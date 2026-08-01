#!/usr/bin/env node
/**
 * Bearer-auth gateway in front of local llama-server (OpenAI-compatible).
 *
 * - Requires Authorization: Bearer <AUTH_PROXY_SECRET>
 * - Ensures the requested Cursor model is loaded (switches llama-server if needed)
 * - Injects chat_template_kwargs.enable_thinking per model role
 * - Compacts oversized chat histories (Cursor BYOK assumes 1M ctx and often
 *   never auto-compacts before our real 64K limit)
 * - Proxies /v1/* to llama-server
 *
 * Env:
 *   AUTH_PROXY_PORT     (default 11435)
 *   AUTH_PROXY_SECRET   (required, >=24 chars)
 *   LLAMA_UPSTREAM      (default http://127.0.0.1:18080)
 *   COMPACT_UPSTREAM    (default http://127.0.0.1:18081) CPU compact sidecar
 *   COMPACT_MODEL       (default compact3b)
 *   USE_COMPACT_SIDECAR (default 1) when 0, summarize via coding upstream
 *   REPO_ROOT           (default parent of proxy/)
 *   MODELS_CONFIG       (default <repo>/config/models.json)
 */
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { URL } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = process.env.REPO_ROOT || path.resolve(__dirname, "..");
const modelsConfigPath =
  process.env.MODELS_CONFIG || path.join(repoRoot, "config", "models.json");

const port = Number(process.env.AUTH_PROXY_PORT || 11435);
const secret = (process.env.AUTH_PROXY_SECRET || "").trim();
const upstreamBase = (process.env.LLAMA_UPSTREAM || "http://127.0.0.1:18080").replace(/\/$/, "");
const compactUpstreamBase = (
  process.env.COMPACT_UPSTREAM || "http://127.0.0.1:18081"
).replace(/\/$/, "");
const compactModelAlias = (process.env.COMPACT_MODEL || "compact3b").trim() || "compact3b";
const useCompactSidecar = !["0", "false", "no", "off"].includes(
  String(process.env.USE_COMPACT_SIDECAR ?? "1").trim().toLowerCase()
);
const runtimeDir = path.join(repoRoot, "runtime");
const activeModelFile = path.join(runtimeDir, "active-model.txt");
const switchScript = path.join(repoRoot, "scripts", "11-switch-model.ps1");

if (!secret || secret.length < 24) {
  console.error("AUTH_PROXY_SECRET must be set to a strong secret (>=24 chars)");
  process.exit(1);
}

const modelsConfig = JSON.parse(fs.readFileSync(modelsConfigPath, "utf8"));
const knownModels = new Set(Object.keys(modelsConfig.models || {}));
const contextSize = Number(modelsConfig.contextSize || 65536);
const compactCfg = {
  enabled: true,
  reserveCompletionTokens: 4096,
  safetyMarginTokens: 2048,
  keepRecentMessages: 14,
  summarizeMiddle: true,
  useCompactSidecar: true,
  charsPerToken: 3.5,
  maxSingleMessageChars: 48000,
  ...(modelsConfig.contextCompact || {}),
};

let activeModel = readActiveModel();
let swapChain = Promise.resolve();

function readActiveModel() {
  try {
    if (fs.existsSync(activeModelFile)) {
      return fs.readFileSync(activeModelFile, "utf8").trim();
    }
  } catch {
    /* ignore */
  }
  return "";
}

function unauthorized(res) {
  res.writeHead(401, {
    "Content-Type": "application/json",
    "WWW-Authenticate": 'Bearer realm="llamacpp-coder"',
  });
  res.end(JSON.stringify({ error: { message: "Unauthorized", type: "auth_error" } }));
}

