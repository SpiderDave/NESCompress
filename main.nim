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

import
    os,
    resource/resource,
    parseopt,
    parseutils,
    strutils,
    strformat,
    tables

import appinfo

const app: App = App(
    name: "NESCompress",
    url: "https://github.com/spiderdave",
    author: "SpiderDave",
    stage: "alpha",
    description: """
Compress or decompress data from NES games.  Supported formats:
  * Konami RLE compression (as used in Life Force)
  * Kemko RLE compression (as used in Bugs Bunny Crazy Castle)"""
)

type
  Op = object
    typ: string
    format: string
    byte0: HSlice[system.int, system.int] = -1 .. -1
    byte1: HSlice[system.int, system.int] = -1 .. -1
    byte2: HSlice[system.int, system.int] = -1 .. -1
    avoid: bool
    start: bool
    size: string

type
  CompressDef = object
    name: string
    shortName: string
    ops: seq[Op]

let konami = CompressDef(
    name: "Konami RLE",
    shortName: "KonamiRLE",
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
)

let kemko = CompressDef(
    name: "Kemko RLE",
    shortName: "KemkoRLE",
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
)


proc toInt(s:string): int =
    if s.startsWith("0x"):
        var num:int
        discard parseHex(s, num)
        return num
    elif s.startsWith("$"):
        var num:int
        discard parseHex(s[1..len(s)-1], num)
        return num
    else:
        return parseInt(s)

proc calc2(s: string): string =
    if s.find("*") != -1:
        let lValue = s.split("*", 1)[0].strip
        let rValue = s.split("*", 1)[1].strip
        let value = toInt(calc2(lValue)) * toInt(calc2(rValue))
        return calc2($value)
    if s.find("/") != -1:
        let lValue = s.split("/", 1)[0].strip
        let rValue = s.split("/", 1)[1].strip
        let value = int(toInt(calc2(lValue)) / toInt(calc2(rValue)))
        return calc2($value)
    return s

proc calc(s: string): string =
    if s.find("+") != -1:
        let lValue = s.split("+", 1)[0].strip
        let rValue = s.split("+", 1)[1].strip
        let value = toInt(calc(lValue)) + toInt(calc(rValue))
        return calc($value)
    if s.find("-") != -1:
        let lValue = s.split("-", 1)[0].strip
        let rValue = s.split("-", 1)[1].strip
        let value = toInt(calc(lValue)) - toInt(calc(rValue))
        return calc($value)
    return calc2(s)

type
  FilenameExtras = object
    name: string
    offset: int = 0
    length: int = 0

proc parseFilename(filename:string): FilenameExtras =
    
    var s = filename & ":0:0"
    
    result = FilenameExtras(
        name: s.split(":")[0],
        offset: toInt(s.split(":")[1]),
        length: toInt(s.split(":")[2])
    )

# Read the file into a byte array (seq[byte])
proc readFileData(filePath: string): seq[byte] =
    let file = open(filePath, fmRead)
    defer: file.close()
    let data = file.readAll()
    result = cast[seq[byte]](data)

proc write(file: FilenameExtras, data: seq[byte]) =
    if file.name == "":
        return
    elif file.offset == 0 and file.length == 0:
        writeFile(file.name, data)
        echo "File created: ", file.name
    else:
        # this currently wont make a new file, and it won't
        # work if you try to write past the length of the
        # original file
        
        var data2 = readFileData(file.name)
        for i in 0..data.len-1:
            if file.length != 0 and i > file.length:
                break
            data2[file.offset + i] = data[i]
        writeFile(file.name, data2)
        echo "File modified: ", file.name


proc write(filename: string, data: seq[byte]) =
    if filename == "":
        return
    else:
        writeFile(filename, data)
        echo "File created: ", filename

# Helper function to determine how many times the first byte in the sequence repeats
proc getRep(data: seq[byte], startIdx: int): int =
    var rep = 1
    while (startIdx + rep) < data.len and data[startIdx + rep] == data[startIdx] and rep < 0x7f:
        rep += 1
    return rep

proc compressKemkoRLE(nametable: seq[byte], ppuAddress: int): seq[byte] =
    var compressedData = newSeq[byte]()
    
    # Add initial PPU address
