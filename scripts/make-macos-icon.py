#!/usr/bin/env python3
import os
import struct
import subprocess
import zlib


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ICONSET = os.path.join(ROOT, "packaging", "macos", "AppIcon.iconset")
ICNS = os.path.join(ROOT, "packaging", "macos", "AppIcon.icns")


def png_chunk(kind, data):
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    )


def write_png(path, width, height, pixels):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        start = y * width * 4
        raw.extend(pixels[start : start + width * 4])

    data = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + png_chunk(b"IEND", b"")
    )
    with open(path, "wb") as fh:
        fh.write(data)


def blend(dst, src):
    sr, sg, sb, sa = src
    if sa >= 255:
        return [sr, sg, sb, 255]
    dr, dg, db, da = dst
    a = sa / 255.0
    return [
        int(sr * a + dr * (1 - a)),
        int(sg * a + dg * (1 - a)),
        int(sb * a + db * (1 - a)),
        255,
    ]


def rounded_rect_alpha(x, y, left, top, right, bottom, radius):
    if x < left or x >= right or y < top or y >= bottom:
        return 0
    cx = min(max(x, left + radius), right - radius - 1)
    cy = min(max(y, top + radius), bottom - radius - 1)
    dx = x - cx
    dy = y - cy
    dist = (dx * dx + dy * dy) ** 0.5
    if dist <= radius - 1:
        return 255
    if dist >= radius + 1:
        return 0
    return int(max(0, min(255, (radius + 1 - dist) * 127.5)))


def draw_rect(pixels, size, left, top, right, bottom, radius, color):
    for y in range(top, bottom):
        for x in range(left, right):
            alpha = rounded_rect_alpha(x, y, left, top, right, bottom, radius)
            if alpha == 0:
                continue
            idx = (y * size + x) * 4
            src = [color[0], color[1], color[2], int(color[3] * alpha / 255)]
            pixels[idx : idx + 4] = blend(pixels[idx : idx + 4], src)


def draw_circle(pixels, size, cx, cy, radius, color):
    r2 = radius * radius
    for y in range(max(0, cy - radius - 2), min(size, cy + radius + 3)):
        for x in range(max(0, cx - radius - 2), min(size, cx + radius + 3)):
            dist2 = (x - cx) * (x - cx) + (y - cy) * (y - cy)
            if dist2 > (radius + 1) * (radius + 1):
                continue
            alpha = 255 if dist2 <= r2 else int(max(0, 255 * (1 - ((dist2**0.5 - radius)))))
            idx = (y * size + x) * 4
            src = [color[0], color[1], color[2], int(color[3] * alpha / 255)]
            pixels[idx : idx + 4] = blend(pixels[idx : idx + 4], src)


def draw_icon(path, size):
    pixels = bytearray([0, 0, 0, 0] * size * size)

    # Background: calm blue/green gradient in a rounded macOS-style square.
    for y in range(size):
        for x in range(size):
            alpha = rounded_rect_alpha(x, y, 0, 0, size, size, int(size * 0.22))
            if alpha == 0:
                continue
            t = (x + y) / (2 * size)
            r = int(25 + 25 * t)
            g = int(95 + 95 * t)
            b = int(165 + 45 * (1 - t))
            idx = (y * size + x) * 4
            pixels[idx : idx + 4] = [r, g, b, alpha]

    s = size
    draw_rect(pixels, s, int(.23*s), int(.16*s), int(.77*s), int(.84*s), int(.055*s), (246, 250, 255, 255))
    draw_rect(pixels, s, int(.29*s), int(.25*s), int(.71*s), int(.295*s), int(.018*s), (65, 96, 132, 230))
    draw_rect(pixels, s, int(.29*s), int(.37*s), int(.71*s), int(.405*s), int(.018*s), (95, 126, 160, 210))
    draw_rect(pixels, s, int(.29*s), int(.48*s), int(.61*s), int(.515*s), int(.018*s), (95, 126, 160, 210))

    # Small friendly "guy" mark on the note.
    draw_circle(pixels, s, int(.50*s), int(.65*s), int(.095*s), (28, 58, 89, 255))
    draw_circle(pixels, s, int(.465*s), int(.63*s), max(1, int(.012*s)), (246, 250, 255, 255))
    draw_circle(pixels, s, int(.535*s), int(.63*s), max(1, int(.012*s)), (246, 250, 255, 255))
    draw_rect(pixels, s, int(.445*s), int(.705*s), int(.555*s), int(.725*s), int(.014*s), (246, 250, 255, 255))

    write_png(path, size, size, pixels)


def main():
    os.makedirs(ICONSET, exist_ok=True)
    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    for size, name in sizes:
        draw_icon(os.path.join(ICONSET, name), size)
    subprocess.run(["iconutil", "-c", "icns", ICONSET, "-o", ICNS], check=True)
    print(ICNS)


if __name__ == "__main__":
    main()
