# Ops

## Layout

| Item | Default |
| --- | --- |
| Binaries | `E:\LlamaCpp` (llama.cpp CUDA) |
| Coding GGUFs | Unsloth **UD-Q4_K_XL** under `E:\LlamaModels\` — see `QUANTIZATION.md` |
| Compact GGUF | Qwen2.5-3B-Instruct **Q4_K_M** → `E:\LlamaModels\compact-qwen25-3b\` |
| Cursor models | `qwen3coder30b` (implement), `qwen3635b` (plan) |

## Ports

| Service | Bind |
| --- | --- |
| Coding `llama-server` | `127.0.0.1:18080` |
| Compact sidecar | `127.0.0.1:18081` (`-ngl 0`) |
| Auth proxy | `127.0.0.1:11435` → Cloudflare quick tunnel |

## CPU threads

Defaults in `config/models.json`: coding `-t/-tb 10`, compact `-t 10` (physical cores on a 10-core CPU).  
These help MoE RAM spill and compaction. Leaving more of the coding model on CPU (beyond what `--fit` already spills) usually slows Agent work.

## Lifecycle

- Commands: `install.bat` `start.bat` `stop.bat` `status.bat` `verify.bat`
- Start order: coding server → compact sidecar → auth proxy → tunnel
- Stop is port-scoped: switching coding models does not stop `:18081`
- Model switch harden: `gpuSettleSeconds` (default 8) + `startRetries` (default 3) for intermittent Blackwell flash-attn init fails
- Long chats: proxy compaction — see `CONTEXT.md`
