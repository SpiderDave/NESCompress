```
NESCompress v2024.11.26 (alpha) by SpiderDave (https://github.com/spiderdave)

Compress or decompress data from NES games.  Supported formats:
  * Konami RLE compression (as used in Life Force)
  * Kemko RLE compression (as used in Bugs Bunny Crazy Castle)

Usage: NESCompress [opts]

Options:
  -c, --compress:filename         filename to compress
  -d, --decompress:filename       filename to decompress
  -m, --method:method             compression method
  -a, --ppuaddr:address           ppu address (c)
  -o, --outputfile:filename       output filename (c)
  -0, --nt0:filename              output filename for nametable 0 (d)
  -1, --nt1:filename              output filename for nametable 1 (d)
  -2, --nt2:filename              output filename for nametable 2 (d)
  -3, --nt3:filename              output filename for nametable 3 (d)
  -b, --bkpal:filename            output filename for background palette (d)
  -s, --spritepal:filename        output filename for sprite palette (d)
  -h, --help                      Show this help
  -v, --version                   show detailed version information

Items labeled with (d) apply only to decompressing.
Items labeled with (c) apply only to compressing.

Valid compression methods are: [konami, kemko]

When specifying filenames, you may also use a colon at the end and add
a file offset.

Examples:
    NESCompress -d:"Castlevania III - Dracula's Curse (USA).nes:0xb580" -0:"nt0.nam"
    NESCompress -c:"uncompressed.nam" -a:0x2000 -o:"compressed.nam"
    NESCompress -c:"custom.nam" -o:"cv3Edit.nes:0xb580"

```