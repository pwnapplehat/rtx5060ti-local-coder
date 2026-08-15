# Models

## `qwen3827b` — plan + implement (default)

Unsloth **UD-Q4_K_XL** of Qwen3.8 27B (~17.9 GB GGUF). Dense hybrid (Gated DeltaNet); needs a recent llama.cpp (see `llamaCppTag` in `config/models.json`).

Use this one id for Agent/Chat, architecture, and file edits. A single GPU load avoids plan ↔ implement swaps.

Thinking is enabled (`enable_thinking=true`). The auth proxy also applies a 2048 `max_tokens` floor so reasoning does not starve `message.content`.

If `--fit` cannot keep a useful context on 16GB, fall back to Unsloth **UD-Q3_K_XL** (~13.4 GB) by changing `include` / `ggufGlob` in `config/models.json` and re-running the pull script.

## `compact3b` — context summarizer

Qwen2.5-3B-Instruct **Q4_K_M** (~2 GB) on a separate `llama-server` at **:18081**, CPU-only (`-ngl 0`).

Used only by the auth proxy when histories approach 64K. Do not add this id in Cursor.

## Switching

Model ids come from `config/models.json`. With a single coding model, Cursor should stay on **`qwen3827b`**.

Manual reload:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\11-switch-model.ps1 -Model qwen3827b
```

## Quants

See [`QUANTIZATION.md`](QUANTIZATION.md). The coding model uses Unsloth **UD-Q4_K_XL**. The compact sidecar uses **Q4_K_M**.