function isAuthorized(req) {
  const h = req.headers.authorization || "";
  if (!h.startsWith("Bearer ")) return false;
  const token = h.slice("Bearer ".length).trim();
  if (token.length !== secret.length) return false;
  let mismatch = 0;
  for (let i = 0; i < token.length; i++) {
    mismatch |= token.charCodeAt(i) ^ secret.charCodeAt(i);
  }
  return mismatch === 0;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

function normalizeModelName(name) {
  return String(name || "")
    .trim()
    .replace(/:latest$/i, "");
}

function messageText(msg) {
  if (!msg || msg.content == null) return "";
  if (typeof msg.content === "string") return msg.content;
  if (Array.isArray(msg.content)) {
    return msg.content
      .map((part) => {
        if (typeof part === "string") return part;
        if (part && typeof part.text === "string") return part.text;
        return JSON.stringify(part);
      })
      .join("\n");
  }
  return String(msg.content);
}

function estimateTokensFromText(text) {
  const chars = String(text || "").length;
  return Math.max(1, Math.ceil(chars / Number(compactCfg.charsPerToken || 3.5)));
}

function estimateMessageTokens(msg) {
  let n = estimateTokensFromText(messageText(msg));
  if (msg && msg.tool_calls) {
    n += estimateTokensFromText(JSON.stringify(msg.tool_calls));
  }
  if (msg && msg.name) n += estimateTokensFromText(msg.name);
  n += 8;
  return n;
}

function estimateMessagesTokens(messages) {
  return (messages || []).reduce((sum, m) => sum + estimateMessageTokens(m), 0);
}

function trimOversizedMessage(msg) {
  const maxChars = Number(compactCfg.maxSingleMessageChars || 48000);
  const text = messageText(msg);
  if (text.length <= maxChars) return msg;
  const keep = Math.floor(maxChars / 2) - 80;
  const clipped =
    text.slice(0, keep) +
    `\n\n[... truncated ${text.length - keep * 2} chars by local auth-proxy ...]\n\n` +
    text.slice(-keep);
  return { ...msg, content: clipped };
}

function promptBudgetTokens(openaiBody) {
  const reserve = Number(compactCfg.reserveCompletionTokens || 4096);
  const safety = Number(compactCfg.safetyMarginTokens || 2048);
  const reqMax = Number(openaiBody.max_tokens || openaiBody.max_completion_tokens || 0);
  const completionReserve = Math.max(reserve, Number.isFinite(reqMax) ? reqMax : 0);
  return Math.max(2048, contextSize - completionReserve - safety);
}

function splitMessages(messages) {
  const system = [];
  const rest = [];
  for (const m of messages || []) {
    if (m && m.role === "system" && system.length < 4) system.push(m);
    else rest.push(m);
  }
  const keepN = Math.max(2, Number(compactCfg.keepRecentMessages || 14));
  if (rest.length <= keepN) {
    return { system, middle: [], recent: rest };
  }
  return {
    system,
    middle: rest.slice(0, rest.length - keepN),
    recent: rest.slice(rest.length - keepN),
  };
}

function upstreamJson(method, reqPath, bodyObj, timeoutMs, baseUrl = upstreamBase) {
  const bodyBuf = bodyObj ? Buffer.from(JSON.stringify(bodyObj), "utf8") : null;
  return new Promise((resolve, reject) => {
    const headers = { "content-type": "application/json" };
    if (bodyBuf) headers["content-length"] = String(bodyBuf.length);
    const up = upstreamRequest(method, reqPath, headers, bodyBuf, baseUrl);
    const timer = setTimeout(() => {
      up.destroy();
      reject(new Error(`upstream timeout after ${timeoutMs}ms`));
    }, timeoutMs);
    let raw = Buffer.alloc(0);
    up.on("response", (upstreamRes) => {
      upstreamRes.on("data", (c) => {
        raw = Buffer.concat([raw, c]);
      });
      upstreamRes.on("end", () => {
        clearTimeout(timer);
        const text = raw.toString("utf8");
        if ((upstreamRes.statusCode || 500) >= 400) {
          reject(new Error(`upstream ${upstreamRes.statusCode}: ${text.slice(0, 500)}`));
          return;
        }
        try {
          resolve(JSON.parse(text || "{}"));
        } catch (err) {
          reject(err);
        }
      });
    });
    up.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });
    if (bodyBuf) up.write(bodyBuf);
    up.end();
  });
}

