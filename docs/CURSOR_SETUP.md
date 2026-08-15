# Cursor setup

| Cursor id | Role | Quant |
| --- | --- | --- |
| `qwen3827b` | Plan + implement | Unsloth UD-Q4_K_XL |

```bat
install.bat
start.bat
verify.bat
```

Settings → Models:

1. API key = `runtime\api-key.txt`
2. Override Base URL = `runtime\public-base-url.txt` (`https://….trycloudflare.com/v1`)
3. Models = **`qwen3827b`**
4. Do not register `compact3b` in Cursor (proxy-internal summarizer on `:18081`)

Backend: **llama.cpp** OpenAI-compatible API via the auth proxy.

## Model switching

Use **`qwen3827b`** for both plan and implement. The auth proxy only reloads the GPU if you pick a different known id.

Cold loads can take several minutes. If Cursor says it is taking long or returns a loading error, keep **`qwen3827b`** selected and send again after a minute.

## Long Agent threads

Cursor BYOK often assumes 1M context and may not auto-compact before this stack’s real **64K** window. The auth proxy compresses oversized histories using the CPU compact sidecar. Details: [`CONTEXT.md`](CONTEXT.md).

After a large milestone, starting a **new chat** still improves quality vs endless compaction.
