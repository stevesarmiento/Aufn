<img src="Aufn/Assets.xcassets/AppIcon.appiconset/AppIcon.png" alt="Aufn Logo" align="right" width="120" />

# 🔴 Aufn
Record, ship, delete.

A simple multitrack overdub recorder for iPhone. Layer takes over each other, hear everything in sync, and ship per-track stems straight into your DAW.

## 🪄 Features

- 🎛️ **Multitrack overdubs** — record a new track while the existing ones play back, sample-aligned via a shared engine start time with per-track latency compensation.
- 💾 **Highest-quality capture** — every take is 32-bit float PCM (CAF) at the hardware sample rate, up to 96 kHz.
- 🎚️ **Mixing** — per-track volume and pan (tap the sliders button on a track to expand), DAW-style **M**ute and **S**olo buttons that work live during playback and overdubs (mute beats solo; solo silences everything else), plus a per-project master fader. Applied live and to the mixdown; stems always stay complete.
- 🌊 **Tape-head transport** — the transport is a tape deck: a dot-matrix waveform of the project flows right-to-left behind a glass capsule record head (Liquid Glass refracts it). Blue dots left of the head are on tape; gray dots right are upcoming; dim dots are blank tape. The red pill morphs to a stop square while recording.
- 🎤 **Input picker** — choose the recording device (built-in mic, USB interface, or a Bluetooth headset mic with a quality warning); your choice is remembered per device.
- 📤 **Stem export** — each track as its own 24-bit WAV (individually, zipped, or as a stereo mixdown) for Logic, Ableton, or anywhere else. Stems are raw by default; toggle "Apply track volume" to bake levels in.
- 🧊 **Liquid Glass UI** — built for iOS 26 with SwiftUI's glass effects; two screens, no clutter.
- 🔊 **Loud playback** — playback routes to the loudspeaker (recording stays on the quieter receiver to minimize bleed); the app nudges you toward headphones for clean overdubs.

## 🛠 Development

The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
xcodebuild -project Aufn.xcodeproj -scheme Aufn -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Tests cover the export pipeline (unit) and the record/overdub flow (UI, simulator mic = your Mac's input):

```sh
xcrun simctl privacy booted grant microphone co.lassidesign.Aufn
xcodebuild -project Aufn.xcodeproj -scheme Aufn -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

> **Note** Overdub latency offsets are computed from `AVAudioSession` input/output latency and stored per track (never baked into audio files). Simulator latencies differ from hardware — fine-tune on a real device.

> **Device-only checks** A few behaviors can't be verified in the simulator: loudspeaker-vs-receiver routing on playback/record, AirPods A2DP monitoring (no speaker override when headphones are connected), and selecting a Bluetooth/USB input. Verify these on hardware.

> **Gotcha for contributors** Never touch `engine.mainMixerNode` after `engine.start()` while the input tap is live on a first take — lazily instantiating the mixer→output graph mid-capture resets the tap and every frame is dropped. Mix settings are applied only when playback players exist (mixer already connected before start). See `AudioEngineController.applyMixSettings`. Likewise never touch `engine.inputNode` before the session is configured for recording — its first access caches the input format, and an unconfigured session yields 0 Hz ("No audio input is available") — and never `detach` a node while a take is live (`removeTrack` only stops; `stopTransport` detaches).

## 🗃 Archive

`archive/` holds the original 2023 single-take recorder built with GPT-4. It's kept for reference; none of its code is used by the current app.

## ✍️ Authors

- Anon ([@_Aufn](https://twitter.com/_Aufn))
- GPT4 ([@OpenAI](https://twitter.com/OpenAI)) — 2023 original, now in `archive/`
- Claude ([@AnthropicAI](https://twitter.com/AnthropicAI)) — 2026 rewrite
