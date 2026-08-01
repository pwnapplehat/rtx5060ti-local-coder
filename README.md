# RTX 5060 Ti Local Coder

Local Cursor coding stack for **NVIDIA GeForce RTX 5060 Ti (16GB)** + **~32GB system RAM**, powered by **llama.cpp** (`llama-server`).

## Models

| Cursor id | Weights | Quant | Role |
| --- | --- | --- | --- |
| **`qwen3coder30b`** | Qwen3-Coder 30B-A3B | Unsloth **UD-Q4_K_XL** | Implementation / Agent |
| **`qwen3635b`** | Qwen3.6 35B-A3B | Unsloth **UD-Q4_K_XL** | Planning / architecture |

Only one coding model is loaded on the GPU at a time. Pick the id in Cursor; the auth proxy switches `llama-server` on `:18080`.

## Context compaction

Cursor BYOK often assumes a **1M** context window, so client-side compaction may never fire before this stack’s real **64K** limit. The auth proxy compresses oversized threads before they reach llama-server.

| Piece | Detail |
| --- | --- |
| Alias | `compact3b` (proxy-internal; do not add in Cursor) |
| Weights | Qwen2.5-3B-Instruct **Q4_K_M** (~2 GB) |
| Process | Second `llama-server` on `127.0.0.1:18081` |
| Placement | CPU only (`-ngl 0`) so summarization does not consume RTX VRAM |

Details: [`docs/CONTEXT.md`](docs/CONTEXT.md).

## Default paths

| Path | Purpose |
| --- | --- |
| `E:\LlamaCpp` | `llama-server.exe` + CUDA runtime |
| `E:\LlamaModels\…` | GGUF weights |
| `runtime\` | API key, tunnel URL, PIDs (gitignored) |

Override paths in `config/models.json` if needed.

## Quick start

```bat
install.bat
start.bat
verify.bat
```

| Command | Purpose |
| --- | --- |
| `install.bat` | Install llama.cpp binaries and download GGUFs |
| `start.bat` | Coding server + compact sidecar + auth proxy + Cloudflare tunnel |
| `stop.bat` | Tear down |
| `status.bat` | GPU / GGUF / health |
| `verify.bat` | Structure checks + smoke tests |

## Cursor setup

1. OpenAI API Key = contents of `runtime\api-key.txt`
2. Override Base URL = contents of `runtime\public-base-url.txt` (after `start.bat`)
3. Add models: **`qwen3coder30b`**, **`qwen3635b`**
4. Default: **`qwen3coder30b`**

More detail: [`docs/CURSOR_SETUP.md`](docs/CURSOR_SETUP.md).

## Docs

- [`docs/MODELS.md`](docs/MODELS.md) — when to use each model
- [`docs/CONTEXT.md`](docs/CONTEXT.md) — 64K window + proxy compaction
- [`docs/QUANTIZATION.md`](docs/QUANTIZATION.md) — GGUF choices
- [`docs/OPS.md`](docs/OPS.md) — ports, start order, CPU threads
- [`docs/PRODUCTION_AUDIT.md`](docs/PRODUCTION_AUDIT.md) — stack snapshot

## Tuning (accuracy-first)

| Setting | Value |
| --- | --- |
| Context (`-c`) | 65536 |
| VRAM fit | `--fit on` (do not force `-ngl`; that disables the fitter) |
| CPU threads | `cpuThreads` / `cpuThreadsBatch` in `config/models.json` (default 10) |
| Flash attention | on |
| KV cache | `q8_0` |
| Thinking | enabled for both Cursor models |

## License

MIT for scripts and configs. Upstream licenses apply to model weights and llama.cpp.
