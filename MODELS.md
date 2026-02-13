# YapYap Model Guide

Comprehensive guide to speech-to-text and language models used in YapYap.

## Overview

YapYap uses two types of models:
1. **STT (Speech-to-Text)** — Converts your voice to raw text
2. **LLM (Language Model)** — Cleans up the raw text (removes fillers, fixes grammar)

All models run **100% offline** on your Mac. No internet required after initial download.

## STT Models

### Parakeet TDT v3 (Recommended)

**Size**: ~600MB
**Engine**: FluidAudio (CoreML)
**Hardware**: Apple Neural Engine (ANE)
**Speed**: ⚡️ Fastest (runs on dedicated ML accelerator)

**Pros**:
- Runs on Neural Engine → no GPU usage → no fan noise
- Faster than Whisper for short recordings
- Lower power consumption
- Good accuracy for English

**Cons**:
- English-only (no multilingual support)
- Slightly lower accuracy than Whisper Large

**Best for**: Daily use, quick transcriptions, battery efficiency

**Download**: Settings → Models → Parakeet TDT v3 → Download

---

### Whisper Large v3 Turbo

**Size**: ~1.5GB
**Engine**: WhisperKit (CoreML)
**Hardware**: Apple Neural Engine + GPU
**Speed**: Good (~2-3x real-time on M1)

**Pros**:
- Best accuracy of all models
- 99 languages supported
- Handles accents and noisy audio well
- Turbo variant faster than original Large v3

**Cons**:
- Requires 16GB RAM for optimal performance
- Slower than Parakeet
- Larger download size

**Best for**: Multilingual use, challenging audio, maximum accuracy

**Languages**: English, Spanish, French, German, Italian, Portuguese, Dutch, Polish, Russian, Japanese, Korean, Chinese, Arabic, Hindi, and 85+ more

**Download**: Settings → Models → Whisper Large v3 Turbo → Download

---

### Whisper Medium

**Size**: ~769MB
**Engine**: WhisperKit (CoreML)
**Hardware**: Apple Neural Engine + GPU
**Speed**: Fast (~4-5x real-time on M1)

**Pros**:
- Good balance of speed and accuracy
- Multilingual (same 99 languages as Large)
- Lower RAM requirement (8GB OK)
- Smaller than Large

**Cons**:
- Less accurate than Large for difficult audio
- Slower than Parakeet

**Best for**: Balanced performance, multilingual, 8GB RAM Macs

**Download**: Settings → Models → Whisper Medium → Download

---

### Whisper Small

**Size**: ~244MB
**Engine**: WhisperKit (CoreML)
**Hardware**: Apple Neural Engine
**Speed**: Very fast (~6-8x real-time on M1)

**Pros**:
- Smallest Whisper model
- Fast downloads
- Low RAM usage
- Still multilingual

**Cons**:
- Lower accuracy than Medium/Large
- May struggle with accents or background noise

**Best for**: Testing, low-spec Macs, quick setup

**Download**: Settings → Models → Whisper Small → Download

---

## LLM Cleanup Models

### Qwen 2.5 1.5B (Recommended)

**Size**: ~800MB (4-bit quantized)
**Engine**: MLX Swift
**Hardware**: Apple Silicon GPU
**Speed**: ⚡️ Very fast (~200-500 tokens/sec on M1)

**Pros**:
- Fast inference
- Multilingual (English, Chinese, Spanish, French, German, Japanese, etc.)
- Good instruction following
- Low RAM usage

**Cons**:
- Smaller than 3B/7B variants → less nuanced rewrites

**Best for**: Daily use, fast cleanup, multilingual support

**Context window**: 32K tokens
**Training cutoff**: September 2023

**Download**: Settings → Models → Qwen 2.5 1.5B → Download

---

### Qwen 2.5 3B

**Size**: ~2.0GB (4-bit quantized)
**Engine**: MLX Swift
**Hardware**: Apple Silicon GPU
**Speed**: Fast (~150-300 tokens/sec on M1)

**Pros**:
- Better rewrites than 1.5B
- Still fast enough for real-time use
- Same multilingual support

**Cons**:
- Larger download
- Slightly slower than 1.5B

**Best for**: Higher quality cleanup, willing to sacrifice 1-2 seconds

**Download**: Settings → Models → Qwen 2.5 3B → Download

---

### Qwen 2.5 7B

**Size**: ~4.7GB (4-bit quantized)
**Engine**: MLX Swift
**Hardware**: Apple Silicon GPU
**Speed**: Good (~80-150 tokens/sec on M1)

**Pros**:
- Best Qwen model for cleanup quality
- Can handle complex rewrite instructions
- Excellent multilingual

**Cons**:
- Requires 16GB RAM
- Noticeably slower inference
- Large download

**Best for**: Maximum quality, long-form editing, non-time-critical use

**Download**: Settings → Models → Qwen 2.5 7B → Download

---

### Llama 3.2 1B

**Size**: ~800MB (4-bit quantized)
**Engine**: MLX Swift
**Hardware**: Apple Silicon GPU
**Speed**: Very fast (~250-500 tokens/sec on M1)

**Pros**:
- Fast inference
- Great for English
- Concise, direct outputs

**Cons**:
- English-focused (limited multilingual)
- Smaller model → less nuanced

**Best for**: English-only users, speed priority

**Download**: Settings → Models → Llama 3.2 1B → Download

---

### Llama 3.2 3B

