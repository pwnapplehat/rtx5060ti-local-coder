# Stack snapshot

Date: **2026-08-15**

## Components

| Layer | Choice |
| --- | --- |
| Runtime | llama.cpp `llama-server` **b10437** (CUDA 13.3 Windows) |
| Coding quant | Unsloth **UD-Q4_K_XL** |
| Plan + implement | `qwen3827b` (Qwen3.8 27B) |
| Coding server | `127.0.0.1:18080`, `--fit on`, thinking on |
| Compact sidecar | `compact3b` (Qwen2.5-3B-Instruct Q4_K_M) on `127.0.0.1:18081`, CPU `-ngl 0` |
| Edge | Auth proxy `:11435` + Cloudflare quick tunnel |
| Context | Proxy compaction for Cursor BYOK vs real 64K window |

## Security

Bearer auth on the proxy (`runtime/api-key.txt`, gitignored). For stronger exposure control, use a named Cloudflare tunnel + Access.

## Checks performed (2026-08-01)

- Compact `/health` and proxy `compactUpstreamHealth: 200` with coding VRAM near full
- Over-budget chat compacted ~166k → ~14k tokens (`summarize-middle` via sidecar)
- Model-switch stop is scoped to `:18080` so the compact sidecar stays up

## Ops notes

- Quick tunnel URL rotates each `start.bat`; refresh Cursor Override Base URL from `runtime/public-base-url.txt`
- Single coding model avoids plan ↔ implement GPU swaps
- After a large milestone, a new Cursor chat often helps more than further compaction
