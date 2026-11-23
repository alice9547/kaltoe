#!/usr/bin/env python3
"""shared/photo-maltese.png (배경 제거한 실사 말티즈) → 맥·윈도우 실사 캐릭터 산출물을 만든다. (docs/spec.md 6-2절)
python3 표준 라이브러리 + macOS 기본 도구(sips)만 사용. 기존 픽셀 캐릭터 산출물(gen-mascot.py)은 건드리지 않는다.

  swift shared/make-photo-cutout.swift   # (필요할 때만) 사진 → shared/photo-maltese.png
  python3 shared/gen-photo.py

산출물:
  mac/Sources/Kaltoe/UI/PhotoMascotData.swift          표시용 PNG(긴 변 192px) base64 + 눈 좌표 + 메뉴바용 얼굴 PNG(72px) base64
  mac/Resources/AppIcon-photo-1024.png                 둥근 사각 배경 위의 사진 캐릭터 (Finder 아이콘)
  windows/Kaltoe.App/Assets/photo-maltese.png          표시용 PNG(긴 변 192px)
  windows/Kaltoe.App/Assets/tray-photo.ico             얼굴 부분 16·20·24·32
  windows/Kaltoe.App/Assets/app-photo.ico              둥근 사각 배경 위 캐릭터 16~256
"""
import base64, importlib.util, os, struct, subprocess, sys, tempfile, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "shared", "photo-maltese.png")

# 이미지(512x494) 기준 비율 좌표 (0~1). 눈물 덧그림 위치 — make-photo-cutout 결과에서 눈 중심을 재서 기록.
LEFT_EYE = (0.376, 0.395)
RIGHT_EYE = (0.640, 0.386)
# 얼굴(머리 전체, 귀 포함) 자르기 영역: 이미지 비율 (x, y, w, h). 아래쪽 FACE_FADE 만큼은 서서히 투명해진다.
# 자른 결과는 가운데에 놓은 정사각형(투명 여백)으로 만든다 — 맥 메뉴바 아이콘(18pt)·윈도우 트레이 아이콘용.
FACE = (0.02, 0.0, 0.96, 0.77)
FACE_FADE = 0.16               # 자른 높이 대비, 아래쪽에서 투명해지는 비율
FACE_MAC_PX = 72               # 맥 메뉴바용(18pt 의 4배) 내장 크기
DISPLAY_LONG = 192
ICON_BG = (0x8E, 0xC5, 0xE8)   # 하늘색 (여러 색을 렌더링해 비교한 뒤 고름 — 아래 고른 이유는 보고서 참고)
ICON_CHAR_WIDTH = 0.70         # 아이콘 1024 폭 대비 캐릭터 폭


