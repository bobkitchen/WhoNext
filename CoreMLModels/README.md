---
license: other
license_name: mixed
license_link: LICENSE.md
tags:
  - speaker-diarization
  - coreml
  - apple
  - macos
  - ios
  - sortformer
  - wespeaker
  - speaker-embedding
language:
  - en
pipeline_tag: audio-classification
---

# Speaker Diarization CoreML Models

CoreML conversions of speaker diarization and speaker embedding models for on-device inference on Apple platforms.

## Models

| Model | Original | Size | Description |
|-------|----------|------|-------------|
| `sortformer_4spk_v21.mlpackage` | [nvidia/diar_streaming_sortformer_4spk-v2.1](https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2.1) | 441 MB | Sortformer diarization model — end-to-end neural speaker diarization supporting up to 4 speakers, streaming capable |
| `wespeaker_resnet34.mlpackage` | [WeSpeaker ResNet34](https://github.com/wenet-e2e/wespeaker) | 25 MB | ResNet34 speaker embedding model — extracts 256-dim speaker embeddings for speaker verification and identification |

## Format

Both models are in Apple `.mlpackage` format (FP32). On first load, CoreML compiles them to `.mlmodelc` and caches the compiled version for subsequent fast loading.

- **Sortformer**: Input `mel_features (B, 128, T)` → Output `speaker_probs (B, T/8, 4)` sigmoid probabilities per speaker per frame
- **ResNet34**: Input `fbank_features (1, 80, T)` → Output `embedding (1, 256)` speaker embedding vector

## Usage

These models are designed for use with the [AxiiDiarization](https://github.com/AugustDev/AxiiDiarization) Swift library:

```swift
import AxiiDiarization

let pipeline = try DiarizationPipeline(
    sortformerModelPath: "path/to/sortformer_4spk_v21.mlpackage",
    embModelPath: "path/to/wespeaker_resnet34.mlpackage"
)

let result = try pipeline.run(samples: audioSamples)
for segment in result.segments {
    print("\(segment.speaker.label): \(segment.start)s - \(segment.end)s")
}
```

## Licenses

The models in this repository have separate licenses from their original authors:

- **Sortformer v2.1**: Licensed by NVIDIA Corporation under the [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/). Commercial use permitted. See original model card: [nvidia/diar_streaming_sortformer_4spk-v2.1](https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2.1)

- **WeSpeaker ResNet34**: Licensed under [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0). See original project: [wenet-e2e/wespeaker](https://github.com/wenet-e2e/wespeaker)

The CoreML conversion code and this repository are MIT licensed.

## Acknowledgments

- NVIDIA NeMo team for the Sortformer diarization model
- WeSpeaker / WeNet team for the ResNet34 speaker embedding model
