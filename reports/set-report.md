# Corrupt Set Report

## Scope

Known corrupt source members discovered during CocoaSpice library scanning. Source archives remain unchanged.

## Confirmed Corrupt Members

| Set | Member | Status | Evidence |
| --- | --- | --- | --- |
| `/Users/john/Downloads/audio/JoshW/NEC PC-98/0-9/100Yen Disk Vol. 5 (PC-88)(1988)(Onion).tar.zst` | `100yen5pcm.s98` | Corrupt; non-playable | First bytes are `01 10 00 01`, not the required ASCII `S98` signature. |
| `/Users/john/Downloads/audio/JoshW/Nintendo Game Boy Advance/Yuujou no Victory Goal - 4V4 Arashi Get the Goal!! (2001-11-15)(KCE Studios)(Konami)[GBA].tar.zst` | `15 BGM #15.minigsf` | Corrupt; non-playable | Payload begins with zero bytes, not the required `PSF` signature. |

## Scanner Handling

The scanner records these payloads as failed with an explicit `Corrupt S98 payload` or `Corrupt GSF payload` reason. They are not admitted as playable tracks.
