# Parakeet-EOU-120M — Streaming ASR Model

Small RNN-T streaming ASR model with an explicit end-of-utterance (EOU)
head for real-time dictation. Runs on CoreML / Neural Engine.

- HuggingFace: [aufklarer/Parakeet-EOU-120M-CoreML-INT8](https://huggingface.co/aufklarer/Parakeet-EOU-120M-CoreML-INT8)
- Module: `Sources/ParakeetStreamingASR/`
- Weights: ~120 MB (INT8)
- Languages: 25 European languages
- Sample rate: 16 kHz

## Architecture

Three CoreML models pipelined per chunk:

### Encoder — cache-aware Conformer with pre_cache loopback

Input mel chunk is 64 frames (640 ms at 10 ms hop, 16 kHz). Encoder takes
six state tensors and emits updated copies each step:

- `pre_cache` — mel cache that loops back to prepend future chunks with the
  recent-past mel context, so the FFT / first conv block sees continuous
  audio across chunk boundaries. 64 frames by default.
- `cache_last_channel` — attention key/value cache, shape
  `[layers, 1, attention_context, hidden]`
- `cache_last_time` — depthwise conv cache for each layer,
  `[layers, 1, hidden, conv_cache]`
- `cache_last_channel_len` — int32 length of the attention cache

Each step returns `encoded_output`, `encoded_length`, and updated copies
of all four caches. Only the first `outputFrames` frames of the encoder
output are new; the rest is future-context overlap, consumed on the next
chunk. The session advances its sample buffer by
`outputFrames * subsampling_factor * hop_length` samples between calls.

### Decoder — fp32 LSTM prediction network

Single-step LSTM that consumes the previous non-blank token and emits a
`decoder_output` embedding plus new `(h, c)` state. Input is fp32 but
model outputs are fp16 on Apple Silicon; the session casts fp16 → fp32
in-place between steps.

### Joint — fuses encoder slice + decoder output, has EOU head

Takes `encoder_output[1,1,H]` and `decoder_output[1,1,H]`, returns logits
over `vocab_size + 1 + 1` classes (vocabulary + blank + EOU). Greedy RNNT
decoding loops per encoder frame, advancing the decoder only on non-blank
emissions. An EOU token fires when the model recognizes sentence / clause
boundary silence.

## Why a separate EOU token

Plain RNNT emits blanks during silence, which the decoder happily
absorbs without signaling "utterance finished." Adding a dedicated EOU
head lets the model make a hard cut for:

- committing the partial to a "final" in the streaming API
- resetting any post-processing state (punctuation, capitalization)
- triggering downstream actions (paste to app, send to LLM, etc.)

In practice the joint's EOU signal is noisy during non-silent pauses
(keyboard clicks, background hum), so production pipelines usually debounce
EOU across several frames and also fall back to a VAD-driven force-finalize
— see `docs/inference/parakeet-streaming-asr-inference.md`.

## Vocabulary

SentencePiece BPE, identical to upstream NeMo Parakeet TDT vocabulary.
`blank_token_id` is the last vocabulary index; `eou_token_id` is
`vocab_size + 1`.

## Config

Runtime config in `ParakeetEOUConfig` (see `Sources/ParakeetStreamingASR/
ParakeetEOUConfig.swift`). Key streaming fields:

| Field | Value | Meaning |
|---|---|---|
| `streaming.melFrames` | 64 | Mel frames per encoder chunk |
| `streaming.outputFrames` | 20 | New encoder output frames per chunk |
| `streaming.preCacheSize` | 64 | Mel frames kept in loopback cache |
| `subsamplingFactor` | 4 | Conformer stride |
| `hopLength` | 160 | 10 ms at 16 kHz |
| `encoderLayers` | 17 | |
| `encoderHidden` | 512 | |
| `attentionContext` | 70 | Attention cache depth |

## See also

- [parakeet-streaming-asr-inference.md](../inference/parakeet-streaming-asr-inference.md) — runtime pipeline, VAD integration, force-finalize
- [parakeet-asr.md](parakeet-asr.md) — non-streaming Parakeet TDT 0.6B