async function summarizeMiddle(modelId, middleMessages) {
  // Cap input hard so the compressor itself cannot blow the compact window.
  const parts = [];
  let used = 0;
  const cap = 24000;
  for (const m of middleMessages) {
    const role = (m && m.role) || "unknown";
    const text = messageText(m).slice(0, 1200);
    const chunk = `### ${role}\n${text}\n\n`;
    if (used + chunk.length > cap) break;
    parts.push(chunk);
    used += chunk.length;
  }
  const blob = parts.join("");

  const preferSidecar =
    useCompactSidecar && compactCfg.useCompactSidecar !== false;
  const summarizeBase = preferSidecar ? compactUpstreamBase : upstreamBase;
  const summarizeModel = preferSidecar ? compactModelAlias : modelId;

  const compactReq = {
    model: summarizeModel,
    temperature: 0.1,
    max_tokens: 700,
    stream: false,
    chat_template_kwargs: { enable_thinking: false },
    messages: [
      {
        role: "system",
        content:
          "Compress prior coding-agent context. Dense factual brief only: goals, decisions, file paths, APIs, errors, constraints, TODOs. No fluff.",
      },
      {
        role: "user",
        content: `Continuity brief (<=500 words):\n\n${blob}`,
      },
    ],
  };

  try {
    const resp = await upstreamJson(
      "POST",
      "/v1/chat/completions",
      compactReq,
      90000,
      summarizeBase
    );
    const content = resp?.choices?.[0]?.message?.content;
    if (!content || !String(content).trim()) {
      throw new Error("empty compaction summary");
    }
    return String(content).trim();
  } catch (err) {
    if (!preferSidecar || summarizeBase === upstreamBase) throw err;
    console.warn(
      `compact sidecar failed (${err.message}); falling back to coding upstream`
    );
    const fallbackReq = { ...compactReq, model: modelId };
    const resp = await upstreamJson(
      "POST",
      "/v1/chat/completions",
      fallbackReq,
      90000,
      upstreamBase
    );
    const content = resp?.choices?.[0]?.message?.content;
    if (!content || !String(content).trim()) {
      throw new Error("empty compaction summary (coding fallback)");
    }
    return String(content).trim();
  }
}

function extractiveMiddleBrief(middleMessages) {
  const lines = [];
  for (const m of middleMessages.slice(0, 30)) {
    const role = (m && m.role) || "unknown";
    const text = messageText(m).replace(/\s+/g, " ").trim().slice(0, 220);
    if (text) lines.push(`- (${role}) ${text}`);
  }
  if (middleMessages.length > 30) {
    lines.push(`- ... plus ${middleMessages.length - 30} older messages omitted`);
  }
  return lines.join("\n");
}

async function compactMessagesIfNeeded(openaiBody) {
  if (!compactCfg.enabled) {
    return { body: openaiBody, meta: { compacted: false, reason: "disabled" } };
  }
  if (!Array.isArray(openaiBody.messages) || openaiBody.messages.length === 0) {
    return { body: openaiBody, meta: { compacted: false, reason: "no-messages" } };
  }

  let messages = openaiBody.messages.map(trimOversizedMessage);
  const budget = promptBudgetTokens(openaiBody);
  let tokens = estimateMessagesTokens(messages);
  if (tokens <= budget) {
    return {
      body: { ...openaiBody, messages },
      meta: { compacted: false, tokensBefore: tokens, tokensAfter: tokens, budget },
    };
  }

  const { system, middle, recent } = splitMessages(messages);
  let rebuilt = [...system, ...recent];
  let mode = "drop-middle";

  if (middle.length > 0) {
    let brief = extractiveMiddleBrief(middle);
    if (compactCfg.summarizeMiddle) {
      try {
        brief = await summarizeMiddle(normalizeModelName(openaiBody.model), middle);
        mode = "summarize-middle";
      } catch (err) {
        console.warn(`compaction summarize failed, using extractive brief: ${err.message}`);
        mode = "extractive-middle";
      }
    } else {
      mode = "extractive-middle";
    }
    rebuilt = [
      ...system,
      {
        role: "system",
        content:
          "[local-context-compact] Earlier turns compressed to fit the local 64K window " +
          `(${middle.length} messages):\n\n${brief}`,
      },
      ...recent,
    ];
  }

  while (estimateMessagesTokens(rebuilt) > budget && rebuilt.length > system.length + 1) {
    const dropAt = system.length;
    if (dropAt >= rebuilt.length - 1) break;
    rebuilt.splice(dropAt, 1);
    mode = `${mode}+trim-recent`;
  }

  if (estimateMessagesTokens(rebuilt) > budget && rebuilt.length > 0) {
    const last = rebuilt[rebuilt.length - 1];
    const text = messageText(last);
    const allowChars = Math.max(2000, Math.floor(budget * Number(compactCfg.charsPerToken || 3.5) * 0.55));
    if (text.length > allowChars) {
      rebuilt[rebuilt.length - 1] = {
        ...last,
        content: text.slice(0, allowChars) + "\n\n[... hard-truncated by local auth-proxy to fit context ...]",
      };
      mode = `${mode}+hard-trim-last`;
    }
  }

  const tokensAfter = estimateMessagesTokens(rebuilt);
  console.log(
    `context-compact mode=${mode} before=${tokens} after=${tokensAfter} budget=${budget} msgs=${messages.length}->${rebuilt.length}`
  );
  return {
    body: { ...openaiBody, messages: rebuilt },
    meta: {
      compacted: true,
      mode,
      tokensBefore: tokens,
      tokensAfter,
      budget,
      messagesBefore: messages.length,
      messagesAfter: rebuilt.length,
    },
  };
}

