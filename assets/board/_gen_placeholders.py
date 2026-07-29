"""Generate PLACEHOLDER PNG assets for MoeChess (board backgrounds + icon).

These are intentionally flat-color / simple-gradient placeholders to be
replaced by real ComfyUI-generated art later. They are NOT final art.

Outputs:
  assets/board/board_player.png    1080x1280  player-side perspective bg
  assets/board/board_opponent.png  1080x1280  opponent-side perspective bg
  assets/ui/icon.png              256x256    app icon
"""
import os
import struct
import zlib

OUT_DIR_BOARD = os.path.join(os.path.dirname(__file__))
OUT_DIR_UI = os.path.abspath(os.path.join(OUT_DIR_BOARD, "..", "ui"))
os.makedirs(OUT_DIR_BOARD, exist_ok=True)
os.makedirs(OUT_DIR_UI, exist_ok=True)


def _write_png(path, width, height, rows_rgba):
    """rows_rgba: list of bytearray, each row has width*4 bytes (RGBA)."""
    raw = bytearray()
    for row in rows_rgba:
        raw.append(0)  # filter type 0
        raw.extend(row)
    compressed = zlib.compress(bytes(raw), 9)

    def chunk(tag, data):
        c = tag + data
        crc = struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
        return struct.pack(">I", len(data)) + c + crc

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)  # 8-bit, RGBA
    with open(path, "wb") as f:
        f.write(sig)
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", compressed))
        f.write(chunk(b"IEND", b""))
    print("wrote", path, "%dx%d" % (width, height))


def _lerp(a, b, t):
    return a + (b - a) * t


def _lerp_color(c1, c2, t):
    return (
        int(_lerp(c1[0], c2[0], t)),
        int(_lerp(c1[1], c2[1], t)),
        int(_lerp(c1[2], c2[2], t)),
        int(_lerp(c1[3], c2[3], t)),
    )


# Board background: a near-flat light wood gradient with subtle "perspective"
# trapezoid drawn using two darker borders to imply row lines. Far edge
# (top of player view) is narrower than near edge (bottom).
BOARD_W = 1080
BOARD_H = 1280


