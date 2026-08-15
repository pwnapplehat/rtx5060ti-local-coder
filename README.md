# RTX 5060 Ti Local Coder

Local Cursor coding stack for **NVIDIA GeForce RTX 5060 Ti (16GB)** + **~32GB system RAM**, powered by **llama.cpp** (`llama-server`).

## Models

| Cursor id | Weights | Quant | Role |
| --- | --- | --- | --- |
| **`qwen3827b`** | Qwen3.8 27B | Unsloth **UD-Q4_K_XL** | Plan + implement (single GPU load) |

One coding GGUF is hot on the GPU. Use the same id for Agent, Chat, plan, and implement so Cursor does not trigger 2–5 minute model swaps.

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

Override paths in `config/models.json` if needed. llama.cpp tag is `llamaCppTag` (currently **b10437**, required for Qwen3.8).

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
3. Add model: **`qwen3827b`**
4. Use that id for both plan and implement

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
| Thinking | enabled |

## License

MIT for scripts and configs. Upstream licenses apply to model weights and llama.cpp.
