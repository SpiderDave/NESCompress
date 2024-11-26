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


# Decompress and extract data from the NES file using Konami RLE format
proc decompressKonamiRLE(data: seq[byte], offset: int): seq[byte] =
    var ppu = newSeq[byte](0x4000)  # PPU memory space (16KB)
    var address = int64(data[offset]) or (int64(data[offset + 1]) shl 8)  # Initial PPU address (little endian)
    
    var i = offset + 2  # Start reading data after the address
    while i < data.len:
        let op = data[i]
        inc(i)

        if op == 0:
            # Read another byte, and write it to the output 256 times
            let repeatVal = data[i]
            inc(i)
            for _ in 0..<256:
                if address < 0x4000:  # Ensure address is within bounds
                    ppu[address] = repeatVal
                    inc(address)
                else:
                    echo "Warning: address out of bounds, skipping."
        elif op >= 1 and op <= 0x7e:
            # Read another byte, and write it to the output n times
            let repeatVal = data[i]
            inc(i)
            for _ in 0..<int(op):  # Cast op to int to resolve ambiguity
                if address < 0x4000:
                    ppu[address] = repeatVal
                    inc(address)
                else:
                    echo "Warning: address out of bounds, skipping."
        elif op == 0x7f:
            # Read another two bytes for a new PPU address
            address = (int64(data[i]) or (int64(data[i+1]) shl 8))  # Corrected with 'shl'
            i += 2
        elif op == 0x80:
            # Read another byte, and write it to the output 255 times
            let repeatVal = data[i]
            inc(i)
            for _ in 0..<255:
                if address < 0x4000:
                    ppu[address] = repeatVal
                    inc(address)
                else:
                    echo "Warning: address out of bounds, skipping."
        elif op >= 0x81 and op <= 0xfe:
            # Copy n - 128 bytes from input to output
            let count = int(op) - 128
            for j in 0..<count:
                if address < 0x4000:
                    ppu[address] = data[i + j]
                    inc(address)
                else:
                    echo "Warning: address out of bounds, skipping."
            i += count
        elif op == 0xff:
            break  # End of data

    result = ppu

proc decompressKemkoRLE(data: seq[byte], offset: int): seq[byte] =
    var ppu = newSeq[byte](0x4000)  # PPU memory space (16KB)
    var address = 0x2000
    
    var i = offset
    
    while i < data.len:
        let op = data[i]
        # don't increment i yet because this might be data (not op)

        if op == 0xff:
            i += 1
            # Read two bytes for (value, len) and write value to output len times
            let repeatVal = data[i]
            i += 1
            let l = data[i]
            i += 1
            
            # Writing 0 times signals end of data
            if l == 0:
                break
            
            for _ in 0..l.int-1:
                if address < 0x4000:  # Ensure address is within bounds
                    ppu[address] = repeatVal
                    address += 1
                else:
                    echo fmt"Warning: address 0x{address:04x} out of bounds, skipping."
        else: # 0x00 - 0xfe
            # Copy bytes from input to output
            
            # copy until we find another 0xff
            
            while true:
                if data[i] == 0xff:
                    break
                
                if address < 0x4000:
                    ppu[address] = data[i]
                    address += 1
                else:
                    echo fmt"Warning: address 0x{address:04x} out of bounds, skipping."
                
                i += 1

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
    if options.hasKey("m", "mode"):
        mode = options.getVal("m", "mode")
    
    if options.haskey("decompress", "d"):
        let inputFile = parseFilename(options.getVal("decompress", "d"))
        
        echo "decompressing from file: ", inputFile.name, "...\n"
        let data = readFileData(inputFile.name)
        
        var ppu = newSeq[byte](0x4000)
        
        if mode == "kemko":
            ppu = decompressKemkoRLE(data, inputFile.offset)
        elif mode == "konami":
            ppu = decompressKonamiRLE(data, inputFile.offset)
        else:
            echo "unknown decompress mode"

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
            echo "unknown compress mode"
        
        echo fmt"  Compressed size: {compressed.len} bytes"
        echo fmt"  Target PPU Address: 0x{ppuAddress:04x}"
        
#        let compressed = compressKonamiRLE(data, 0x2000)
#        let compressed = compressKonamiRLE(data, "nt0")
        
        write(parseFilename(options.getVal("outputFile", "o")), compressed)
        
        
    echo "Done.\n"
