# Toward an installable macOS camera

## Implemented

The standalone prototype accesses the vendor-specific USB video interface through
IOUSBHost, initializes the bridge/decoder, queues isochronous input, validates PAL
fields and separately records the adapter's standard USB audio using AudioQueue.

## Not implemented

There is no CMIO provider/device/stream, containing activation app, Xcode project,
signed system extension or installer yet. There is no OBS, Final Cut Pro or iMovie
live-source verification. Do not advertise the current prototype as a driver.

## Proposed implementation

1. Extract USB ownership, register journal, start/stop and capture queue into a
   reusable engine. Replace the three-second/64 MiB limits with bounded buffering.
   Define behavior for no signal, unplugging, sleep and cancellation.
2. Assemble adjacent fields without pairing across dropped data; assign timestamps
   from the USB timing and preserve field order. Choose and document whether the
   public stream is interlaced 576i/25 or deinterlaced 576p/50. Validate 4:3 metadata.
3. Build an ARM64 Core Media I/O Camera Extension and containing macOS app. Publish
   CVPixelBuffers with explicit format, frame duration and host-clock timestamps.
   Validate direct USB access within the extension's sandbox; do not assume the
   standalone process's permissions automatically transfer to an extension.
4. Keep audio through the existing standard USB audio interface initially. Measure
   video/audio clock drift and synchronization. A virtual video camera does not
   automatically provide an associated audio input in every application.
5. Add activation/deactivation UI using OSSystemExtensionManager and test signed
   installation, removal and upgrades. Validate OBS, Final Cut Pro and iMovie
   independently, including each application's import/capture restrictions.

The video interface is vendor-specific, not UVC. A UVC override DriverKit component
should not be introduced without evidence of an interface ownership conflict.

## Signing and packaging

Apple's normal Camera Extension distribution requires code signing, matching team
identities for the containing app and extension, appropriate entitlements, and the
applicable notarization/App Store requirements. Extension activation is performed
by its containing app; copying files using a `.pkg` does not bypass validation.

Gatekeeper approval of a downloaded app and authorization of a system extension
are different checks. Ad-hoc signing is useful for some local builds but is not a
replacement for Developer ID distribution of a system extension. Development
overrides documented by Apple involve changes to system protections and are not
an ordinary end-user installation path. This project does not make those changes.

Legacy DAL plugins require a legacy-camera opt-in on current macOS versions.
Apple documents reduced camera-indicator behavior for that route; it is not the
planned default. Neither DAL availability on macOS 28 nor editor compatibility
is established here.

References:

- https://developer.apple.com/documentation/coremediaio/creating-a-camera-extension-with-core-media-i-o
- https://developer.apple.com/documentation/systemextensions
- https://developer.apple.com/documentation/systemextensions/debugging-and-testing-system-extensions
- https://developer.apple.com/videos/play/wwdc2022/10022/
- https://support.apple.com/108387