function runSwitch(modelId) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      "powershell.exe",
      ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", switchScript, "-Model", modelId],
      { cwd: repoRoot, windowsHide: true }
    );
    let stderr = "";
    child.stderr.on("data", (d) => {
      stderr += d.toString("utf8");
    });
    child.stdout.on("data", (d) => {
      process.stdout.write(d);
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`switch-model failed (${code}): ${stderr.slice(-2000)}`));
    });
  });
}

function ensureModelLoaded(requested) {
  const target = normalizeModelName(requested);
  if (!knownModels.has(target)) {
    return Promise.reject(
      new Error(`Unknown model '${requested}'. Use: ${[...knownModels].join(", ")}`)
    );
  }
  const current = readActiveModel() || activeModel;
  if (current === target) {
    activeModel = target;
    return Promise.resolve();
  }

  swapChain = swapChain
    .catch(() => {})
    .then(async () => {
      const again = readActiveModel() || activeModel;
      if (again === target) {
        activeModel = target;
        return;
      }
      console.log(`switching llama-server -> ${target}`);
      await runSwitch(target);
      activeModel = target;
      console.log(`coding-model-active=${target}`);
    });
  return swapChain;
}

function applyThinkingPolicy(openaiBody) {
  const modelId = normalizeModelName(openaiBody.model);
  const entry = modelsConfig.models[modelId];
  if (!entry) return openaiBody;
  const enableThinking = Boolean(entry.enableThinking);
  const kwargs = {
    ...(openaiBody.chat_template_kwargs || {}),
    enable_thinking: enableThinking,
  };
  const patched = { ...openaiBody, chat_template_kwargs: kwargs };
  if (enableThinking) {
    const floor = 2048;
    const current = Number(patched.max_tokens || patched.max_completion_tokens || 0);
    if (!Number.isFinite(current) || current < floor) {
      patched.max_tokens = floor;
      delete patched.max_completion_tokens;
    }
  }
  return patched;
}

function upstreamRequest(method, reqPath, headers, bodyBuf, baseUrl = upstreamBase) {
  const target = new URL(reqPath, baseUrl);
  const hdrs = { ...headers };
  delete hdrs.host;
  hdrs.host = `${target.hostname}:${target.port || 80}`;
  if (bodyBuf && bodyBuf.length) {
    hdrs["content-length"] = String(bodyBuf.length);
  }
  return http.request({
    protocol: target.protocol,
    hostname: target.hostname,
    port: target.port || 80,
    path: target.pathname + target.search,
    method,
    headers: hdrs,
  });
}

function proxyRaw(req, res, bodyBuf, overridePath, extraHeaders) {
  const targetPath = overridePath || req.url || "/";
  const headers = { ...req.headers, ...(extraHeaders || {}) };
  const up = upstreamRequest(req.method, targetPath, headers, bodyBuf);
  up.on("response", (upstreamRes) => {
    const outHeaders = { ...upstreamRes.headers };
    if (extraHeaders && extraHeaders["x-local-context-compact"]) {
      outHeaders["x-local-context-compact"] = extraHeaders["x-local-context-compact"];
    }
    res.writeHead(upstreamRes.statusCode || 502, outHeaders);
    upstreamRes.pipe(res);
  });
  up.on("error", (err) => {
    if (!res.headersSent) {
      res.writeHead(502, { "Content-Type": "application/json" });
    }
    res.end(JSON.stringify({ error: { message: `Upstream error: ${err.message}`, type: "proxy_error" } }));
  });
  if (bodyBuf && bodyBuf.length) up.write(bodyBuf);
  up.end();
}