def _load_mascot_module():
    spec = importlib.util.spec_from_file_location("gen_mascot", os.path.join(ROOT, "shared", "gen-mascot.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


gm = _load_mascot_module()   # Img, png, ico, resample, rounded_bg 재사용


# ---------- PNG 읽기 (8비트 RGB/RGBA, 비인터레이스) ----------
def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"PNG 아님: {path}"
    pos, idat, w = 8, b"", None
    while pos < len(data):
        ln, = struct.unpack(">I", data[pos:pos + 4])
        typ = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            assert depth == 8 and ctype in (2, 6) and interlace == 0, f"지원하지 않는 PNG 형식 {depth}/{ctype}/{interlace}"
        elif typ == b"IDAT":
            idat += body
        pos += 12 + ln
    bpp = 4 if ctype == 6 else 3
    raw = zlib.decompress(idat)
    stride = w * bpp
    img = gm.Img(w, h)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]; line = bytearray(raw[p + 1:p + 1 + stride]); p += 1 + stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        prev = line
        for x in range(w):
            o = (y * w + x) * 4
            if bpp == 4:
                img.px[o:o + 4] = line[x * 4:x * 4 + 4]
            else:
                img.px[o:o + 4] = bytes((line[x * 3], line[x * 3 + 1], line[x * 3 + 2], 255))
    return img


def write_bytes(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def sips_resize(img, nw, nh):
    """sips(CoreGraphics)로 크기를 바꾼다 — 확대에도 쓰므로 자체 면적평균 대신 사용."""
    with tempfile.TemporaryDirectory() as td:
        a, b = os.path.join(td, "a.png"), os.path.join(td, "b.png")
        write_bytes(a, gm.png(img))
        r = subprocess.run(["sips", "-z", str(nh), str(nw), a, "--out", b], capture_output=True)
        if r.returncode != 0:
            print("sips 실패:", r.stderr.decode(), file=sys.stderr); sys.exit(1)
        return read_png(b)


def over(dst, src, ox, oy):
    """src(비프리멀티 RGBA)를 dst 위에 알파 합성."""
    for y in range(src.h):
        dy = y + oy
        if not 0 <= dy < dst.h:
            continue
        for x in range(src.w):
            dx = x + ox
            if not 0 <= dx < dst.w:
                continue
            s = (y * src.w + x) * 4
            sa = src.px[s + 3]
            if sa == 0:
                continue
            d = (dy * dst.w + dx) * 4
            da = dst.px[d + 3]
            if sa == 255 or da == 0:
                dst.px[d:d + 4] = src.px[s:s + 4]
                continue
            a = sa / 255
            oa = a + da / 255 * (1 - a)
            for k in range(3):
                dst.px[d + k] = round((src.px[s + k] * a + dst.px[d + k] * (da / 255) * (1 - a)) / oa)
            dst.px[d + 3] = round(oa * 255)


def crop(img, x, y, w, h):
    out = gm.Img(w, h)
    for yy in range(h):
        sy = y + yy
        if not 0 <= sy < img.h:
            continue
        for xx in range(w):
            sx = x + xx
            if 0 <= sx < img.w:
                out.px[(yy * w + xx) * 4:(yy * w + xx) * 4 + 4] = img.px[(sy * img.w + sx) * 4:(sy * img.w + sx) * 4 + 4]
    return out


def face_image(src):
    """머리 전체를 자르고 아래쪽을 서서히 투명하게 한 뒤, 가운데에 놓은 정사각형 이미지."""
    fx, fy = round(FACE[0] * src.w), round(FACE[1] * src.h)
    fw, fh = round(FACE[2] * src.w), round(FACE[3] * src.h)
    face = crop(src, fx, fy, fw, fh)
    fade_rows = round(fh * FACE_FADE)
    for y in range(fh - fade_rows, fh):
        k = (fh - 1 - y) / fade_rows            # 1 → 0
        for x in range(fw):
            i = (y * fw + x) * 4 + 3
            face.px[i] = round(face.px[i] * k)
    side = max(fw, fh)
    sq = gm.Img(side, side)
    over(sq, face, (side - fw) // 2, (side - fh) // 2)
    return sq


def display_image(src):
    scale = DISPLAY_LONG / max(src.w, src.h)
    return gm.resample(src, max(1, round(src.w * scale)), max(1, round(src.h * scale)))


def master_icon(src, bg=ICON_BG, size=1024):
    img = gm.rounded_bg(size, round(size * 100 / 1024), 0.225, bg)
    cw = round(size * ICON_CHAR_WIDTH)
    ch = round(src.h * cw / src.w)
    dog = sips_resize(src, cw, ch)
    over(img, dog, (size - cw) // 2, (size - ch) // 2 + round(size * 0.01))
    return img


def gen_sources(disp, face):
    b64 = base64.b64encode(gm.png(disp)).decode()
    face_b64 = base64.b64encode(gm.png(gm.resample(face, FACE_MAC_PX, FACE_MAC_PX))).decode()
    header = "생성된 파일 — 직접 고치지 말 것. 원본: shared/photo-maltese.png, 생성: shared/gen-photo.py"
    lines = [b64[i:i + 100] for i in range(0, len(b64), 100)]
    # 멀티라인 리터럴: 줄 끝의 `\` 가 줄바꿈을 지워 한 줄짜리 문자열이 된다 (`+` 로 잇는 것보다 컴파일이 빠르다).
    body = '\\\n        '.join(lines)
    text = (f"// {header}\nimport CoreGraphics\n\n"
            f"/// 실사 말티즈 (docs/spec.md 6-2절). 표시용 PNG(긴 변 {DISPLAY_LONG}px, {disp.w}x{disp.h}) 를 코드에 내장한다 (swift run 은 번들 리소스가 없다).\n"
            "/// 좌표는 모두 이미지 기준 비율(0~1, 왼쪽 위 원점).\n"
            "enum PhotoMascotData {\n"
            f"    static let pngBase64: String = \"\"\"\n        {body}\n        \"\"\"\n"
            f"    static let leftEye = CGPoint(x: {LEFT_EYE[0]}, y: {LEFT_EYE[1]})\n"
            f"    static let rightEye = CGPoint(x: {RIGHT_EYE[0]}, y: {RIGHT_EYE[1]})\n"
            f"    /// 메뉴바 아이콘용 얼굴 PNG({FACE_MAC_PX}x{FACE_MAC_PX}, 머리 전체를 가운데에 놓고 아래쪽은 서서히 투명) base64.\n"
            f"    static let faceBase64: String = \"\"\"\n        {face_b64}\n        \"\"\"\n"
            "}\n")
    with open(os.path.join(ROOT, "mac/Sources/Kaltoe/UI/PhotoMascotData.swift"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def gen_icons(src, disp, face):
    res = os.path.join(ROOT, "mac", "Resources")
    assets = os.path.join(ROOT, "windows/Kaltoe.App/Assets")
    write_bytes(os.path.join(assets, "photo-maltese.png"), gm.png(disp))

    m = master_icon(src)
    write_bytes(os.path.join(res, "AppIcon-photo-1024.png"), gm.png(m))
    m512 = gm.resample(m, 512, 512)
    m256 = gm.resample(m512, 256, 256)
    cache = {256: m256}
    def at(n):
        if n not in cache:
            cache[n] = gm.resample(m256, n, n)
        return cache[n]
    write_bytes(os.path.join(assets, "app-photo.ico"), gm.ico([(n, gm.png(at(n))) for n in (16, 32, 48, 64, 128, 256)]))

    # 트레이: 배경 없이 얼굴만
    write_bytes(os.path.join(assets, "tray-photo.ico"),
                gm.ico([(n, gm.png(gm.resample(face, n, n))) for n in (16, 20, 24, 32)]))


def main():
    src = read_png(SRC)
    disp = display_image(src)
    face = face_image(src)
    gen_sources(disp, face)
    gen_icons(src, disp, face)
    print(f"OK: 원본 {src.w}x{src.h} → 표시 {disp.w}x{disp.h}, 아이콘 배경 #{ICON_BG[0]:02X}{ICON_BG[1]:02X}{ICON_BG[2]:02X}")


if __name__ == "__main__":
    main()
