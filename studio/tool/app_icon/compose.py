"""Composite the icon: float background (no banding) + vector mark from rsvg."""
import io, subprocess, numpy as np
from PIL import Image, ImageFilter
from icon import PAL, defs, mark, svg

def _rsvg(svg_text, px):
    png = subprocess.run(['rsvg-convert', '-w', str(px), '-h', str(px)], input=svg_text.encode(), capture_output=True, check=True).stdout
    return Image.open(io.BytesIO(png)).convert('RGBA')

def _hex(c):
    c = c.lstrip('#'); return np.array([int(c[i:i+2], 16) for i in (0, 2, 4)], dtype=np.float64)

def _background(p, px, seed=11):
    y, x = np.mgrid[0:px, 0:px].astype(np.float64) / px
    base = _hex(p['bg0'])[None, None, :] * (1 - y[..., None]) + _hex(p['bg1'])[None, None, :] * y[..., None]
    d2 = ((x - 0.5) / 0.60) ** 2 + ((y - 0.42) / 0.60) ** 2
    a = p['glow_o'] * np.exp(-2.6 * d2)
    rgb = base * (1 - a[..., None]) + _hex(p['glow'])[None, None, :] * a[..., None]
    hl = np.clip(0.10 * (1 - y / 0.5), 0, None)
    rgb = rgb * (1 - hl[..., None]) + 255 * hl[..., None]
    rng = np.random.default_rng(seed)
    rgb = rgb + rng.uniform(-0.5, 0.5, rgb.shape)      # dither before rounding
    return np.clip(np.rint(rgb), 0, 255).astype(np.uint8)

def compose(variant, px, tile=None, mark_at=None, small=False, shadow=False, mono=None, background=True, flatten=None):
    """tile: (x, y, size, radius|None) in 1024 units, None = no background.
    mark_at: (cx, cy, width) in 1024 units, None = no mark."""
    p = PAL[variant]; u = 'a'; k = px / 1024
    out = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    if tile and background:
        tx, ty, ts, tr = tile
        rr = f' rx="{tr}"' if tr else ''
        shape = _rsvg(svg(f'<rect x="{tx}" y="{ty}" width="{ts}" height="{ts}"{rr} fill="#fff"/>'), px).split()[3]
        if shadow:
            sh = Image.new('RGBA', (px, px), (0, 0, 0, 0))
            blur = shape.filter(ImageFilter.GaussianBlur(14 * k)).point(lambda v: int(v * 0.42))
            sh.putalpha(blur)
            out.alpha_composite(sh, (0, int(round(10 * k))))
        bg = Image.fromarray(_background(p, px), 'RGB').convert('RGBA'); bg.putalpha(shape)
        out.alpha_composite(bg)
        if tr:
            edge = _rsvg(svg(f'<rect x="{tx+1.5}" y="{ty+1.5}" width="{ts-3}" height="{ts-3}" rx="{tr-1.5}" fill="none" stroke="#FFFFFF" stroke-opacity="0.08" stroke-width="3"/>'), px)
            out.alpha_composite(edge)
    if mark_at:
        cx, cy, w = mark_at
        out.alpha_composite(_rsvg(svg(defs(p, u) + mark(p, u, cx, cy, w, small, mono)), px))
    if flatten:
        bgc = Image.new('RGBA', out.size, flatten); bgc.alpha_composite(out); return bgc.convert('RGB')
    return out

# Platform recipes (1024 units)
def macos(variant, px):
    small = px <= 32
    return compose(variant, px, (100, 100, 824, 185.4), (512, 560, 640 if small else 620), small, shadow=True)
def ios(variant, px):
    small = px <= 40
    return compose(variant, px, (0, 0, 1024, None), (512, 548, 760 if small else 780), small, flatten='#0E1113')
def rounded(variant, px, margin=0):
    small = px <= 32; s = 1024 - 2 * margin
    return compose(variant, px, (margin, margin, s, s * 0.2237), (512, 512 + s * 0.035, s * (0.78 if small else 0.76)), small)
def maskable(variant, px):
    return compose(variant, px, (0, 0, 1024, None), (512, 540, 600), False, flatten='#0E1113')
def android_fg(variant, px):
    return compose(variant, px, None, (512, 540, 1024 * 50 / 108))
def android_mono(variant, px):
    return compose(variant, px, None, (512, 540, 1024 * 50 / 108), mono='#FFFFFF')
def android_bg(variant, px):
    return compose(variant, px, (0, 0, 1024, None), None)