**Size**: ~2.0GB (4-bit quantized)
**Engine**: MLX Swift
**Hardware**: Apple Silicon GPU
**Speed**: Fast (~120-250 tokens/sec on M1)

**Pros**:
- Better quality than 1B
- Still very fast
- Strong instruction following

**Cons**:
- English-focused

**Best for**: English users wanting better quality than 1B

**Download**: Settings → Models → Llama 3.2 3B → Download

---

### Llama 3.1 8B

**Size**: ~4.7GB (4-bit quantized)
**Engine**: MLX Swift
**Hardware**: Apple Silicon GPU
**Speed**: Good (~70-120 tokens/sec on M1)

**Pros**:
- Excellent rewrite quality
- Handles complex instructions well
- Long context window (128K)

**Cons**:
- Requires 16GB RAM
- Slower inference
- Large download

**Best for**: Maximum English quality, complex rewrites

**Download**: Settings → Models → Llama 3.1 8B → Download

---

### Gemma 2 2B

**Size**: ~1.2GB (4-bit quantized)
**Engine**: MLX Swift
**Hardware**: Apple Silicon GPU
**Speed**: Fast (~150-300 tokens/sec on M1)

**Pros**:
- Good balance of size and quality
- Strong instruction following
- Trained by Google DeepMind

**Cons**:
- Not as widely tested as Qwen/Llama

**Best for**: Alternative to Qwen 3B, English-focused

**Download**: Settings → Models → Gemma 2 2B → Download

---

## Model Compatibility Matrix

| Mac Model | RAM | Recommended STT | Recommended LLM |
|-----------|-----|-----------------|-----------------|
| M1 MacBook Air (8GB) | 8GB | Parakeet / Whisper Small | Qwen 1.5B / Llama 1B |
| M1 MacBook Pro (16GB) | 16GB | Parakeet / Whisper Large | Qwen 3B / Llama 3B |
| M1 Max/Ultra (32GB+) | 32GB+ | Whisper Large Turbo | Qwen 7B / Llama 8B |
| M2/M3 (8GB) | 8GB | Parakeet / Whisper Medium | Qwen 1.5B |
| M2/M3 (16GB+) | 16GB+ | Whisper Large Turbo | Qwen 3B / Llama 3B |

## Disk Space Requirements

### Minimal Setup (~1.5GB)
- Whisper Small (244MB)
- Qwen 1.5B (800MB)
- App + overhead (~500MB)

### Recommended Setup (~2.5GB)
- Parakeet TDT v3 (600MB)
- Qwen 2.5 3B (2.0GB)
- App + overhead (~500MB)

### Maximum Quality (~6GB)
- Whisper Large v3 Turbo (1.5GB)
- Qwen 7B or Llama 8B (4.7GB)
- App + overhead (~500MB)

**Tip**: You can install multiple models and switch between them. Delete unused models to free space.

## Model Storage Location

All models are downloaded to:
```
~/Library/Application Support/YapYap/Models/
├── STT/
│   ├── whisper-large-v3-turbo/
│   ├── whisper-medium/
│   ├── whisper-small/
│   └── parakeet-tdt-v3/
└── LLM/
    ├── qwen-2.5-1.5b/
    ├── qwen-2.5-3b/
    ├── llama-3.2-1b/
    └── gemma-2-2b/
```

To free space:
```bash
# Delete all models
rm -rf ~/Library/Application\ Support/YapYap/Models/

# Delete specific STT model
rm -rf ~/Library/Application\ Support/YapYap/Models/STT/whisper-large-v3-turbo/

# Delete specific LLM model
rm -rf ~/Library/Application\ Support/YapYap/Models/LLM/qwen-2.5-7b/
```

Or use Settings → Models → Delete button.

## Model Download Sources

All models are downloaded from HuggingFace:

**STT Models**:
- WhisperKit: `argmaxinc/whisperkit-coreml`
- FluidAudio: `FluidInference/parakeet-tdt-1.1b-v3`

**LLM Models**:
- Qwen: `Qwen/Qwen2.5-{1.5B,3B,7B}-Instruct-4bit`
- Llama: `mlx-community/Llama-3.2-{1B,3B}-Instruct-4bit`
- Gemma: `mlx-community/gemma-2-2b-it-4bit`

## Performance Tuning

### For Speed
- Use Parakeet (fastest STT)
- Use Qwen 1.5B or Llama 1B (fastest LLM)
- Enable GPU acceleration (Settings → Models)
- Reduce cleanup level to "Light"

### For Quality
- Use Whisper Large v3 Turbo (best STT)
- Use Qwen 7B or Llama 8B (best LLM)
- Set cleanup level to "Heavy"
- Use "Formal" formality setting

### For Battery Life
- Use Parakeet (ANE-only, no GPU)
- Use smaller LLM (1.5B or 1B)
- Disable floating bar animations
- Use push-to-talk (not hands-free)

## Troubleshooting

### "Model download failed"
- Check internet connection
- Retry download
- Try smaller model first
- Check available disk space

### "Out of memory" error
- Close other apps
- Use smaller models (Whisper Small, Qwen 1.5B)
- Upgrade RAM if possible

### "Slow transcription"
- Switch to faster model (Parakeet, Whisper Small)
- Enable GPU acceleration
- Close background apps
- Use lighter LLM (1.5B instead of 7B)

### "Model not found" error
- Re-download model from Settings
- Check `~/Library/Application Support/YapYap/Models/` exists
- Verify model files aren't corrupted

---

*Last updated: 2026-02-13*
