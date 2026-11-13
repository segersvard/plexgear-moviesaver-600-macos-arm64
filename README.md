# Plexgear Moviesaver 600 on Apple Silicon

Project: `plexgear-moviesaver-600-macos-arm64`.

Native ARM64 research prototype for the Plexgear Moviesaver 600 / Movie Digitizer sold by Kjell & Company as article **99003**, USB **1b80:e600**, chip ID **146 (0x92)**.

**Status: short PAL capture works on one tested unit. This is not yet an installable system camera driver.** No Rosetta, vendor executable, kernel extension or firmware download is used.

The goal is a modern Core Media I/O Camera Extension that exposes the hardware to macOS camera clients. OBS, Final Cut Pro and iMovie compatibility must each be tested; this repository does not currently provide that integration.

## Verified so far

- MacBook Air M2, macOS 27.0.1, build 26A434.
- Wii U composite output at PAL 576i, 4:3, plus analog stereo audio.
- Approximately three seconds of asynchronous isochronous video and separate USB audio.
- A recorded run yielded 148 complete valid fields and 73 adjacent frame pairs; actual color video was recovered.
- The audio file contained stereo 48 kHz, 16-bit PCM with nonzero samples. Audio/video synchronization has not been measured.
- The corrected v5.1 parser accepts the observed four-byte field trailer. It passes synthetic tests and replay of the original recording. v5.1 itself has not been recaptured on hardware.

One hardware variant and one source are tested. Other devices sold under the same product name, NTSC, S-Video, long captures, hot unplugging and macOS 28 are unverified.

## Build and test

Requires an Apple Silicon Mac and Apple's Command Line Tools. Full Xcode and a paid developer account are not needed for this command-line prototype.

```sh
make test
make
file build/plexgear-pal
```

Build and tests do not open the USB device. To deliberately run the short hardware experiment, connect a PAL composite source and stereo audio, then run from Terminal:

```sh
mkdir -p captures
./build/plexgear-pal "captures/run-$(date +%Y%m%d-%H%M%S)"
```

macOS may ask for audio-input permission. The code selects a USB audio device whose name/UID contains `2828`; it does not fall back to the Mac microphone. Multiple matching adapters are not supported reliably yet.

This is experimental hardware access: it writes bridge and decoder registers, selects video alternate setting 7 and attempts to restore saved values afterwards. Do not run concurrently with another capture program. If the device stops responding or restoration fails, unplug and reconnect it. Restoration of register values does not prove all internal decoder state is restored; power cycling remains the clean reset.

Outputs include raw USB data, a packet-boundary TSV log, register diagnostics, a first-field PNG and a WAV. These may contain private recordings or device information: inspect before sharing. No example recordings are included in this repository.

## Recover a short movie

Python 3 is needed only for offline recovery. It is not used by the USB capture program.

```sh
python3 tools/recover.py captures/RUN recovered
./build/make-jpeg recovered/video-720x576.yuyv recovered/jpeg
python3 tools/make-mov.py recovered/jpeg captures/RUN/wiiu-ljud.wav recovered/preview.mov
```

This weaves adjacent even/odd fields, resamples 720×576 to 768×576 for a 4:3 preview and writes Motion JPEG plus PCM. Dropped fields are omitted and remaining frames are placed at nominal 25 fps; video and audio are both placed at time zero. **It is a diagnostic preview, not a synchronized archival recording or a deinterlacer.** The original interlaced YUYV data is retained.

## Driver and installer roadmap

See [camera-extension.md](docs/camera-extension.md) and [hardware.md](docs/hardware.md).

A `.pkg` wrapper alone cannot make an unsigned Camera Extension load. Normal distribution needs a correctly signed containing app and extension, appropriate entitlements and Apple's distribution requirements. “Open Anyway” is not a substitute for those checks. This repository contains no security-bypass installer and no ready-to-install camera extension.

A contributor with an appropriate Apple Developer identity can help build and sign future releases. The code and build instructions remain public so others can reproduce, audit and improve the implementation.

## Contributing and license

Please read [CONTRIBUTING.md](CONTRIBUTING.md) and [NOTICE](NOTICE). Useful contributions include extracting a reusable streaming engine, field timestamps and buffering, robust unplug/reconnect handling, CMIO integration and per-application compatibility tests.

The combined capture program is **GPL-2.0-or-later** because it adapts Linux em28xx register sequences. Independently marked parser/audio modules retain MIT notices. See [LICENSE](LICENSE), [LICENSE-MIT](LICENSE-MIT) and [sources.md](docs/sources.md). No original vendor driver binaries are redistributed. This is an independent project, unaffiliated with Plexgear, Kjell & Company or Apple.
