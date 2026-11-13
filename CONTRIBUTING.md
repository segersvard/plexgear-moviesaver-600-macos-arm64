# Contributing

Keep the tested command-line prototype buildable independently of Xcode signing.
Run `make test` and `make` on Apple Silicon before submitting a change. CI must
never open USB devices or request microphone access. Preserve licensing notices.

For hardware reports, state product label, VID/PID, chip ID, Mac/OS version,
source standard, connector and results. Remove serial numbers, personal paths,
recordings and unrelated USB-device details before posting logs. Publish media
only if you have the right to share it.

Separate parser tests from hardware changes. New register profiles should name
their source and tested hardware; do not apply untested profiles automatically.
Document any change to power registers, firmware, interface ownership or reset.

The immediate milestone is a reusable ARM64 stream engine feeding a CMIO Camera
Extension, with bounded buffering, useful timestamps, stop/restart and unplug
handling. A successful short command-line capture is not evidence of an installed
system camera. Test each camera client explicitly before marking it supported.

Signed release contributions are welcome. Do not commit certificates, signing
keys, provisioning profiles or credentials. Build signing separately from the
ordinary source/test workflow. Redistribution must comply with the GPL.
