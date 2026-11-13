# Tested hardware and capture format

| Item | Observed value |
|---|---|
| Retail product | Plexgear Moviesaver 600 / Movie Digitizer, Kjell article 99003 |
| USB VID:PID | `1b80:e600` |
| Reported USB name | `USB 28286 Device` |
| Chip register `0x000a` | `0x92` (146), consistent with reported EM2980 |
| Video interface | 0, vendor-specific class `0xff` |
| Tested transport | isochronous IN `0x82`, alternate setting 7 |
| Capacity | `wMaxPacketSize=0x1400`, 3072 bytes per 125 µs |
| Other endpoints | `0x81` interrupt, `0x84` isochronous, `0x8a` bulk |
| Audio | standard USB Audio, macOS audio driver, stereo 48 kHz/16 bit |
| Source | Wii U PAL 576i, 4:3, composite |

Each image field contains 720 × 288 × 2 = 414720 bytes of packed YUYV.
The tested device appends the four-byte trailer `c6 93 05 93`; the parser accepts
either the exact image size or image plus that exact trailer. Field headers begin
`22 5a`; byte 2 supplies the counter/parity used by the recovery experiment.
Continuation headers `88 88 88 88` are stripped at USB packet boundaries. VBI
headers begin `33 95`. Preserve packet boundaries: the raw BIN alone is insufficient.

Only a new field/VBI boundary finalizes a field. The last unfinished field is not
flushed. Invalid lengths, unexpected trailers and USB errors reject the field.
The replay program counts valid fields; the offline preview additionally requires
an even counter immediately followed by the next odd counter modulo 256.

The power register `0x0c` is left unchanged. Register `0x0f` was written `0x87` and
read back `0x07` during the earlier basic test; the cause of bit 7 behavior is not
established. Saved values were restored in that test. Some decoder registers may
have side effects not undone merely by restoring readback values.

An earlier generic bulk experiment produced no data and left the device needing
unplug/reconnect. That experiment is not included as a supported capture path.

Recorded baseline (2026-11-13): 62,391,104 video bytes, 24,064 packets, 32 packets
with errors, 151 field headers. Offline replay with corrected parser: 148 complete
fields, 2 rejected completed fields, 73 usable adjacent frame pairs. WAV: 139,672
stereo samples at 48 kHz (about 2.910 seconds). These are one experiment's results,
not throughput, quality or synchronization guarantees.
