# Models

## `qwen3coder30b` — implement (default)

Unsloth **UD-Q4_K_XL** of Qwen3-Coder 30B-A3B.

Use for Agent/Chat file edits, refactors, patches, and tests.

Thinking is enabled (`enable_thinking=true`). The auth proxy also applies a 2048 `max_tokens` floor so reasoning does not starve `message.content`.

## `qwen3635b` — plan

Unsloth **UD-Q4_K_XL** of Qwen3.6 35B-A3B.

Use for architecture, multi-file plans, and API design.

Thinking is enabled (same accuracy-first policy as the coder).

## `compact3b` — context summarizer

Qwen2.5-3B-Instruct **Q4_K_M** (~2 GB) on a separate `llama-server` at **:18081**, CPU-only (`-ngl 0`).

Used only by the auth proxy when histories approach 64K. Do not add this id in Cursor.

## Switching

Pick the model id in Cursor. The auth proxy reloads `llama-server` with the matching GGUF.

Cold-load after a switch can take minutes. Avoid thrashing plan ↔ implement every message.

Manual:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\11-switch-model.ps1 -Model qwen3635b
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\11-switch-model.ps1 -Model qwen3coder30b
```

## Quants

See [`QUANTIZATION.md`](QUANTIZATION.md). Coding models use Unsloth **UD-Q4_K_XL**. The compact sidecar uses **Q4_K_M**.