#    compressedData.add(byte(ppuAddress mod 0x100))  # PPU address low byte
#    compressedData.add(byte(ppuAddress / 0x100))  # PPU address high byte

    var i = 0
    let length = nametable.len

    while i < length:
        let currentByte = nametable[i]
        var rep = getRep(nametable, i)  # Get how many times the current byte repeats
        
        if rep > 0xfe:
            compressedData.add(0xff)
            compressedData.add(currentByte)  # Repeat value
            i += 0xfe
        elif rep >= 3:
            compressedData.add(0xff)
            compressedData.add(currentByte)  # Value to repeat
            compressedData.add(byte(rep))  # Repeat count
            i += rep
        elif currentByte == byte(0xff):
            # handle literal 0xff
            compressedData.add(0xff)
            compressedData.add(0xff)
            compressedData.add(byte(rep))  # Repeat count
            i += rep
        else:
            # Otherwise, perform the copy operation
            var copyData = newSeq[byte]()
            while i < length and getRep(nametable, i) < 4:
                if nametable[i] == byte(0xff):
                    # handle a literal 0xff elsewhere
                    break
                copyData.add(nametable[i])
                i += 1
                
            compressedData.add(copyData)  # Add the copied data to the compressed output

    # End of data marker
    compressedData.add(0xff)
    compressedData.add(0xff)
    compressedData.add(0x00)
    
    return compressedData

proc compressKonamiRLE(nametable: seq[byte], ppuAddress: int): seq[byte] =
    var compressedData = newSeq[byte]()
    
    # Add initial PPU address
    compressedData.add(byte(ppuAddress mod 0x100))  # PPU address low byte
    compressedData.add(byte(ppuAddress / 0x100))  # PPU address high byte

    var i = 0
    let length = nametable.len

    while i < length:
        let currentByte = nametable[i]
        var rep = getRep(nametable, i)  # Get how many times the current byte repeats
        
        if rep > 0x7e:
            # If repetition is greater than 0x7e, we cap it at 0x7e
            compressedData.add(0x7e)  # Operation for 0x7e repetition
            compressedData.add(currentByte)  # Repeat value
            i += 0x7e
        elif rep >= 3:
            # For repetitions greater than or equal to 3, use repeat (01-7E)
            compressedData.add(byte(rep))  # Repeat count (1 to 0x7e)
            compressedData.add(currentByte)  # Value to repeat
            i += rep
        else:
            # Otherwise, perform the copy operation
            var copyData = newSeq[byte]()
            while i < length and getRep(nametable, i) < 4 and copyData.len < 0x7e:
                copyData.add(nametable[i])
                inc(i)
                
            compressedData.add(byte(0x80 + copyData.len))  # Operation byte (0x80 + n)
            compressedData.add(copyData)  # Add the copied data to the compressed output

    compressedData.add(0xff)  # End of data marker
    return compressedData

proc compressKonamiRLE(nametable: seq[byte], ppuSection: string): seq[byte] =
    if ppuSection == "nt0":
        return compressKonamiRLE(nametable, 0x2000)
    elif ppuSection == "nt1":
        return compressKonamiRLE(nametable, 0x2400)
    elif ppuSection == "nt2":
        return compressKonamiRLE(nametable, 0x2800)
    elif ppuSection == "nt3":
        return compressKonamiRLE(nametable, 0x2c00)
    elif ppuSection == "att0":
        return compressKonamiRLE(nametable, 0x23c0)
    elif ppuSection == "att1":
        return compressKonamiRLE(nametable, 0x27c0)
    elif ppuSection == "att2":
        return compressKonamiRLE(nametable, 0x2bc0)
    elif ppuSection == "att3":
        return compressKonamiRLE(nametable, 0x2fc0)
    elif ppuSection == "chr0":
        return compressKonamiRLE(nametable, 0x0000)
    elif ppuSection == "chr1":
        return compressKonamiRLE(nametable, 0x1000)
    elif ppuSection == "bgPal":
        return compressKonamiRLE(nametable, 0x3f00)
    elif ppuSection == "spritePal":
        return compressKonamiRLE(nametable, 0x3f10)

proc decompress(compression: CompressDef, data: seq[byte], offset: int): seq[byte] =
    var ppu = newSeq[byte](0x4000)  # PPU memory space (16KB)
    var address = 0x2000
    
    var i = offset
    var start = true
    while i < data.len:
        let b0 = data[i+0].int
        let b1 = data[i+1].int
        let b2 = data[i+2].int
        echo $b0, " ", $b1, " ", $b2
        
        var validOp = false
        for op in compression.ops:
            if (op.start == false or start == true) and ((b0 in op.byte0 or -1 in op.byte0) and (b1 in op.byte1 or -1 in op.byte1) and (b2 in op.byte2 or -1 in op.byte2)):
                start = false
                validOp = true
                if (op.start == true and i == offset):
