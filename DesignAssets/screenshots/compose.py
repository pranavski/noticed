import random, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

import os
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "../.."))
RAW = os.path.join(HERE, "iphone-6.9/raw")
OUT = os.path.join(HERE, "iphone-6.9")
F = os.path.join(ROOT, "Soma/Fonts") + "/"
W, H = 1320, 2868
PAPER, INK, INKSOFT, PERSIMMON = (240,230,210), (58,42,32), (140,116,96), (200,84,43)

SHOTS = [
    ("01-noticed",          "patterns in your own record, hedged"),
    ("02-today",            "say it, it's written"),
    ("03-capture",          "ten seconds, by voice or by hand"),
    ("04-compare-yesterday","yesterday, laid over today"),
    ("05-consent",          "you decide what goes to Claude"),
    ("06-kitchen",          "export it, or delete it, any time"),
]

def font(name, size):
    return ImageFont.truetype(F + name, size)

def paper_bg():
    bg = Image.new("RGB", (W, H), PAPER)
    # window light from the upper left, like PaperBackground
    light = Image.new("L", (W, H), 0)
    ImageDraw.Draw(light).ellipse((-700, -900, 1300, 1100), fill=90)
    light = light.filter(ImageFilter.GaussianBlur(260))
    bg = Image.composite(Image.new("RGB", (W, H), (250,243,229)), bg, light)
    # edge vignette
    vig = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vig).rectangle((0, 0, W, H), outline=70, width=90)
    vig = vig.filter(ImageFilter.GaussianBlur(120))
    bg = Image.composite(Image.new("RGB", (W, H), (214,198,170)), bg, vig)
    # seeded grain
    rnd = random.Random(7)
    d = ImageDraw.Draw(bg)
    for _ in range(26000):
        x, y = rnd.randrange(W), rnd.randrange(H)
        c = rnd.choice([(120,96,74), (255,250,238)])
        d.point((x, y), fill=c)
    return bg

def wrap(draw, text, fnt, maxw):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if draw.textlength(t, font=fnt) <= maxw: cur = t
        else: lines.append(cur); cur = w
    lines.append(cur)
    return lines

def wobble_rule(draw, x0, x1, y, color, width=4):
    import math
    pts = [(x, y + 3*math.sin(x/38.0) + 1.5*math.sin(x/11.0)) for x in range(x0, x1+1, 4)]
    draw.line(pts, fill=color, width=width, joint="curve")

base = paper_bg()
eyebrow_f = font("IBMPlexMono-Medium.ttf", 34)
cap_f = font("Fraunces-Italic.ttf", 104)
cap_f.set_variation_by_axes([72, 400, 0, 1])
margin = 110

for i, (name, caption) in enumerate(SHOTS, 1):
    img = base.copy()
    d = ImageDraw.Draw(img)
    # eyebrow: plate numeral, tracked mono
    eb = f"NO. {i:02d}"
    x = margin
    for ch in eb:
        d.text((x, 190), ch, font=eyebrow_f, fill=INKSOFT)
        x += d.textlength(ch, font=eyebrow_f) + 8
    # caption with a persimmon period, like the wordmark
    lines = wrap(d, caption, cap_f, W - 2*margin)
    y = 262
    for j, ln in enumerate(lines):
        d.text((margin, y), ln, font=cap_f, fill=INK)
        if j == len(lines) - 1:
            dx = d.textlength(ln, font=cap_f)
            d.text((margin + dx, y), ".", font=cap_f, fill=PERSIMMON)
        y += 124
    rule_y = y + 36
    wobble_rule(d, margin, margin + 180, rule_y, PERSIMMON, 5)

    # screenshot, scaled, rounded, bleeding off the bottom edge
    shot = Image.open(f"{RAW}/{name}.png").convert("RGB")
    sw = 1080
    sh = round(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    top = max(rule_y + 90, 700) if len(lines) > 1 else rule_y + 90
    top = 636  # same for every frame so the set lines up in the store
    sx = (W - sw) // 2
    r = 150
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw-1, sh-1), r, fill=255)
    # warm shadow, never black
    sh_layer = Image.new("L", (W, H), 0)
    ImageDraw.Draw(sh_layer).rounded_rectangle((sx, top+24, sx+sw, top+sh+24), r, fill=110)
    sh_layer = sh_layer.filter(ImageFilter.GaussianBlur(40))
    img = Image.composite(Image.new("RGB", (W, H), (96,76,66)), img, sh_layer)
    img.paste(shot, (sx, top), mask)
    # hairline ink border
    ImageDraw.Draw(img).rounded_rectangle((sx, top, sx+sw-1, top+sh-1), r,
                                          outline=(74,58,48), width=4)
    assert img.size == (W, H) and img.mode == "RGB"
    img.save(f"{OUT}/{name}.png", optimize=True)
    print(name, len(lines), "lines, shot top", top)
