"""Draws the Egtma3 app icon (1024x1024) and its adaptive-icon foreground.

Three women side by side (a meeting / a sisterhood) under a gold Coptic
cross, inside a gold ring, on a deep navy background. Drawn at 4x and
scaled down for smooth edges.

    python tool/make_icon.py
"""
from PIL import Image, ImageDraw, ImageFilter

S = 4096          # working size (4x)
OUT = 1024

NAVY_TOP = (31, 58, 95)      # AppColors.primary
NAVY_BOT = (14, 30, 54)
GOLD = (214, 168, 74)
GOLD_LIGHT = (247, 226, 170)
CREAM = (250, 244, 230)
ROSE = (232, 196, 178)


def gradient(size, top, bottom):
    img = Image.new("RGB", (size, size), top)
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(size):
            px[x, y] = c
    return img


def coptic_cross(d, cx, cy, r, color):
    """Coptic cross: thick arms that widen at the ends, each end finished
    with three small rounds (trefoil), plus a centre medallion."""
    inner = r * 0.16   # half-width at the centre
    outer = r * 0.30   # half-width at the arm end
    end = r * 0.78     # where the trefoil starts
    for dx, dy in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
        # tapered arm (trapezoid)
        px, py = -dy, dx  # perpendicular
        pts = [
            (cx + px * inner, cy + py * inner),
            (cx - px * inner, cy - py * inner),
            (cx + dx * end - px * outer, cy + dy * end - py * outer),
            (cx + dx * end + px * outer, cy + dy * end + py * outer),
        ]
        d.polygon(pts, fill=color)
        # trefoil: one round at the tip, two at the corners
        k = r * 0.17
        for (ox, oy) in [(dx * (end + k * 0.9), dy * (end + k * 0.9)),
                         (dx * end + px * outer * 0.85, dy * end + py * outer * 0.85),
                         (dx * end - px * outer * 0.85, dy * end - py * outer * 0.85)]:
            d.ellipse([cx + ox - k, cy + oy - k, cx + ox + k, cy + oy + k], fill=color)
    m = r * 0.24
    d.ellipse([cx - m, cy - m, cx + m, cy + m], fill=color)


def woman(d, cx, base_y, scale, body, veil):
    """Soft figure: rounded dome shoulders, a veil that flows from the head
    down onto the shoulders, and the face."""
    head_r = 190 * scale
    hy = base_y - 700 * scale
    sw = 560 * scale
    shoulder_top = base_y - 420 * scale
    # body: a big dome
    d.ellipse([cx - sw, shoulder_top, cx + sw, shoulder_top + sw * 2.2], fill=body)
    # veil: arch around the head flowing down to the shoulders
    vw = head_r * 1.45
    d.rounded_rectangle([cx - vw, hy - head_r * 1.35, cx + vw, shoulder_top + 120 * scale],
                        radius=int(vw), fill=veil)
    # face
    d.ellipse([cx - head_r, hy - head_r * 0.95, cx + head_r, hy + head_r * 1.05], fill=ROSE)


def draw(transparent_bg=False):
    if transparent_bg:
        img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    else:
        img = gradient(S, NAVY_TOP, NAVY_BOT).convert("RGBA")
    d = ImageDraw.Draw(img)
    cx = S / 2

    # Content area: adaptive icons crop to the centre ~66%, so keep the art
    # inside a circle of radius ~0.33*S around the centre.
    if not transparent_bg:
        ring_r = S * 0.43
        d.ellipse([cx - ring_r, cx - ring_r, cx + ring_r, cx + ring_r], outline=GOLD, width=int(S * 0.018))

    # soft halo behind the cross
    halo = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    hr = S * 0.15
    hy = S * 0.31
    hd.ellipse([cx - hr, hy - hr, cx + hr, hy + hr], fill=(214, 168, 74, 70))
    halo = halo.filter(ImageFilter.GaussianBlur(S * 0.03))
    img.alpha_composite(halo)
    d = ImageDraw.Draw(img)

    coptic_cross(d, cx, S * 0.31, S * 0.125, GOLD)

    base = S * 0.80
    # side women slightly smaller and behind; centre woman in front
    woman(d, cx - S * 0.205, base, 1.0 * S / 4096 * 0.92, body=(176, 72, 92), veil=(242, 236, 228))
    woman(d, cx + S * 0.205, base, 1.0 * S / 4096 * 0.92, body=(60, 120, 150), veil=(242, 236, 228))
    woman(d, cx, base + S * 0.02, 1.0 * S / 4096 * 1.05, body=GOLD, veil=CREAM)

    if not transparent_bg:
        # clip the bottom of the bodies to the ring for a medallion look
        mask = Image.new("L", (S, S), 0)
        md = ImageDraw.Draw(mask)
        r = S * 0.43 - S * 0.009
        md.ellipse([cx - r, cx - r, cx + r, cx + r], fill=255)
        bg = gradient(S, NAVY_TOP, NAVY_BOT).convert("RGBA")
        bg_draw = ImageDraw.Draw(bg)
        ring_r = S * 0.43
        bg_draw.ellipse([cx - ring_r, cx - ring_r, cx + ring_r, cx + ring_r], outline=GOLD, width=int(S * 0.018))
        bg.paste(img, (0, 0), mask)
        img = bg
    return img.resize((OUT, OUT), Image.LANCZOS)


if __name__ == "__main__":
    import os
    os.makedirs("assets/icon", exist_ok=True)
    draw().convert("RGB").save("assets/icon/app_icon.png")
    # Android adaptive icon: the launcher crops to its own shape (circle,
    # squircle...) and only the centre ~66% is safe. Use the whole medallion,
    # shrunk into the safe zone, on a transparent canvas; the background
    # colour fills the rest.
    full = draw().convert("RGBA")
    mask = Image.new("L", full.size, 0)
    r = OUT * 0.43 + OUT * 0.012
    c = OUT / 2
    ImageDraw.Draw(mask).ellipse([c - r, c - r, c + r, c + r], fill=255)
    medal = Image.new("RGBA", full.size, (0, 0, 0, 0))
    medal.paste(full, (0, 0), mask)
    side = int(OUT * 0.72)
    medal = medal.resize((side, side), Image.LANCZOS)
    fg = Image.new("RGBA", (OUT, OUT), (0, 0, 0, 0))
    fg.alpha_composite(medal, ((OUT - side) // 2, (OUT - side) // 2))
    fg.save("assets/icon/app_icon_foreground.png")
    print("written assets/icon/app_icon.png and app_icon_foreground.png")
