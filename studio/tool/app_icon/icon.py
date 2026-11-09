"""WYRM Studio app icon: parametric SVG masters and platform renders."""

# The mark: five nodes on the wyrm's arc (from the logo / log-in board), in a 220x130 box.
NODES = [(20, 85, 14), (65, 45, 17), (115, 30, 20), (165, 55, 17), (200, 100, 14)]
SPINE = "M20 85 C45 50 65 45 70 45 S105 25 115 30 S155 40 165 55 S190 95 200 100"
MARK_CX, MARK_CY = 110, 65   # visual centre of the mark box

PAL = {
  'night':  dict(bg0='#171B1F', bg1='#0B0D0F', glow='#4A2A12', glow_o=0.55, ring0='#F6B072', ring1='#D9732B', fill0='#F8BC85', fill1='#E07B2E', spine='#7A4A22', spine_o=0.9, hole='#0E1113'),
  'ember':  dict(bg0='#F09A4E', bg1='#C9612A', glow='#FFD3A8', glow_o=0.35, ring0='#1A1F23', ring1='#0E1113', fill0='#22282D', fill1='#0E1113', spine='#7A3A12', spine_o=0.55, hole='#E8893A'),
}

def defs(p, uid):
    return f'''<defs>
<linearGradient id="bg{uid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{p['bg0']}"/><stop offset="1" stop-color="{p['bg1']}"/></linearGradient>
<radialGradient id="gl{uid}" cx="0.5" cy="0.42" r="0.6"><stop offset="0" stop-color="{p['glow']}" stop-opacity="{p['glow_o']}"/><stop offset="0.45" stop-color="{p['glow']}" stop-opacity="{p['glow_o']*0.45:.3f}"/><stop offset="1" stop-color="{p['glow']}" stop-opacity="0"/></radialGradient>
<linearGradient id="hl{uid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.10"/><stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>
<linearGradient id="rg{uid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{p['ring0']}"/><stop offset="1" stop-color="{p['ring1']}"/></linearGradient>
<linearGradient id="fg{uid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{p['fill0']}"/><stop offset="1" stop-color="{p['fill1']}"/></linearGradient>
<filter id="sh{uid}" x="-30%" y="-30%" width="160%" height="170%"><feGaussianBlur in="SourceAlpha" stdDeviation="6"/><feOffset dy="7"/><feComponentTransfer><feFuncA type="linear" slope="0.45"/></feComponentTransfer><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>
<filter id="ts{uid}" x="-20%" y="-20%" width="140%" height="150%"><feGaussianBlur in="SourceAlpha" stdDeviation="14"/><feOffset dy="10"/><feComponentTransfer><feFuncA type="linear" slope="0.38"/></feComponentTransfer><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>
</defs>'''

def mark(p, uid, cx, cy, width, small=False, mono=None):
    """The mark centred at (cx, cy), `width` wide. small: three nodes, heavier strokes. mono: one colour."""
    s = width / 180.0
    if small:
        nodes = [(35, 82, 22), (110, 42, 30), (185, 82, 22)]   # three nodes, legible at 16-32 px
        ox, oy = 110, 62; sw = 13; spine = None
        s = width / 215.0
    else:
        nodes = NODES; ox, oy = MARK_CX, MARK_CY; sw = 8.4; spine = SPINE
        s = width / 215.0
    g = [f'<g transform="translate({cx:.2f} {cy:.2f}) scale({s:.4f}) translate({-ox} {-oy})">']
    if spine and not mono:
        holes = ''.join(f'<circle cx="{x}" cy="{y}" r="{r + sw/2 + 1.5:.2f}" fill="black"/>' for x, y, r in nodes)
        g.append(f'<mask id="sp{uid}" maskUnits="userSpaceOnUse" x="-50" y="-50" width="320" height="230"><rect x="-50" y="-50" width="320" height="230" fill="white"/>{holes}</mask>')
        g.append(f'<path d="{spine}" fill="none" stroke="{p["spine"]}" stroke-opacity="{p["spine_o"]}" stroke-width="4.5" stroke-linecap="round" mask="url(#sp{uid})"/>')
    g.append(f'<g filter="url(#sh{uid})">' if not mono else '<g>')
    mid = len(nodes) // 2
    for i, (x, y, r) in enumerate(nodes):
        if i == mid:
            col = mono or f'url(#fg{uid})'
            g.append(f'<circle cx="{x}" cy="{y}" r="{r + sw/2:.2f}" fill="{col}"/>')
            if not mono:
                g.append(f'<ellipse cx="{x - r*0.28:.2f}" cy="{y - r*0.38:.2f}" rx="{r*0.42:.2f}" ry="{r*0.26:.2f}" fill="#FFFFFF" fill-opacity="0.28"/>')
        else:
            col = mono or f'url(#rg{uid})'
            g.append(f'<circle cx="{x}" cy="{y}" r="{r:.2f}" fill="none" stroke="{col}" stroke-width="{sw}"/>')
    g.append('</g></g>')
    return '\n'.join(g)


def svg(body, w=1024, h=1024):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>'
