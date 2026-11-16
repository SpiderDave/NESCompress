# Load NEXXT / NES Screen Tool (.nss) files.
#
# Data fields use hexadecimal bytes. A bracketed hexadecimal count after a byte
# expands that byte to the specified total run length, for example:
#
#     NameTable=00[80]01[64]0203
#
# This produces 0x80 bytes of 00, 0x64 bytes of 01, then 02 03.

import
    strutils,
    std/tables

proc hexValue(c: char): int =
    case c
    of '0'..'9': ord(c) - ord('0')
    of 'a'..'f': ord(c) - ord('a') + 10
    of 'A'..'F': ord(c) - ord('A') + 10
    else: -1

proc parseHexByte(s: string, pos: int): byte =
    if pos + 1 >= s.len:
        raise newException(ValueError, "Incomplete hexadecimal byte in NSS data")

    let high = hexValue(s[pos])
    let low = hexValue(s[pos + 1])

    if high < 0 or low < 0:
        raise newException(ValueError, "Invalid hexadecimal byte in NSS data")

    result = byte(high * 16 + low)

proc parseHexCount(s: string): int =
    if s.len == 0:
        raise newException(ValueError, "Empty run length in NSS data")

    for c in s:
        let value = hexValue(c)
        if value < 0:
            raise newException(ValueError, "Invalid hexadecimal run length in NSS data")
        result = result * 16 + value

proc decodeNssData*(value: string): seq[byte] =
    ## Decode a single NSS hexadecimal data field.
    ## A bracket count specifies the total number of occurrences of the
    ## immediately preceding byte, including the byte already emitted.
    var i = 0

    while i < value.len:
        if value[i].isSpaceAscii or value[i] == ',' or value[i] == '\\':
            inc i
            continue

        if value[i] == '[':
            let closePos = value.find(']', i + 1)
            if closePos < 0:
                raise newException(ValueError, "Unclosed run length in NSS data")
            if result.len == 0:
                raise newException(ValueError, "Run length has no preceding byte in NSS data")

            let count = parseHexCount(value[i + 1 ..< closePos])
            if count == 0:
                raise newException(ValueError, "NSS run length cannot be zero")

            let previous = result[^1]
            if count > result.len and count - 1 > high(int) - result.len:
                raise newException(ValueError, "NSS run length is too large")

            for _ in 1..<count:
                result.add(previous)

            i = closePos + 1
        else:
            result.add(parseHexByte(value, i))
            i += 2

proc parseNss*(contents: string, keys: seq[string] = @["nametable", "attrtable"]): seq[byte] =
    ## Parse NSS text and return data from specified keys
    
    var data = initTable[string, string]()
    
    for line in contents.splitLines:
        if "=" in line:
            let parts = line.strip.split("=", 1)
            data[parts[0].toLowerAscii] = parts[1]

    for key in keys:
        if data.hasKey(key.strip.toLowerAscii):
            echo key
            result.add(decodeNssData(data[key.strip.toLowerAscii]))

proc parseNss2*(contents: string, keys: seq[string] = @["nametable", "attrtable"]): Table[string, string] =
    ## Parse NSS text and return data from specified keys
    
    var data = initTable[string, string]()
    
    for line in contents.splitLines:
        if "=" in line:
            let parts = line.strip.split("=", 1)
            let key = parts[0].strip.toLowerAscii
            if key in keys:
                result[key] = parts[1]


proc loadNss*(filename: string, keys: seq[string] = @["nametable", "attrtable"]): seq[byte] =
    ## Load an NSS file, returning NameTable and optionally AttrTable bytes.
    let contents = readFile(filename)
    result = parseNss(contents, keys)
