# -------------------------------------------------------------------------------------
# Konami RLE compression (as used in Contra?)
#
# 00-80     Read another byte, and write it to the output n times.
# 81-FE     Copy n - 128 bytes from input to output.
# FF        End of data
#
# Notes:
#           unknown if 00 is used.  Avoiding.
#
# References:
#           https://www.nesdev.org/wiki/Tile_compression#Konami_RLE
# -------------------------------------------------------------------------------------
formats.add(CompressDef(
    name: "Konami RLE",
    shortName: "konami",
    ops: @[
        Op(
            typ: "repeat",
            byte0: 0..0x80,
            byte1: 0..0xff,
            format: "[1] [0]",
            size: "2",
        ),
        Op(
            typ: "copy",
            byte0: 0x81..0xfe,
            format: "[0]-128 1",
            size: "[0]-127",
        ),
        Op(
            typ: "end",
            byte0: 0xff..0xff,
            size: "1",
        )
    ],
))

# -------------------------------------------------------------------------------------
# Konami RLE compression (as used in Life Force)
#
# Start with a 2 byte PPU address (little endian), then zero or more operations:
#
# 00        Read another byte, and write it to the output 256 times
# 01-7E     Read another byte, and write it to the output n times.
# 7F        Read another two bytes for a new PPU address
# 80        Read another byte, and write it to the output 255 times
# 81-FE     Copy n - 128 bytes from input to output.
# FF        End of data
#
# Notes:
#           00 is never used.  Sometimes listed as copy 0 bytes.  Avoiding.
#           80 can be inconsistant/invalid/error on some games.  Avoiding.
#
# References:
#           https://datacrystal.romhacking.net/wiki/Blades_of_Steel:ROM_map
#           https://www.nesdev.org/wiki/Tile_compression#Konami_RLE
# -------------------------------------------------------------------------------------
formats.add(CompressDef(
    name: "Konami RLE 2",
    shortName: "konami2",
    ops: @[
        Op(
            start: true,
            typ: "address",
            byte0: 0..0xff,
            byte1: 0..0xff,
            format: "[1]*256+[0]",
            size: "2",
        ),
        Op(
            typ: "repeat",
            byte0: 0..0,
            byte1: 0..0xff,
            format: "[1] 256",
            size: "2",
            avoid: true,
        ),
        Op(
            typ: "repeat",
            byte0: 1..0x7e,
            byte1: 0..0xff,
            format: "[1] [0]",
            size: "2",
        ),
        Op(
            typ: "repeat",
            byte0: 0x80..0x80,
            byte1: 0..0xff,
            format: "[1] 255",
            size: "2",
            avoid: true,
        ),
        Op(
            typ: "address",
            byte0: 0x7f..0x7f,
            byte1: 0..0xff,
            byte2: 0..0xff,
            format: "[2]*256+[1]",
            size: "3",
        ),
        Op(
            typ: "copy",
            byte0: 0x81..0xfe,
            format: "[0]-128 1",
            size: "[0]-127",
        ),
        Op(
            typ: "end",
            byte0: 0xff..0xff,
            size: "1",
        )
    ],
))


# Kemko RLE compression (as used in Bugs Bunny Crazy Castle)
#
# Uses a rudimentary RLE compression.
#
# FF xx yy  Output tile xx yy times.
# 00-FE     Copy input to output.
# FF FF 00  End of data.  The second byte can be anything, but FF is used.
#-------------------------------------------------------------------------------------
#
# Select Screen data:
# 03:d7d6 (file offset 0xd7e6)
# 0x33d bytes
formats.add(CompressDef(
    name: "Kemko RLE",
    shortName: "kemko",
    ops: @[
        Op(
            start: true,
            typ: "address",
            format: "0x2000",
            size: "0",
        ),
        Op(
            typ: "end",
            byte0: 0xff..0xff,
            byte1: 0x00..0xff,
            byte2: 0x00..0x00,
            size: "3",
        ),
        Op(
            typ: "repeat",
            byte0: 0xff..0xff,
            byte1: 0..0xff,
            byte2: 0..0xff,
            format: "[1] [2]",
            size: "3",
        ),
        Op(
            typ: "copy",
            byte0: 0x00..0xfe,
            format: "1 0",
            size: "1",
        )
    ],
))

# Used in Super Mario Bros.
# Modified to use both end marker types.
#
# https://www.nesdev.org/wiki/Tile_compression#NES_Stripe_Image_RLE
formats.add(CompressDef(
    name: "NES Stripe Image RLE",
    shortName: "stripe",
    ops: @[
        Op(
            typ: "end",
            byte0: 0x00..0x00,
            size: "1",
        ),
        Op(
            typ: "end",
            byte0: 0x80..0xff,
            size: "1",
        ),
        Op(
            typ: "address",
            byte0: 0..0xff,
            byte1: 0..0xff,
            format: "[0]*256+[1]",
            size: "2",
            noBreak: true,
        ),
        Op(
            typ: "copy",
            byte0: 0x00..0x3f,
            format: "[0] 1",
            size: "[0]+1",
        ),
        Op(
            typ: "repeat",
            byte0: 0x40..0x7f,
            byte1: 0..0xff,
            format: "[1] [0]-63",
            size: "2",
        ),
        Op(
            typ: "copy",
            byte0: 0x80..0xbf,
            format: "[0]-127 1",
            size: "[0]-126",
            addressAdd: "32",
        ),
        Op(
            typ: "repeat",
            byte0: 0xc0..0xff,
            byte1: 0..0xff,
            format: "[1] [0]-191",
            size: "2",
            addressAdd: "32",
        ),
    ],
))

# This is just an uncompressed extraction of a full ppu dump
formats.add(CompressDef(
    name: "Full PPU Dump",
    shortName: "ppudump",
    ops: @[
        Op(
            start: true,
            typ: "address",
            format: "0",
            size: "0",
        ),
        Op(
            typ: "copy",
            byte0: 0x00..0xff,
            format: "0x4000 0",
            size: "0x4000",
            noBreak: true,
        ),
        Op(
            typ: "end",
        )
    ],
))

# -------------------------------------------------------------------------------------
# PackBits
#
# 00-7f     Copy n bytes from input to output.
# 80        No operation
# 81-ff     Read another byte, and write it to the output 257-n times.
#
# References:
#           https://en.wikipedia.org/wiki/PackBits
# -------------------------------------------------------------------------------------
#
# ********** needs testing **********
#
formats.add(CompressDef(
    name: "PackBits",
    shortName: "packbits",
    ops: @[
        Op(
            typ: "repeat",
            byte0: 0x81..0xff,
            byte1: 0..0xff,
            format: "[1] 257-[0]",
            size: "2",
        ),
        Op(
            typ: "copy",
            byte0: 0x00..0x7f,
            format: "[0]+1 1",
            size: "[0]+2",
        ),
    ],
))