def _draw_board(player_side: bool):
    """player_side True  -> row0 (red, player) at bottom (near, wide);
                  row9 (black, opponent) at top (far, narrow).
       player_side False -> opposite (used for opponent view in 2-player flip).
    """
    # Base warm wood gradient
    near_color = (220, 180, 120, 255)
    far_color = (170, 130, 80, 255)
    rows = []
    for y in range(BOARD_H):
        t = y / float(BOARD_H - 1)
        # When player_side: bottom (y large) is near (warm bright), top is far (darker)
        if player_side:
            tt = t  # 0=top=far, 1=bottom=near
        else:
            tt = 1.0 - t
        base = _lerp_color(far_color, near_color, tt)
        row = bytearray()
        for _ in range(BOARD_W):
            row.extend(base)
        rows.append(row)

    # Draw a trapezoid outline to suggest the board area
    # 9 cols x 10 rows grid inside the perspective trapezoid
    # Near edge wide, far edge narrow
    margin_y = 60
    near_half_width = int(BOARD_W * 0.46)
    far_half_width = int(BOARD_W * 0.32)
    cx = BOARD_W // 2
    near_y = BOARD_H - margin_y
    far_y = margin_y
    line_color = (60, 40, 20, 255)

    def set_pixel(x, y, color):
        if 0 <= x < BOARD_W and 0 <= y < BOARD_H:
            i = x * 4
            rows[y][i:i + 4] = bytes(color)

    def draw_line(x0, y0, x1, y1, color):
        # Bresenham
        dx = abs(x1 - x0)
        dy = abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx - dy
        while True:
            for ox in (-2, -1, 0, 1, 2):
                for oy in (-2, -1, 0, 1, 2):
                    set_pixel(x0 + ox, y0 + oy, color)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 > -dy:
                err -= dy
                x0 += sx
            if e2 < dx:
                err += dx
                y0 += sy

    # Trapezoid border (4 edges)
    draw_line(int(cx - near_half_width), near_y, int(cx - far_half_width), far_y, line_color)
    draw_line(int(cx + near_half_width), near_y, int(cx + far_half_width), far_y, line_color)
    draw_line(int(cx - near_half_width), near_y, int(cx + near_half_width), near_y, line_color)
    draw_line(int(cx - far_half_width), far_y, int(cx + far_half_width), far_y, line_color)

    # Horizontal row lines (10 rows -> 9 gaps)
    for r in range(11):
        t = r / 10.0
        # row 0 near, row 10 far
        y = int(near_y + (far_y - near_y) * t)
        half = int(near_half_width + (far_half_width - near_half_width) * t)
        draw_line(cx - half, y, cx + half, y, line_color)

    # Vertical column lines (9 cols -> 8 gaps)
    for c in range(9):
        t = c / 8.0
        # x offset at near and far
        x_near_left = cx - near_half_width
        x_far_left = cx - far_half_width
        x_near_right = cx + near_half_width
        x_far_right = cx + far_half_width
        xn = int(x_near_left + (x_near_right - x_near_left) * t)
        xf = int(x_far_left + (x_far_right - x_far_left) * t)
        draw_line(xn, near_y, xf, far_y, line_color)

    # River band marker (middle 4-5 rows)
    river_y1 = int(near_y + (far_y - near_y) * 0.45)
    river_y2 = int(near_y + (far_y - near_y) * 0.55)
    river_color = (120, 80, 40, 80)
    for y in range(river_y1, river_y2 + 1):
        for x in range(BOARD_W):
            i = x * 4
            cur = rows[y][i:i + 4]
            blended = (
                int(cur[0] * 0.5 + river_color[0] * 0.5),
                int(cur[1] * 0.5 + river_color[1] * 0.5),
                int(cur[2] * 0.5 + river_color[2] * 0.5),
                255,
            )
            rows[y][i:i + 4] = bytes(blended)

    return rows


_write_png(
    os.path.join(OUT_DIR_BOARD, "board_player.png"),
    BOARD_W, BOARD_H, _draw_board(player_side=True)
)
_write_png(
    os.path.join(OUT_DIR_BOARD, "board_opponent.png"),
    BOARD_W, BOARD_H, _draw_board(player_side=False)
)


# App icon: 256x256, a simple rounded square with a king crown glyph made of pixels
ICON = 256
icon_rows = []
for y in range(ICON):
    row = bytearray()
    for x in range(ICON):
        # rounded square background
        bg = (255, 220, 180, 255)
        # corner radius
        r = 32
        in_corner = False
        if x < r and y < r:
            if (x - r) ** 2 + (y - r) ** 2 > r * r:
                in_corner = True
        if x >= ICON - r and y < r:
            if (x - (ICON - r - 1)) ** 2 + (y - r) ** 2 > r * r:
                in_corner = True
        if x < r and y >= ICON - r:
            if (x - r) ** 2 + (y - (ICON - r - 1)) ** 2 > r * r:
                in_corner = True
        if x >= ICON - r and y >= ICON - r:
            if (x - (ICON - r - 1)) ** 2 + (y - (ICON - r - 1)) ** 2 > r * r:
                in_corner = True
        if in_corner:
            row.extend(b"\x00\x00\x00\x00")
            continue
        # crown region (center band)
        cy = ICON // 2
        if cy - 30 < y < cy + 10:
            # crown base
            if 60 < x < 196:
                row.extend(b"\xc8\x6a\x1e\xff")  # orange
                continue
        if cy - 60 < y < cy - 30:
            # crown points
            if 80 < x < 90 or 120 < x < 130 or 160 < x < 170:
                row.extend(b"\xc8\x6a\x1e\xff")
                continue
        row.extend(bytes(bg))
    icon_rows.append(row)

_write_png(os.path.join(OUT_DIR_UI, "icon.png"), ICON, ICON, icon_rows)
print("done")
