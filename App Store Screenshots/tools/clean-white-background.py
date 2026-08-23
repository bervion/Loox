"""Flatten an illustration's near-white background to pure #FFFFFF.

The generated hero art sits on 253–254 grey, which shows as a faint rectangle
against the deck's white frame (and WebP encoding mottles it further). Pure
Python so it needs no image library on this machine.
"""
import struct
import sys
import zlib

THRESHOLD = 244  # every channel at or above this is background


def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat, meta = 8, [], None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if ctype == b"IHDR":
            w, h, depth, color, comp, filt, inter = struct.unpack(">IIBBBBB", body)
            assert depth == 8 and comp == 0 and filt == 0 and inter == 0, "unsupported PNG"
            assert color in (2, 6), "expected RGB or RGBA"
            meta = (w, h, 3 if color == 2 else 4, color)
        elif ctype == b"IDAT":
            idat.append(body)
        elif ctype == b"IEND":
            break
        pos += 12 + length
    return meta, zlib.decompress(b"".join(idat))


def unfilter(raw, w, h, bpp):
    stride = w * bpp
    out = bytearray(stride * h)
    prev = bytearray(stride)
    pos = 0
    for y in range(h):
        ftype = raw[pos]; pos += 1
        line = bytearray(raw[pos:pos + stride]); pos += stride
        if ftype == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif ftype == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif ftype != 0:
            raise ValueError(f"bad filter {ftype}")
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return out


def chunk(ctype, body):
    return (struct.pack(">I", len(body)) + ctype + body
            + struct.pack(">I", zlib.crc32(ctype + body) & 0xFFFFFFFF))


def main(src, dst):
    (w, h, bpp, color), raw = read_png(src)
    px = unfilter(raw, w, h, bpp)
    stride = w * bpp
    touched = 0
    for i in range(0, len(px), bpp):
        if px[i] >= THRESHOLD and px[i + 1] >= THRESHOLD and px[i + 2] >= THRESHOLD:
            if px[i] != 255 or px[i + 1] != 255 or px[i + 2] != 255:
                touched += 1
            px[i] = px[i + 1] = px[i + 2] = 255
    body = bytearray()
    for y in range(h):
        body.append(0)
        body += px[y * stride:(y + 1) * stride]
    out = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, color, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(body), 9))
           + chunk(b"IEND", b""))
    open(dst, "wb").write(out)
    print(f"{w}x{h} bpp={bpp} whitened={touched:,} px -> {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
