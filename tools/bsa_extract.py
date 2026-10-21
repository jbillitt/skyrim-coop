"""Extract a Skyrim SE BSA (v105). Usage: python -I bsa_extract.py <archive.bsa> <out_dir>"""
import os
import struct
import sys


def lz4_block(src, out):
    i = 0
    while i < len(src):
        token = src[i]; i += 1
        n = token >> 4
        if n == 15:
            while True:
                b = src[i]; i += 1; n += b
                if b != 255:
                    break
        out += src[i:i + n]; i += n
        if i >= len(src):
            break
        back = src[i] | src[i + 1] << 8; i += 2
        m = (token & 15) + 4
        if m == 19:
            while True:
                b = src[i]; i += 1; m += b
                if b != 255:
                    break
        start = len(out) - back
        for k in range(m):  # byte by byte: matches may overlap themselves
            out.append(out[start + k])


def lz4_frame(data):
    assert struct.unpack_from("<I", data)[0] == 0x184D2204
    flg = data[4]
    i = 7 + (8 if flg & 0x08 else 0) + (4 if flg & 0x01 else 0)
    out = bytearray()
    while True:
        size = struct.unpack_from("<I", data, i)[0]; i += 4
        if size == 0:
            return bytes(out)
        raw = size & 0x80000000
        size &= 0x7FFFFFFF
        block = data[i:i + size]; i += size
        if raw:
            out += block
        else:
            lz4_block(block, out)
        if flg & 0x10:
            i += 4


def read_bzstring(f):
    n = f.read(1)[0]
    return f.read(n).rstrip(b"\0").decode("cp1252")


def extract(path, out):
    with open(path, "rb") as f:
        magic, version, offset, flags, nfolders, nfiles, _, _, _, _ = struct.unpack("<4sIIIIIIIHH", f.read(36))
        assert magic == b"BSA\0" and version == 105, (magic, version)
        compressed_default = bool(flags & 0x4)
        embed_names = bool(flags & 0x100)
        folders = [struct.unpack("<QIIQ", f.read(24))[1] for _ in range(nfolders)]
        entries = []
        for count in folders:
            folder = read_bzstring(f)
            for _ in range(count):
                _, size, off = struct.unpack("<QII", f.read(16))
                entries.append([folder, size, off])
        names = f.read().split(b"\0")
        for entry, name in zip(entries, names):
            entry.append(name.decode("cp1252"))

        for folder, size, off, name in entries:
            toggled = bool(size & 0x40000000)
            size &= 0x3FFFFFFF
            f.seek(off)
            if embed_names:
                skip = f.read(1)[0]
                f.read(skip)
                size -= skip + 1
            data = f.read(size)
            if compressed_default != toggled:
                data = lz4_frame(data[4:])  # first 4 bytes: original size
            dest = os.path.join(out, folder, name)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as o:
                o.write(data)
            print(dest, len(data))


if __name__ == "__main__":
    extract(sys.argv[1], sys.argv[2])
