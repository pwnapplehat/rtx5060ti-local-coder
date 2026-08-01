# Quantization

## Coding models (GPU)

Coding models use **Unsloth Dynamic UD-Q4_K_XL** GGUFs.

| Term | Meaning |
| --- | --- |
| Q4 | 4-bit sweet spot for 16GB GPUs |
| UD | Unsloth Dynamic — sensitive tensors kept at higher precision |
| XL | Quant strategy name (not “extra large model”) |

Sources:

- `unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF` → `*UD-Q4_K_XL*`
- `unsloth/Qwen3.6-35B-A3B-GGUF` → `*UD-Q4_K_XL*`

Avoid for these coding sizes on 16GB: Q2/Q3 (quality), FP16/Q8 (VRAM).

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
```