async function handleChatCompletions(req, res, bodyBuf) {
  let openaiBody;
  try {
    openaiBody = JSON.parse(bodyBuf.toString("utf8") || "{}");
  } catch {
    res.writeHead(400, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: { message: "Invalid JSON body", type: "invalid_request_error" } }));
    return;
  }

  try {
    await ensureModelLoaded(openaiBody.model);
  } catch (err) {
    res.writeHead(400, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: { message: String(err.message || err), type: "model_error" } }));
    return;
  }

  let compactMeta = { compacted: false };
  try {
    const compacted = await compactMessagesIfNeeded(openaiBody);
    openaiBody = compacted.body;
    compactMeta = compacted.meta;
  } catch (err) {
    console.warn(`context compact error: ${err.message}`);
  }

  const patched = applyThinkingPolicy(openaiBody);
  const payloadBuf = Buffer.from(JSON.stringify(patched), "utf8");
  const compactHeader = Buffer.from(JSON.stringify(compactMeta), "utf8").toString("base64url");
  proxyRaw(req, res, payloadBuf, "/v1/chat/completions", {
    "x-local-context-compact": compactHeader,
  });
}

const server = http.createServer(async (req, res) => {
  const reqPath = (req.url || "").split("?")[0];

  if (req.method === "GET" && reqPath === "/healthz") {
    let upstream = "unknown";
    let compact = "unknown";
    try {
      await new Promise((resolve, reject) => {
        const u = upstreamRequest("GET", "/health", {}, null);
        u.on("response", (r) => {
          upstream = String(r.statusCode || 0);
          r.resume();
          r.on("end", resolve);
        });
        u.on("error", reject);
        u.end();
      });
    } catch {
      upstream = "down";
    }
    try {
      await new Promise((resolve, reject) => {
        const u = upstreamRequest("GET", "/health", {}, null, compactUpstreamBase);
        u.on("response", (r) => {
          compact = String(r.statusCode || 0);
          r.resume();
          r.on("end", resolve);
        });
        u.on("error", reject);
        u.end();
      });
    } catch {
      compact = "down";
    }
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(
      JSON.stringify({
        status: "ok",
        service: "llamacpp-auth-proxy",
        activeModel: readActiveModel() || activeModel || null,
        upstreamHealth: upstream,
        compactUpstreamHealth: compact,
        compactModel: compactModelAlias,
        useCompactSidecar:
          useCompactSidecar && compactCfg.useCompactSidecar !== false,
        contextSize,
        contextCompact: Boolean(compactCfg.enabled),
      })
    );
    return;
  }

  if (!isAuthorized(req)) {
    unauthorized(res);
    return;
  }

  try {
    const bodyBuf = ["POST", "PUT", "PATCH"].includes(req.method || "") ? await readBody(req) : Buffer.alloc(0);
    if (req.method === "POST" && (reqPath === "/v1/chat/completions" || reqPath === "/chat/completions")) {
      await handleChatCompletions(req, res, bodyBuf);
      return;
    }
    if (req.method === "GET" && (reqPath === "/v1/models" || reqPath === "/models")) {
      // Advertise real context so clients that honor it don't assume 1M.
      const data = [...knownModels].map((id) => ({
        id,
        object: "model",
        owned_by: "local-llamacpp",
        context_length: contextSize,
        max_model_len: contextSize,
      }));
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ object: "list", data }));
      return;
    }
    proxyRaw(req, res, bodyBuf);
  } catch (err) {
    if (!res.headersSent) {
      res.writeHead(500, { "Content-Type": "application/json" });
    }
    res.end(JSON.stringify({ error: { message: String(err?.message || err), type: "proxy_error" } }));
  }
});

server.requestTimeout = 0;
server.headersTimeout = 0;
server.keepAliveTimeout = 120000;

server.listen(port, "127.0.0.1", () => {
  console.log(
    `llamacpp-auth-proxy listening on 127.0.0.1:${port} -> ${upstreamBase} (compact ${compactUpstreamBase} model=${compactModelAlias})`
  );  console.log(`models: ${[...knownModels].join(", ")}`);
  console.log(`contextSize=${contextSize} compact=${compactCfg.enabled}`);
});
