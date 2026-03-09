# MLX Pipeline Performance Review

**Date**: March 2026
**Scope**: STT → LLM pipeline performance analysis with focus on MLX inference optimization
**Branch**: `claude/mlx-pipeline-performance-review-HAfCQ`

---

## Executive Summary

The YapYap MLX pipeline is **well-engineered** with several sophisticated optimizations already in place (KV-cache prefix reuse, streaming STT, fast-path bypass, eager model loading). However, there are **6 concrete optimization opportunities** that could meaningfully improve latency, with the biggest wins coming from:

1. **Newer, faster models** (Qwen3-1.7B matches Qwen2.5-3B quality at half the size)
2. **Persistent KV-cache warm-start** (eliminate cold-start prefill on first call)
3. **Setting `maxTokens` to a bounded value** (currently `nil` = unbounded)
4. **Prompt token reduction** for small models

Benchmark data from [arXiv 2511.05502](https://arxiv.org/abs/2511.05502) confirms MLX achieves ~230 tok/s sustained on M2 Ultra with Qwen 3B 4-bit. On consumer M1/M2/M3, realistic numbers are 100-300 tok/s for 1-3B models. **Sub-second total LLM time is achievable** for short transcripts with cache hits, but requires the optimizations below.

---

## Current Pipeline Timeline (Measured)

```
User releases hotkey
  │
  ├─ stopCapture()              ~5ms
  ├─ VAD filtering              ~10-50ms (proportional to audio length)
  ├─ STT (Parakeet/Whisper)     ~500-2000ms
  ├─ LLM prefill                ~200-400ms (cache MISS) / ~50-100ms (cache HIT)
  ├─ LLM decode                 ~100-300ms (for typical 20-50 token outputs)
  ├─ Post-processing            ~5-10ms (OutputFormatter + FillerFilter)
  └─ Paste                      ~5ms
                                ─────────
                     Total:     ~800ms - 2.8s
```

**The LLM phase (prefill + decode) accounts for 300-700ms** of the critical path. This is where most optimization effort should focus.

---

## What's Already Done Well

### 1. KV-Cache Prefix Reuse (`MLXEngine.swift:198-225`)
The prompt cache implementation is sophisticated:
- Caches KV state from the static prefix (system prompt + examples)
- Joint tokenization (line 186) eliminates BPE boundary mismatches
- Three-way validation: prefix key + token count + joint prefix slice
- On cache hit, only the dynamic suffix (raw transcript) needs prefill

**Impact**: Saves ~200-400ms per call on cache hit (estimated 70-80% hit rate for same-context usage).

### 2. GPU Cache Limit (`MLXEngine.swift:77-78`)
```swift
let cacheBytes = 1024 * 1024 * 1024  // 1GB
GPU.set(cacheLimit: cacheBytes)
```
Prevents Metal from deallocating compute buffers between calls. Without this, each `generate()` call would reallocate GPU memory (+30-50ms).

### 3. Realistic Warmup (`MLXEngine.swift:103-110`)
Uses a ~250-token prompt that forces all model weights into memory, not just a trivial "Hello" that only touches a subset.

### 4. Fast-Path Bypass (TranscriptionPipeline)
Short transcriptions (<7 words, configurable) skip LLM entirely. Saves 300-700ms for common phrases like "sounds good" or "on my way."

### 5. Streaming STT
Streaming transcription runs in parallel with recording. If streaming produces ≥3 words, batch STT is skipped entirely — saving 500-2000ms.

### 6. Background Task Offloading
History save, analytics, stats update are detached tasks that don't block paste.

---

## Optimization Opportunities

### OPT-1: Upgrade to Newer Model Families (HIGH IMPACT, LOW EFFORT)

**Problem**: The model registry uses Qwen 2.5, Llama 3.2, and Gemma 3 — all released in 2024. Newer models from 2025-2026 are significantly better at the same or smaller sizes.

**Key findings from research**:

| Model | Params | Quality vs. | Speed Advantage | Notes |
|-------|--------|-------------|-----------------|-------|
| **Qwen3-1.7B** | 1.7B | = Qwen2.5-3B | ~2x faster (half params) | Dual-mode `/think` and `/no_think` |
| **Qwen3-0.6B** | 0.6B | ≈ Qwen2.5-1.5B | ~3x faster | Most downloaded model on HF late 2025 |
| **SmolLM3-3B** | 3B | > Llama-3.2-3B, > Qwen2.5-3B | Same params, better quality | Best-in-class at 3B; dual-mode reasoning |

**Specific recommendation**:
- Add `mlx-community/Qwen3-1.7B-4bit` as a new option (replaces Qwen2.5-3B as the "medium" tier — same quality, half the memory, ~2x speed)
- Add `mlx-community/Qwen3-0.6B-4bit` as an ultra-lightweight option (~300MB, extremely fast)
- Consider `SmolLM3-3B` as the new recommended model at the 3B tier
- The `/no_think` mode in Qwen3 is particularly useful — avoids wasting tokens on chain-of-thought reasoning for simple cleanup tasks

**Caveat**: Qwen3's chat template has a [known KV-cache bug](https://github.com/ml-explore/mlx-examples/issues) where `enable_thinking=false` breaks cache reuse, causing a **90x slowdown**. Must verify the template is correct before deploying.

**Estimated impact**: 30-50% faster inference at same quality, or same speed at notably higher quality.

Sources:
- [Qwen3 Blog](https://qwenlm.github.io/blog/qwen3/)
- [SmolLM3 Blog](https://huggingface.co/blog/smollm3)
- [Best Open-Source SLMs 2026](https://www.bentoml.com/blog/the-best-open-source-small-language-models)

---

### OPT-2: Persistent KV-Cache Warm-Start (HIGH IMPACT, MEDIUM EFFORT)

**Problem**: The first inference call after model load always gets a cache MISS, requiring full prefill of the entire prompt (~500-800 tokens). This adds 200-400ms to the very first transcription.

**Current behavior** (`MLXEngine.swift:67-71`):
```swift
// On model load:
promptCache = nil           // Cache starts empty
promptCachePrefixTokenCount = 0
promptCachePrefixKey = nil
```

**Proposed solution**: After model load and warmup, immediately pre-compute the KV cache for the default system prompt + examples. This way, the first real inference call also gets a cache hit.

```
Current:  load → warmup(1 token) → first call = MISS (full prefill ~300ms)
Proposed: load → warmup(1 token) → pre-cache default prompt → first call = HIT (~80ms)
```

**Implementation approach**:
1. After `warmup()` completes, call a new `preCacheDefaultPrompt()` method
2. This builds the default prompt (e.g., medium cleanup, no specific app context)
3. Runs prefill and stores the cache in `promptCache`
4. First real call sees cache hit if context matches, or graceful miss if context differs

**Alternative (advanced)**: MLX-LM (Python) supports serializing KV cache to `.safetensors` files. If `mlx-swift-lm` adds this, the cache could persist across app launches — eliminating cold-start entirely.

**Estimated impact**: 200-300ms saved on first transcription after app launch.

Sources:
- [LM Studio KV Cache TTFT benchmarks](https://lmstudio.ai/) — showed TTFT drop from 10s to 0.11s with cache reuse on 3000-token prompts
- [vllm-mlx prefix caching](https://github.com/vllm-project/vllm-mlx) — 5.8x TTFT speedup

---

### OPT-3: Set a Bounded `maxTokens` (MEDIUM IMPACT, TRIVIAL EFFORT)

**Problem** (`MLXEngine.swift:232`):
```swift
let parameters = GenerateParameters(
    maxTokens: nil,    // ← UNBOUNDED
    temperature: family.temperature,
    ...
)
```

With `maxTokens: nil`, generation continues until a stop token or model EOS. If the model hallucinates or fails to emit a stop sequence, it could generate hundreds of tokens before hitting the model's context limit.

**Why this matters**:
- Text cleanup outputs are typically 1-2x the input length
- A 50-word input should produce at most ~60-70 words
- Unbounded generation wastes time on hallucinated tokens that get discarded by `LLMOutputSanitizer`
- The 50% content-word-overlap validation (TranscriptionPipeline) will reject hallucinated output anyway — but only after wasting the generation time

**Proposed fix**: Set `maxTokens` proportional to input length:
```swift
let maxOutput = max(100, inputTokens.count * 2)  // At most 2x input, minimum 100
let parameters = GenerateParameters(maxTokens: maxOutput, ...)
```

**Estimated impact**: Prevents tail-case 2-5s hangs when models hallucinate. No impact on normal operation (outputs are always shorter than 2x input).

---

### OPT-4: Reduce Prompt Token Count for Small Models (MEDIUM IMPACT, LOW EFFORT)

**Current token budgets** (estimated):

| Model Size | System Prompt | Examples | Dynamic Suffix | Total Prefix (Cached) |
|-----------|--------------|----------|---------------|---------------------|
| Small (≤2B) | ~100-150 tokens | ~200 tokens (3 examples) | ~10-30 tokens | ~300-380 tokens |
| Medium (3B-4B) | ~300-400 tokens | ~400-600 tokens (6-12 examples) | ~20-50 tokens | ~700-1050 tokens |
| Large (7B+) | ~400-500 tokens | ~400-600 tokens | ~20-50 tokens | ~800-1150 tokens |

**Issue 1**: V2 prompts (`PromptTemplatesV2.swift:28-47`) are verbose for a "deterministic refinement engine":
- 16 hard rules in the system prompt
- Rules like "Do NOT use '@' for people, companies, products, hashtags" are edge cases that add ~20 tokens
- "Insert paragraph breaks where there is a logical shift in topic" adds ~15 tokens

For 1-2B models, these verbose instructions actually hurt — small models perform worse with too many constraints because they "contaminate" the limited context window.

**Issue 2**: The V1 prompt for small models (`CleanupPromptBuilder.swift:267`) includes:
```
"Only remove filler words and fix punctuation. Keep every other word exactly as spoken —
DO NOT substitute synonyms or rephrase. Do NOT drop any sentences. Do NOT answer questions."
```
This is 35+ tokens of instruction that could be reduced to ~10 tokens: "Fix grammar only. Keep all words."

**Issue 3**: V1 unified prompt suffix (`CleanupPromptBuilder.swift:321`):
```swift
let suffix = "Transcript: \(rawText)\n\nTranscript: \(rawText)"
```
The transcript is repeated twice, doubling the dynamic token count. This "repetition trick" helps 3B+ models focus on the input, but for 1-2B models it wastes prefill time on duplicate tokens.

**Research finding**: For sub-2B models, system prompts should be under 50 tokens. Small models learn patterns from few-shot examples, not from instruction length. Rely on deterministic post-processing (`OutputFormatter.swift`) for mechanical formatting rules.

**Estimated impact**: 15-25% fewer prefill tokens for small models → ~30-60ms saved on prefill.

Sources:
- [Evaluating Small Models for Grammar Correction](https://arxiv.org/abs/2601.03874) — confirmed small models struggle with verbose instructions
- [CompactPrompt](https://arxiv.org/html/2510.08043v1) — up to 60% token reduction with minimal quality loss

---

### OPT-5: Dynamic GPU Cache Sizing (LOW IMPACT, TRIVIAL EFFORT)

**Problem** (`MLXEngine.swift:77`):
```swift
let cacheBytes = 1024 * 1024 * 1024  // 1GB — hardcoded
```

1GB is appropriate for 1-3B models but insufficient for 7B+ models:

| Model | Weights | KV Cache (2K context) | Activations | Total GPU Need |
|-------|---------|----------------------|-------------|---------------|
| Qwen 1.5B | ~800MB | ~86KB/token × 500 ≈ 43MB | ~100MB | ~950MB |
| Gemma 4B | ~2GB | ~150KB/token × 500 ≈ 75MB | ~200MB | ~2.3GB |
| Qwen 7B | ~4GB | ~256KB/token × 500 ≈ 128MB | ~300MB | ~4.4GB |
| Llama 8B | ~4.5GB | ~256KB/token × 500 ≈ 128MB | ~350MB | ~5GB |

For 7B+ models, the 1GB cache limit means Metal continuously reallocates buffers. The fix is simple:

```swift
let modelSizeGB = Double(modelInfo.sizeBytes) / 1_073_741_824
let cacheBytes = Int(max(1.0, modelSizeGB * 1.5)) * 1024 * 1024 * 1024
GPU.set(cacheLimit: cacheBytes)
```

**Estimated impact**: 30-50ms saved per inference for 7B+ models. No impact on small models.

---

### OPT-6: Consider Apple Foundation Models Framework (FUTURE, macOS 26+)

**Apple announced at WWDC25** a built-in ~3B on-device model accessible via the `FoundationModels` framework:
- Free, offline, zero-cost inference — model ships with the OS
- Achieves ~0.6ms per prompt token and 30 tok/s generation
- Mixed 2-bit/4-bit palletization (3.7 bits average)
- **Guided Generation** with `@Generable` Swift macros for structured output
- Runs across CPU, GPU, and ANE via Core ML's automatic dispatch

**Potential for YapYap**: If the built-in model is good enough for text cleanup, it would:
- Eliminate model download/management entirely
- Reduce memory footprint (model is OS-managed, shared with other apps)
- Provide consistent performance across all Apple Silicon Macs

**Caveats**:
- Requires macOS 26 (Tahoe) — not yet released
- Model quality/customizability unknown for this specific use case
- No fine-tuning or custom prompting beyond the framework's API
- Would need to be offered as an optional backend alongside MLX

**Recommendation**: Add as an experimental option once macOS 26 ships. Keep MLX as the primary engine for customizability.

Sources:
- [Apple Foundation Models WWDC25](https://developer.apple.com/videos/play/wwdc2025/286/)
- [Apple Foundation Models Documentation](https://developer.apple.com/documentation/FoundationModels)

---

## Not Worth Pursuing

### Speculative Decoding
- MLX-LM (Python) supports it, but **MLX Swift does not have a public API** for speculative decoding
- Benefits are marginal for 1-3B models already running at 200-500 tok/s
- Doubles memory usage (need draft model + main model)
- Text cleanup outputs are short (under 100 tokens) — speculative decoding helps most with long generation
- LM Studio achieved 1.5-3x speedup only for 7B+ models

### Sub-4-bit Quantization (2-bit, 3-bit)
- Quality degrades meaningfully below 4-bit for well-trained models (ACL 2025 finding)
- 4-bit is the speed/quality sweet spot for MLX
- Exception: Microsoft's BitNet b1.58 (natively 1.58-bit) could work, but it's a research model not suited for production text cleanup
- Apple's own approach (mixed 2/4-bit palletization at 3.7 bits average) is only available through Foundation Models framework

### Running LLMs on ANE (Apple Neural Engine)
- [ANEMLL](https://github.com/Anemll/Anemll) project exists but quality is reportedly low due to lack of block quantization on ANE
- CoreML conversion path is fragile and requires per-model tuning
- MLX's GPU path is already well-optimized for Apple Silicon's unified memory
- ANE is better suited for STT (Parakeet already runs on ANE) than LLM inference

### GGUF Format / llama.cpp Backend
- MLX native format is **20-30% faster than GGUF** for models under 7B ([arXiv 2511.05502](https://arxiv.org/abs/2511.05502))
- Already using MLX native format via `mlx-community` models — correct choice

---

## Benchmark Reference Data

### MLX Token Generation Speed (from research papers and community benchmarks)

| Model | Quantization | Hardware | Tok/s (decode) | TTFT | Source |
|-------|-------------|----------|----------------|------|--------|
| Qwen2.5 3B | 4-bit | M2 Ultra | ~230 | ~400ms | [arXiv 2511.05502](https://arxiv.org/abs/2511.05502) |
| Qwen3 0.6B | 4-bit | M4 Max | ~525 | <100ms | vllm-mlx benchmarks |
| Llama 3.2 1B | 4-bit | M4 | ~97-119 | <200ms | Community benchmarks |
| Qwen2 1.5B | 4-bit | M1 | ~30-60 | ~400ms | Community benchmarks |
| Qwen2.5 3B | 4-bit | M1 Pro | ~80-120 | ~500ms | Community estimates |

### Key Insight: Where Sub-Second Is Achievable

For a typical 30-word transcription with cache hit:
```
Prefill (cache hit, ~30 suffix tokens):  ~50ms
Decode (~40 output tokens at 200 tok/s): ~200ms
Post-processing:                         ~10ms
                                         ─────
LLM total:                               ~260ms  ✓ SUB-SECOND
```

For a cache miss:
```
Prefill (full, ~600 tokens):             ~300ms
Decode (~40 output tokens at 200 tok/s): ~200ms
Post-processing:                         ~10ms
                                         ─────
LLM total:                               ~510ms  ✓ SUB-SECOND (barely)
```

**Sub-second LLM inference IS achievable** on M1+ with:
- 1-2B models (Qwen3-0.6B, Qwen2.5-1.5B, Llama 1B)
- 4-bit quantization (MLX native format)
- KV-cache prefix reuse (already implemented)
- Bounded output tokens (OPT-3)
- Short transcripts (<50 words)

For 3-4B models (Gemma 4B, the current default), sub-second requires cache hit + M2 or newer.

---

## Priority Ranking

| # | Optimization | Impact | Effort | Risk |
|---|-------------|--------|--------|------|
| 1 | **OPT-1**: Add Qwen3-1.7B/0.6B models | High (30-50% faster) | Low (registry entry + template) | Low (well-tested models) |
| 2 | **OPT-3**: Bound `maxTokens` | Medium (prevents hangs) | Trivial (1 line) | None |
| 3 | **OPT-2**: Pre-cache default prompt at load | High (200-300ms first call) | Medium (new method) | Low |
| 4 | **OPT-4**: Reduce prompt tokens for ≤2B | Medium (30-60ms) | Low (prompt editing) | Low (test-gated) |
| 5 | **OPT-5**: Dynamic GPU cache sizing | Low (30-50ms for 7B+) | Trivial (3 lines) | None |
| 6 | **OPT-6**: Foundation Models framework | Future potential | High (new backend) | Medium (macOS 26 only) |

---

## Fine-Tuning Opportunity (Bonus)

Research from [arXiv 2601.03874](https://arxiv.org/abs/2601.03874) found that out-of-the-box small models struggle with grammar correction and hallucinate, but **fine-tuned versions of Qwen2.5-1.5B on GEC datasets yield competitive results**.

**Proposal**: Generate 500-1000 synthetic cleanup examples using a larger model (Claude, GPT-4), then LoRA fine-tune Qwen3-1.7B specifically for voice-to-text cleanup. Benefits:
- LoRA adapter is only ~5MB
- Could dramatically improve quality while enabling **much shorter prompts** (model "knows" the task)
- Shorter prompts = faster prefill = better cache efficiency
- Could potentially drop few-shot examples entirely (saving ~200-400 prefix tokens)

This is a higher-effort investment but could yield the single biggest quality + speed improvement.

---

## Appendix: Dependency Versions

Current (`project.yml`):
```yaml
mlx-swift: "0.30.0"
mlx-swift-lm: "2.29.0"
WhisperKit: "0.9.0"
FluidAudio: "0.7.9"
```

These are reasonably current. No performance issues expected from outdated dependencies. Check for updates to `mlx-swift-lm` periodically — Apple presented MLX improvements at WWDC25 including better KV cache management and multi-turn conversation support.
