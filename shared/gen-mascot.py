#!/usr/bin/env python3
"""shared/mascot.json (원본 하나) → 맥·윈도우 소스와 아이콘을 모두 생성한다. 표준 라이브러리만 사용.

  python3 Scripts/gen-mascot.py

산출물:
  mac/Sources/Kaltoe/UI/MascotData.swift, MascotDataOrange.swift
  windows/Kaltoe.App/MascotData.cs
  mac/Resources/AppIcon-1024.png, mac/Resources/AppIcon.icns   (주황이 idle, iconutil 필요, macOS)
  windows/Kaltoe.App/Assets/app.ico (주황이), app-maltese.ico, tray.ico, tray-orange.ico
"""
import json, os, struct, subprocess, sys, tempfile, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAMES = ["idle", "blink", "breathe", "sleep", "eat1", "eat2", "sparkle", "hop", "danceL", "danceR", "angry1", "angry2", "cry1", "cry2"]
ICON_BG_MALTESE = (0x8E, 0xC5, 0xE8)   # 하늘색 — 흰 강아지가 또렷하게 돋보이는 쪽
ICON_BG_ORANGE = (0x1B, 0x1B, 0x1F)    # 어두운 터미널색 — 주황이가 가장 또렷하게 돋보임 (크림색과 렌더링 비교 후 선택)
HEADER = "생성된 파일 — 직접 고치지 말 것. 원본: shared/mascot.json, 생성: shared/gen-mascot.py"


# ---------- 읽기·검증 ----------
def load(filename="mascot.json"):
    with open(os.path.join(ROOT, "shared", filename), encoding="utf-8") as f:
        d = json.load(f)
    w, h = d["width"], d["height"]
    pal = d["palette"]
    errors = []
    if not (16 <= w <= 24 and 16 <= h <= 24):
        errors.append(f"격자 크기 {w}x{h} 는 16~24 범위를 벗어남")
    for k, v in pal.items():
        if len(k) != 1 or not k.isalnum() or k.isspace():
            errors.append(f"팔레트 키 '{k}' 는 영숫자 한 글자여야 함")
        if not (isinstance(v, str) and len(v) == 7 and v[0] == "#"):
            errors.append(f"팔레트 값 {k}={v} 는 #RRGGBB 형식이어야 함")
        else:
            int(v[1:], 16)
    for name in FRAMES:
        rows = d["frames"].get(name)
        if rows is None:
            errors.append(f"프레임 '{name}' 없음"); continue
        if len(rows) != h:
            errors.append(f"{name}: 줄 수 {len(rows)} != {h}")
        for i, r in enumerate(rows):
            if len(r) != w:
                errors.append(f"{name}[{i}]: 길이 {len(r)} != {w}")
            for ch in r:
                if ch != "." and ch not in pal:
                    errors.append(f"{name}[{i}]: 팔레트에 없는 문자 '{ch}'")
    extra = set(d["frames"]) - set(FRAMES)
    if extra:
        errors.append(f"알 수 없는 프레임: {sorted(extra)}")
    if errors:
        print(f"{filename} 검증 실패:", *errors[:30], sep="\n  ", file=sys.stderr)
        sys.exit(1)
    return w, h, {k: int(v[1:], 16) for k, v in pal.items()}, {n: d["frames"][n] for n in FRAMES}


# ---------- 소스 생성 ----------
def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def swift_enum(name, w, h, pal, frames):
    p = ", ".join(f'"{k}": 0x{v:06X}' for k, v in pal.items())
    fr = ",\n".join(f'        "{n}": [\n' + ",\n".join(f'            "{r}"' for r in rows) + "\n        ]"
                    for n, rows in frames.items())
    return (f"enum {name} {{\n    static let width: Int = {w}\n    static let height: Int = {h}\n"
            f"    static let palette: [Character: UInt32] = [{p}]\n"
            f"    static let frames: [String: [String]] = [\n{fr},\n    ]\n}}\n")


def cs_class(name, w, h, pal, frames):
    p = ", ".join(f"['{k}'] = 0x{v:06X}" for k, v in pal.items())
    fr = ",\n".join(f'        ["{n}"] = new[]\n        {{\n' + ",\n".join(f'            "{r}"' for r in rows) + "\n        }"
                    for n, rows in frames.items())
    return (f"public static class {name}\n{{\n"
            f"    public const int Width = {w};\n    public const int Height = {h};\n"
            f"    public static readonly IReadOnlyDictionary<char, uint> Palette = new Dictionary<char, uint> {{ {p} }};\n"
            f"    public static readonly IReadOnlyDictionary<string, string[]> Frames = new Dictionary<string, string[]>\n    {{\n{fr},\n    }};\n}}\n")


