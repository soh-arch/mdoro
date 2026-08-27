"""Mdoro のアプリアイコンを 8.5.3 のトークンから描く。

マークは「進行インジケータの形をしたチェックボックス」。角丸正方形のリングを軌道
（--border-subtle）で全周描き、その 3/4 を Focus の色（--ink-graphic）で 12 時から
時計回りに重ねる。集中表示ビューの進行バーと同じ構成である。
"""
import math
from PIL import Image, ImageDraw

SS = 4  # スーパーサンプリング倍率

LIGHT = {"bg": "#F7F3ED", "track": "#D8D3CB", "mark": "#22759E"}
DARK  = {"bg": "#13110D", "track": "#39362F", "mark": "#58A6D1"}
TINT  = {"bg": "#000000", "track": "#595959", "mark": "#FFFFFF"}

PROGRESS = 0.75          # 3/4 周
SIDE_RATIO = 0.56        # マークの外形 / 地の一辺
CORNER_RATIO = 0.18      # マークの角丸 / マークの一辺
STROKE_RATIO = 0.148     # 線幅 / マークの一辺


def rounded_rect_path(cx, cy, side, radius, steps=2048):
    """12 時から時計回りに角丸正方形の外周を等間隔サンプリングする。"""
    h = side / 2
    l, r_, t, b = cx - h, cx + h, cy - h, cy + h
    rr = radius
    segs = []
    segs.append(("line", (cx, t), (r_ - rr, t)))
    segs.append(("arc", (r_ - rr, t + rr), -90, 0))
    segs.append(("line", (r_, t + rr), (r_, b - rr)))
    segs.append(("arc", (r_ - rr, b - rr), 0, 90))
    segs.append(("line", (r_ - rr, b), (l + rr, b)))
    segs.append(("arc", (l + rr, b - rr), 90, 180))
    segs.append(("line", (l, b - rr), (l, t + rr)))
    segs.append(("arc", (l + rr, t + rr), 180, 270))
    segs.append(("line", (l + rr, t), (cx, t)))

    lengths = []
    for s in segs:
        if s[0] == "line":
            (x0, y0), (x1, y1) = s[1], s[2]
            lengths.append(math.hypot(x1 - x0, y1 - y0))
        else:
            lengths.append(abs(math.radians(s[3] - s[2])) * rr)
    total = sum(lengths)

    pts = []
    for s, ln in zip(segs, lengths):
        n = max(2, int(steps * ln / total))
        for i in range(n + 1):
            u = i / n
            if s[0] == "line":
                (x0, y0), (x1, y1) = s[1], s[2]
                pts.append((x0 + (x1 - x0) * u, y0 + (y1 - y0) * u))
            else:
                (ax, ay), a0, a1 = s[1], s[2], s[3]
                a = math.radians(a0 + (a1 - a0) * u)
                pts.append((ax + rr * math.cos(a), ay + rr * math.sin(a)))
    return pts, total


def cut(pts, fraction):
    """先頭から全長の fraction ぶんだけ取り出す。"""
    seglen = [math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]
    target = sum(seglen) * fraction
    out, acc = [pts[0]], 0.0
    for i, ln in enumerate(seglen):
        if acc + ln >= target:
            u = (target - acc) / ln
            x = pts[i][0] + (pts[i + 1][0] - pts[i][0]) * u
            y = pts[i][1] + (pts[i + 1][1] - pts[i][1]) * u
            out.append((x, y))
            break
        acc += ln
        out.append(pts[i + 1])
    return out


def stamp(d, pts, w, fill):
    """経路上に円を敷き詰めて線を引く。丸い端点と角の滑らかさをこれで得る
    （ImageDraw.line の joint="curve" は角にぎざつきを残す）。"""
    r = w / 2
    for x, y in pts:
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def draw_mark(d, cx, cy, tile, colors):
    side = tile * SIDE_RATIO
    stroke = side * STROKE_RATIO
    radius = side * CORNER_RATIO
    pts, _ = rounded_rect_path(cx, cy, side, radius, steps=6000)
    stamp(d, pts, stroke, colors["track"])
    stamp(d, cut(pts, PROGRESS), stroke, colors["mark"])


def render(colors, platform, size=1024):
    n = size * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if platform == "ios":
        d.rectangle([0, 0, n, n], fill=colors["bg"])   # 角丸は OS が被せる
        tile = n
        cx = cy = n / 2
    else:
        tile = n * 824 / 1024                          # macOS のアイコングリッド
        r = n * 185.4 / 1024
        off = (n - tile) / 2
        d.rounded_rectangle([off, off, off + tile, off + tile], radius=r, fill=colors["bg"])
        cx = cy = n / 2
    draw_mark(d, cx, cy, tile, colors)
    return img.resize((size, size), Image.LANCZOS)


# アセットカタログへの書き出し。`python3 Tools/make_icon.py` で上書きする。
IOS = "PomodoroMac/PomodoroiOS/Assets.xcassets/AppIcon.appiconset"
MAC = "PomodoroMac/PomodoroMac/Assets.xcassets/AppIcon.appiconset"
MAC_SIZES = [16, 32, 128, 256, 512]


def write_assets(repo="."):
    import json
    import os

    ios = os.path.join(repo, IOS)
    render(LIGHT, "ios").save(os.path.join(ios, "icon-light-1024.png"))
    render(DARK, "ios").save(os.path.join(ios, "icon-dark-1024.png"))
    render(TINT, "ios").save(os.path.join(ios, "icon-tinted-1024.png"))
    json.dump({"images": [
        {"filename": "icon-light-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        {"appearances": [{"appearance": "luminosity", "value": "dark"}],
         "filename": "icon-dark-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        {"appearances": [{"appearance": "luminosity", "value": "tinted"}],
         "filename": "icon-tinted-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
    ], "info": {"author": "xcode", "version": 1}}, open(os.path.join(ios, "Contents.json"), "w"), indent=2)

    mac = os.path.join(repo, MAC)
    base = render(LIGHT, "mac")
    images = []
    for pt in MAC_SIZES:
        for scale in (1, 2):
            name = f"icon-mac-{pt}@{scale}x.png"
            base.resize((pt * scale, pt * scale), Image.LANCZOS).save(os.path.join(mac, name))
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
    json.dump({"images": images, "info": {"author": "xcode", "version": 1}},
              open(os.path.join(mac, "Contents.json"), "w"), indent=2)


if __name__ == "__main__":
    import sys
    write_assets(sys.argv[1] if len(sys.argv) > 1 else ".")
    print("wrote AppIcon.appiconset for macOS and iOS")
