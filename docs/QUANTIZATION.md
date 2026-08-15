# Quantization

## Coding model (GPU)

The coding model uses **Unsloth Dynamic UD-Q4_K_XL** GGUF.

| Term | Meaning |
| --- | --- |
| Q4 | 4-bit sweet spot for 16GB GPUs |
| UD | Unsloth Dynamic — sensitive tensors kept at higher precision |
| XL | Quant strategy name (not “extra large model”) |

Source:

- `unsloth/Qwen3.8-27B-GGUF` → `Qwen3.8-27B-UD-Q4_K_XL.gguf` (~17.9 GB)

`--fit on` plus `fitCtxMin` 32768 lets weights spill to RAM if VRAM is tight. If load still fails or context collapses, switch `include` / `ggufGlob` to `*UD-Q3_K_XL*` (~13.4 GB) and re-pull.

Avoid for this size on 16GB: Q2 (quality), Q5+/Q8/FP16 (VRAM).

## Compact sidecar (CPU)

Proxy-only summarizer:

| Field | Value |
| --- | --- |
| Source | `Qwen/Qwen2.5-3B-Instruct-GGUF` |
| File | `*Q4_K_M*` (~2 GB) |
| Why | Small instruct model is enough for dense continuity briefs on CPU |

## Pull

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\02-pull-models.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\02-pull-models.ps1 -Target compact
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\02-pull-models.ps1 -Target qwen3827b
```