#                    echo "start"
                var fmt = op.format
                fmt = fmt.replace("[0]", $b0)
                fmt = fmt.replace("[1]", $b1)
                fmt = fmt.replace("[2]", $b2)
                
                var fmtSize = op.size
                fmtSize = fmtSize.replace("[0]", $b0)
                fmtSize = fmtSize.replace("[1]", $b1)
                fmtSize = fmtSize.replace("[2]", $b2)
                
                let size = toInt(calc(fmtSize))
                
                if op.typ == "repeat":
                    let v1 = calc(fmt.split()[0])
                    let v2 = calc(fmt.split()[1])
#                    echo op.typ & " " & v1 & " " & v2
                    for _ in 0..<toInt(v2):
                        ppu[address] = toInt(v1).uint8
                        address = address + 1
                    i = i + size
                    break
                if op.typ == "address":
                    let a = calc(fmt)
#                    echo op.typ & " " & a
                    address = toInt(a)
                    i = i + size
                    break
                if op.typ == "copy":
                    let count = toInt(calc(fmt.split()[0]))
                    let copyStartOffset = toInt(calc(fmt.split()[1]))
#                    echo op.typ & " " & $count
                    for j in 0..<count:
                        ppu[address] = data[i + j + copyStartOffset]
                        address = address + 1
                    i = i + size
                    break
                if op.typ == "end":
#                    echo op.typ
                    i = i + size
                    return ppu
        if not validOp:
            echo "invalid op"
            return ppu
    result = ppu

# Helper functions to extract specific parts of the PPU memory
proc getNametable(ppu: seq[byte], index: int): seq[byte] =
    let offsets = [0x2000, 0x2400, 0x2800, 0x2C00]
    return ppu[offsets[index]..(offsets[index] + 0x3ff)]

proc nt0(ppu: seq[byte]): seq[byte] =
    return getNametable(ppu, 0)
proc nt1(ppu: seq[byte]): seq[byte] =
    return getNametable(ppu, 1)
proc nt2(ppu: seq[byte]): seq[byte] =
    return getNametable(ppu, 2)
proc nt3(ppu: seq[byte]): seq[byte] =
    return getNametable(ppu, 3)

proc getPalette(ppu: seq[byte], index: int): seq[byte] =
    if index == 0:
        return ppu[0x3f00..0x3f0f]  # Background palette
    else:
        return ppu[0x3f10..0x3f1f]  # Sprite palette

proc palBk(ppu: seq[byte]): seq[byte] =
    return getPalette(ppu, 0)
proc palSprite(ppu: seq[byte]): seq[byte] =
    return getPalette(ppu, 1)

proc usage() = 
    echo app.info
    echo ""
    echo app.description
    echo ""
    echo "Usage: ", app.name, " [opts]"
    echo ""
    echo "Options:"
    echo "  -c, --compress:filename         filename to compress"
    echo "  -d, --decompress:filename       filename to decompress"
    echo "  -m, --method:method             compression method"
    echo "  -a, --ppuaddr:address           ppu address (c)"
    echo "  -o, --outputfile:filename       output filename (c)"
    echo "  -0, --nt0:filename              output filename for nametable 0 (d)"
    echo "  -1, --nt1:filename              output filename for nametable 1 (d)"
    echo "  -2, --nt2:filename              output filename for nametable 2 (d)"
    echo "  -3, --nt3:filename              output filename for nametable 3 (d)"
    echo "  -b, --bkpal:filename            output filename for background palette (d)"
    echo "  -s, --spritepal:filename        output filename for sprite palette (d)"
    echo "  -h, --help                      Show this help"
    echo "  -v, --version                   show detailed version information"
    echo ""
    echo "Items labeled with (d) apply only to decompressing."
    echo "Items labeled with (c) apply only to compressing."
    echo ""
    echo "Valid compression methods are: [konami, kemko]"
    echo ""
    echo "When specifying filenames, you may also use a colon at the end and add"
    echo "a file offset."
    echo ""
    echo "Examples:"
    echo "    ", app.name, """ -d:"Castlevania III - Dracula's Curse (USA).nes:0xb580" -0:"nt0.nam""""
    echo "    ", app.name, """ -c:"uncompressed.nam" -a:0x2000 -o:"compressed.nam""""
    echo "    ", app.name, """ -c:"custom.nam" -o:"cv3Edit.nes:0xb580""""
    echo ""
    quit()

# Run the main procedure only when it's the main module
when isMainModule:
    
    
#    let b0 = 0x02
#    let b1 = 0x20
#    let b2 = 0x01
#    let start = true
    
