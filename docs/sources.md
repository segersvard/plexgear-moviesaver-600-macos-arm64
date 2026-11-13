# Sources and provenance

`src/plexgear-pal.m` builds on the earlier independently written ARM64 transport
test and adapts GPL-2.0-or-later Linux em28xx initialization sequences. Preserve
Linux author notices in the source and NOTICE.

Linux files inspected on 2026-11-13 (Git blob identifiers, not release tags):

| File under `drivers/media/usb/em28xx/` | Git blob SHA |
|---|---|
| `em28xx-core.c` | `62a1c25a2de13e25fe25b8e8001244378d57190d` |
| `em28xx-video.c` | `84424284d4869b9b78933f0efffb662837024b50` |
| `em28xx-reg.h` | `8931733a8e2416d266371d59461b9a4eedf53a2a` |
| `em28xx.h` | `7f249ddf6179c84d1f3de73146dfed5e5fbb3395` |
| `em28xx-cards.c` | `1d4f30cba8de847708bb9b337216860621d201da` |

Upstream: https://github.com/torvalds/linux/tree/master/drivers/media/usb/em28xx

The original Kjell `CapDriver_v19.147.10` Intel user-space driver was inspected
statically for the `EmpiaUSBDevice2828x::fDeviceInit` bridge profile and
`fSetHardwareCaptureDimension` PAL field-height value. It was not installed or run
and is not included in this repository. The implementation does not load it.

The actual field trailer and useful packet framing were verified against the
local hardware recording. No recordings or per-device serial numbers are published.

Native API references:

- https://developer.apple.com/documentation/iousbhost/iousbhostinterface
- https://developer.apple.com/documentation/iousbhost/iousbhostpipe
- https://developer.apple.com/documentation/audiotoolbox/audio-queue-services
- https://developer.apple.com/documentation/avfoundation/avcapturedevice

`SOURCES-original.txt` preserves the earlier Swedish v5 provenance notes, including
their **historical** pre-test status. Those status lines were superseded by the
hardware results in README.md and hardware.md. The external experiment linked in
those notes was background reading, not evidence of this unit's behavior.

Retail model identification: Kjell manual, **Moviesaver 600**, item **99003**:
https://www.kjell.com/globalassets/mediaassets/701282_99003_manual_en_no_sv.pdf