def gen_sources(maltese, orange):
    write(os.path.join(ROOT, "mac/Sources/Kaltoe/UI/MascotData.swift"), f"// {HEADER}\n" + swift_enum("MascotData", *maltese))
    write(os.path.join(ROOT, "mac/Sources/Kaltoe/UI/MascotDataOrange.swift"),
          f"// {HEADER}\n// 원본: shared/mascot-orange.json\n" + swift_enum("MascotDataOrange", *orange))
    write(os.path.join(ROOT, "windows/Kaltoe.App/MascotData.cs"),
          f"// {HEADER}\nnamespace Kaltoe.App;\n\n" + cs_class("MascotData", *maltese)
          + "\n" + cs_class("MascotDataOrange", *orange))


# ---------- 래스터 (RGBA 비프리멀티, 리스트 기반) ----------
class Img:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = bytearray(w * h * 4)

    def fill_rect(self, x0, y0, x1, y1, c):
        r, g, b, a = c
        for y in range(max(0, y0), min(self.h, y1)):
            for x in range(max(0, x0), min(self.w, x1)):
                i = (y * self.w + x) * 4
                self.px[i:i + 4] = bytes((r, g, b, a))


def rounded_bg(size, margin, radius_ratio, color):
    img = Img(size, size)
    x0 = y0 = margin
    x1 = y1 = size - margin
    r = (x1 - x0) * radius_ratio
    for y in range(y0, y1):
        for x in range(x0, x1):
            # 모서리 호 안쪽만 칠한다 (4x4 슈퍼샘플로 가장자리 부드럽게)
            cov = 0
            for sy in range(4):
                for sx in range(4):
                    px, py = x + (sx + .5) / 4, y + (sy + .5) / 4
                    cx = min(max(px, x0 + r), x1 - r)
                    cy = min(max(py, y0 + r), y1 - r)
                    if (px - cx) ** 2 + (py - cy) ** 2 <= r * r:
                        cov += 1
            if cov:
                i = (y * size + x) * 4
                img.px[i:i + 4] = bytes((*color, round(255 * cov / 16)))
    return img


def draw_frame(img, frame, pal, ox, oy, scale, crop=None):
    rows = frame if crop is None else frame[crop[0]:crop[1]]
    for ry, row in enumerate(rows):
        for rx, ch in enumerate(row):
            if ch == ".":
                continue
            c = pal[ch]
            img.fill_rect(ox + rx * scale, oy + ry * scale, ox + (rx + 1) * scale, oy + (ry + 1) * scale,
                          ((c >> 16) & 255, (c >> 8) & 255, c & 255, 255))


def resample(src, nw, nh):
    """면적 평균 축소 (프리멀티 알파)."""
    sw, sh = src.w, src.h
    tmp = [[0.0] * 4 for _ in range(nw * sh)]
    for y in range(sh):
        for ox in range(nw):
            a, b = ox * sw / nw, (ox + 1) * sw / nw
            acc = [0.0, 0.0, 0.0, 0.0]
            x = int(a)
            while x < b and x < sw:
                wgt = min(b, x + 1) - max(a, x)
                i = (y * sw + x) * 4
                al = src.px[i + 3] / 255
                acc[0] += src.px[i] * al * wgt; acc[1] += src.px[i + 1] * al * wgt
                acc[2] += src.px[i + 2] * al * wgt; acc[3] += al * wgt
                x += 1
            tmp[y * nw + ox] = acc
    out = Img(nw, nh)
    for oy in range(nh):
        a, b = oy * sh / nh, (oy + 1) * sh / nh
        for x in range(nw):
            acc = [0.0, 0.0, 0.0, 0.0]
            y = int(a)
            while y < b and y < sh:
                wgt = min(b, y + 1) - max(a, y)
                t = tmp[y * nw + x]
                for k in range(4):
                    acc[k] += t[k] * wgt
                y += 1
            area = (b - a) * (sw / nw)
            al = acc[3] / area
            i = (oy * nw + x) * 4
            if al > 0:
                out.px[i:i + 4] = bytes((min(255, round(acc[0] / acc[3])), min(255, round(acc[1] / acc[3])),
                                         min(255, round(acc[2] / acc[3])), min(255, round(al * 255))))
    return out


def png(img):
    raw = b"".join(b"\0" + bytes(img.px[y * img.w * 4:(y + 1) * img.w * 4]) for y in range(img.h))
    def chunk(t, b):
        return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", img.w, img.h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def ico(images):
    """images: [(size, png_bytes)] → PNG 압축 ICO."""
    head = struct.pack("<HHH", 0, 1, len(images))
    off = 6 + 16 * len(images)
    entries, blobs = b"", b""
    for size, data in images:
        entries += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(data), off + len(blobs))
        blobs += data
    return head + entries + blobs


