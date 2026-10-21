"""Dump records of a Skyrim SE plugin. Usage: python -I esp_dump.py <plugin.esp> [TYPE ...]"""
import struct
import sys
import zlib


def subrecords(data):
    i = 0
    while i < len(data):
        sig, size = struct.unpack_from("<4sH", data, i)
        i += 6
        yield sig.decode(), data[i:i + size]
        i += size


def records(buf, start, end):
    i = start
    while i < end:
        sig, size = struct.unpack_from("<4sI", buf, i)
        if sig == b"GRUP":
            yield from records(buf, i + 24, i + size)
            i += size
            continue
        flags, formid = struct.unpack_from("<II", buf, i + 8)
        data = buf[i + 24:i + 24 + size]
        if flags & 0x40000:
            data = zlib.decompress(data[4:])
        yield sig.decode(), formid, data
        i += 24 + size


def show(value):
    if len(value) == 4:
        return f"{struct.unpack('<I', value)[0]:08X}"
    text = value.rstrip(b"\0")
    if text and all(32 <= c < 127 for c in text):
        return repr(text.decode())
    return value.hex(" ")


if __name__ == "__main__":
    buf = open(sys.argv[1], "rb").read()
    wanted = set(sys.argv[2:])
    hedr_size = struct.unpack_from("<I", buf, 4)[0]
    for sig, formid, data in records(buf, 24 + hedr_size, len(buf)):
        if wanted and sig not in wanted:
            continue
        print(f"== {sig} {formid:08X}")
        for sub, value in subrecords(data):
            print(f"   {sub} {show(value)}")