#    for op in konami.ops:
#        if start == true or ((b0 in op.byte0 or -1 in op.byte0) and (b1 in op.byte1 or -1 in op.byte1) and (b2 in op.byte2 or -1 in op.byte2)):
#            var fmt = op.format
#            fmt = fmt.replace("[0]", $b0)
#            fmt = fmt.replace("[1]", $b1)
#            fmt = fmt.replace("[2]", $b2)
#            if op.typ == "repeat":
#                let v1 = calc(fmt.split()[0])
#                let v2 = calc(fmt.split()[1])
#                echo op.typ & " " & v1 & " " & v2
#                break
#            if op.typ == "address":
#                let a = calc(fmt)
#                echo op.typ & " " & a
#                break
#            if op.typ == "copy":
#                let n = calc(fmt)
#                echo op.typ & " " & n
#                break
#            if op.typ == "end":
#                echo op.typ
#                break
            
            
#    quit()
    
    proc hasKey(t: Table[string, string]; key1, key2: string): bool =
        if t.hasKey(key1):
            return true
        elif t.hasKey(key2):
            return true
        else:
            return false
    
    proc getVal(t: Table[string, string]; key1, key2: string): string =
        if t.hasKey(key1):
            return t[key1]
        elif t.hasKey(key2):
            return t[key2]
        else:
            return ""
    
    var p = initOptParser()
    var options = initTable[string, string]()
    var argIndex = 1
    for kind, key, val in p.getopt():
        case kind
        of cmdArgument:
            options["arg" & $argIndex] = key
            argIndex += 1
        of cmdLongOption, cmdShortOption:
            options[key] = val
        of cmdEnd: discard
    
    
    if options.hasKey("releasetag"):
        echo app.releaseTag
        quit()
    if options.hasKey("h", "help"):
        usage()
    if options.haskey("arg1"):
        # does not currently take unnamed arguments
        usage()
    
    if options.hasKey("v", "version"):
        echo app.info
        echo "Build: ", app.date, " ", app.time, " Nim ", app.nimVersion
        quit()
    
    if options.haskey("decompress", "d") or options.haskey("compress", "c"):
        echo app.name, " ", app.version
    else:
        # did not specify compress or decompress
        usage()
    
    var mode = "konami"
    if options.hasKey("m", "method"):
        mode = options.getVal("m", "method")
    
    if options.haskey("decompress", "d"):
        let inputFile = parseFilename(options.getVal("decompress", "d"))
        
        echo "decompressing from file: ", inputFile.name, "...\n"
        let data = readFileData(inputFile.name)
        
        var ppu = newSeq[byte](0x4000)
        
        if mode == "konami":
            ppu = decompress(konami, data, inputFile.offset)
        elif mode == "kemko":
            ppu = decompress(kemko, data, inputFile.offset)
        else:
            echo "unknown decompress method"

        # file will not be written if the value is ""
        write(parseFilename(options.getVal("nt0", "0")), ppu.nt0)
        write(parseFilename(options.getVal("nt1", "1")), ppu.nt1)
        write(parseFilename(options.getVal("nt2", "2")), ppu.nt2)
        write(parseFilename(options.getVal("nt3", "3")), ppu.nt3)
        write(parseFilename(options.getVal("bkpal", "b")), ppu.palBk)
        write(parseFilename(options.getVal("spritepal", "s")), ppu.palSprite)
    elif options.haskey("compress", "c"):
        let inputFile = parseFilename(options.getVal("compress", "c"))
        
        echo "compressing from file: ", inputFile.name, "..."
        var data = readFileData(inputFile.name)
        
        # remove everything before the inputOffset
        data = data[inputFile.offset..len(data)-inputFile.offset-1]
        
        var ppuAddress = 0x2000
        if options.haskey("ppuaddress", "a"):
            ppuAddress = options.getVal("ppuaddress", "a").toInt
        
        var compressed = newSeq[byte]()
#        var compressed = seq[byte]
        if mode == "kemko":
            compressed = compressKemkoRLE(data, ppuAddress)
        elif mode == "konami":
            compressed = compressKonamiRLE(data, ppuAddress)
        else:
            echo "unknown compress method"
        
        echo fmt"  Compressed size: {compressed.len} bytes"
        echo fmt"  Target PPU Address: 0x{ppuAddress:04x}"
        
#        let compressed = compressKonamiRLE(data, 0x2000)
#        let compressed = compressKonamiRLE(data, "nt0")
        
        write(parseFilename(options.getVal("outputFile", "o")), compressed)
        
        
    echo "Done.\n"