def master_icon(frame, pal, bg, size=1024, center_bbox=False):
    img = rounded_bg(size, round(size * 100 / 1024), 0.225, bg)
    scale = int(size * 0.70) // len(frame[0])
    ox = (size - scale * len(frame[0])) // 2
    oy = (size - scale * len(frame)) // 2 + scale // 2
    if center_bbox:   # 불투명 픽셀의 경계 상자 기준으로 가운데에 놓는다 (여백이 비대칭인 격자용)
        cols = [x for r in frame for x, ch in enumerate(r) if ch != "."]
        rws = [y for y, r in enumerate(frame) if any(ch != "." for ch in r)]
        ox = (size - scale * (max(cols) - min(cols) + 1)) // 2 - min(cols) * scale
        oy = (size - scale * (max(rws) - min(rws) + 1)) // 2 - min(rws) * scale
    draw_frame(img, frame, pal, ox, oy, scale)
    return img


def master_tray(frame, pal, rows=(0, 14)):
    face = frame[rows[0]:rows[1]]
    w = len(face[0])
    side = max(w, len(face))
    scale = 32
    img = Img(side * scale, side * scale)
    draw_frame(img, face, pal, (side - w) // 2 * scale, (side - len(face)) // 2 * scale, scale)
    return img


def icon_set(frame, pal, bg, center_bbox=False):
    """마스터 1024 → {크기: Img} 캐시 함수."""
    m = master_icon(frame, pal, bg, center_bbox=center_bbox)
    m512 = resample(m, 512, 512)
    m256 = resample(m512, 256, 256)
    cache = {1024: m, 512: m512, 256: m256}
    def at(n):
        if n not in cache:
            cache[n] = resample(m256, n, n)
        return cache[n]
    return m, at


def gen_icons(maltese, orange):
    w, h, pal, frames = maltese
    ow, oh, opal, oframes = orange
    res = os.path.join(ROOT, "mac", "Resources")
    assets = os.path.join(ROOT, "windows/Kaltoe.App/Assets")
    os.makedirs(res, exist_ok=True)
    os.makedirs(assets, exist_ok=True)

    # 앱 아이콘 = 주황이 idle
    m, at = icon_set(oframes["idle"], opal, ICON_BG_ORANGE, center_bbox=True)
    open(os.path.join(res, "AppIcon-1024.png"), "wb").write(png(m))
    with tempfile.TemporaryDirectory() as td:
        iconset = os.path.join(td, "AppIcon.iconset")
        os.makedirs(iconset)
        for base in (16, 32, 128, 256, 512):
            open(os.path.join(iconset, f"icon_{base}x{base}.png"), "wb").write(png(at(base)))
            open(os.path.join(iconset, f"icon_{base}x{base}@2x.png"), "wb").write(png(at(base * 2)))
        r = subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(res, "AppIcon.icns")])
        if r.returncode != 0:
            print("iconutil 실패", file=sys.stderr); sys.exit(1)
    sizes = (16, 32, 48, 64, 128, 256)
    open(os.path.join(assets, "app.ico"), "wb").write(ico([(n, png(at(n))) for n in sizes]))

    # 윈도우 설정 창용 말티즈 얼굴 아이콘 (예전 말티즈 앱 아이콘과 같은 그림)
    mm, mat = icon_set(frames["idle"], pal, ICON_BG_MALTESE)
    open(os.path.join(res, "AppIcon-maltese-1024.png"), "wb").write(png(mm))
    open(os.path.join(assets, "app-maltese.ico"), "wb").write(ico([(n, png(mat(n))) for n in sizes]))

    # 트레이 아이콘 (배경 없이 얼굴만)
    t = master_tray(frames["idle"], pal)
    open(os.path.join(assets, "tray.ico"), "wb").write(ico([(n, png(resample(t, n, n))) for n in (16, 20, 24, 32)]))
    to = master_tray(oframes["idle"], opal, rows=(3, 14))
    open(os.path.join(assets, "tray-orange.ico"), "wb").write(ico([(n, png(resample(to, n, n))) for n in (16, 20, 24, 32)]))


def main():
    maltese = load("mascot.json")
    orange = load("mascot-orange.json")
    gen_sources(maltese, orange)
    gen_icons(maltese, orange)
    print(f"OK: 말티즈 {maltese[0]}x{maltese[1]} {len(maltese[2])}색, 주황이 {orange[0]}x{orange[1]} {len(orange[2])}색, 프레임 {len(maltese[3])}개씩")


if __name__ == "__main__":
    main()
