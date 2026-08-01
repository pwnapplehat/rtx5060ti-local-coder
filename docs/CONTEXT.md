# Context windows

Configured in `config/models.json` → `contextSize`: **65536**.

## Why Cursor can “lock” near 64K

Cursor custom/BYOK models often assume a **1M** context window in the UI. Auto-compaction is keyed off that assumption, so it may never fire before this stack’s real 64K budget — then requests fail or stall.

Cloud providers compact on their side. llama-server does not compact chat history for you. `--context-shift` only helps long *generation*, not a prompt that already exceeds `-c`.

## Proxy compaction

`proxy/auth-proxy.mjs` compresses oversized histories before forwarding:

1. Estimate tokens (~chars / 3.5; conservative for code)
2. Budget = `65536 - completion reserve - safety`
3. Keep system prompts + last ~14 messages
4. Summarize the dropped middle on the **CPU compact sidecar** (`compact3b` on `:18081`, `-ngl 0`) so summarization does not consume RTX VRAM
5. If the sidecar is down: fall back to the coding upstream, then an extractive brief
6. If still over budget: trim older recent turns, then hard-trim the last user message
7. Advertise `context_length: 65536` on `/v1/models`

Knobs: `config/models.json` → `contextCompact` + `compactModel`.

## Why a small dedicated summarizer

| Option | Notes |
| --- | --- |
| Same 30B/35B for summarize | Works, but queues the GPU for a dull compress job |
| **Qwen2.5-3B-Instruct Q4_K_M (~2 GB)** | Instruct-tuned, small, CPU-resident sidecar |

## VRAM fit

Keep `--fit on` for coding servers. Forcing `-ngl` aborts the fitter and can tank large-prompt speed. The compact sidecar stays at `-ngl 0`.

| Model | Role |
| --- | --- |
| `qwen3coder30b` | Implement |
| `qwen3635b` | Plan |
| `compact3b` | Proxy-only summarizer |

## Tip

Compaction keeps long Agent threads usable. Starting a **new Cursor chat** after a big milestone still improves quality more than endless compression.
