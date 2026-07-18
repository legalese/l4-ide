#!/usr/bin/env python3
"""
Render the s 415 surplusage argument as a ladder diagram (SVG, no dependencies).

Two panels of the SAME circuit (the second limb in the no-property world), under
the two readings. The 'dishonest concealment' rung is a live parallel contact
under the court's reading; under the applicants' reading it is a contact that can
NEVER carry current — an OTIOSE rung the minimiser deletes. Surplusage, drawn.

Follows the conventions of l4wt/ladder-diagrams-3 DESIGN.md: LR orientation,
AND = series, OR = parallel rungs, Tufte hairlines, green = live, grey = inert.
It also exercises a *proposed* 4th leaf state (see that DESIGN, proposed §6a):
ELIMINABLE / don't-care — distinct from known-false.
"""

GREEN, GREY, DEAD, RAIL, INK = "#1a7f37", "#9aa0a6", "#b9bdc2", "#3a3a3a", "#222"
W, PANEL_H = 1200, 340
svg = []

def rect(x, y, w, h, stroke, fill="#ffffff", dash=None, op=1.0, rx=7):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    svg.append(f'<rect x="{x:.0f}" y="{y:.0f}" width="{w:.0f}" height="{h:.0f}" rx="{rx}" '
               f'fill="{fill}" stroke="{stroke}" stroke-width="1.5"{d} opacity="{op}"/>')

def text(x, y, s, size=14, anchor="middle", fill=INK, op=1.0, weight="400", style=""):
    st = f' font-style="{style}"' if style else ""
    svg.append(f'<text x="{x:.0f}" y="{y:.0f}" font-family="Georgia, serif" font-size="{size}" '
               f'font-weight="{weight}" text-anchor="{anchor}" fill="{fill}" opacity="{op}"{st}>{s}</text>')

def line(x1, y1, x2, y2, stroke=RAIL, w=1.4, dash=None, op=1.0):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    svg.append(f'<line x1="{x1:.0f}" y1="{y1:.0f}" x2="{x2:.0f}" y2="{y2:.0f}" '
               f'stroke="{stroke}" stroke-width="{w}"{d} opacity="{op}"/>')

def gap_glyph(gx, cy, col):
    """open-contact break:  —⊣ ⊢—  (current cannot pass)"""
    line(gx - 7, cy - 7, gx - 7, cy + 7, col, 1.6)
    line(gx + 7, cy - 7, gx + 7, cy + 7, col, 1.6)

def leaf(xL, cy, w, label, state):
    """state: 'live' | 'inert' | 'dead'. Returns (in_port, out_port). Boxes stay clean."""
    h = 38; y = cy - h / 2
    if state == "dead":
        rect(xL, y, w, h, DEAD, "#f6f7f8", dash="5 4", op=0.9)
        text(xL + w / 2, cy + 5, label, fill=DEAD, op=0.95, style="italic")
        text(xL + w / 2, y - 9, "otiose — always open", size=11, fill=DEAD, style="italic")
    else:
        col = GREEN if state == "live" else GREY
        rect(xL, y, w, h, col)
        text(xL + w / 2, cy + 5, label, fill=INK)
    return (xL, cy), (xL + w, cy)

def series(stations, y, x0, gap=46):
    """stations: list of (w, label, state). Draw left→right, connect. Return entry/exit x."""
    x = x0; ports = []
    for (w, label, state) in stations:
        pin, pout = leaf(x, y, w, label, state)
        ports.append((pin, pout))
        x = pout[0] + gap
    for i in range(len(ports) - 1):
        line(ports[i][1][0], y, ports[i + 1][0][0], y)
    return ports

def parallel_group(xL, cy, w, rungs, gap=58):
    """rungs: list of (label, state). Vertical OR group. Returns (in_port, out_port)."""
    n = len(rungs); span = (n - 1) * gap
    ys = [cy - span / 2 + i * gap for i in range(n)]
    busL, busR = xL - 20, xL + w + 20
    outs = []
    for y, (label, state) in zip(ys, rungs):
        pin, pout = leaf(xL, y, w, label, state)
        col = DEAD if state == "dead" else (GREEN if state == "live" else GREY)
        dash = "5 4" if state == "dead" else None
        op = 0.9 if state == "dead" else 1.0
        if state == "dead":
            mid = (busL + pin[0]) / 2
            line(busL, y, mid - 7, y, col, 1.4, dash, op)
            gap_glyph(mid, y, col)                              # break: no current can pass
            line(mid + 7, y, pin[0], y, col, 1.4, dash, op)
        else:
            line(busL, y, pin[0], y, col, 1.4, dash, op)        # left bus stub
        line(pout[0], y, busR, y, col, 1.4, dash, op)           # right bus stub
        outs.append(state)
    # buses only span the LIVE rungs' extent; draw full bus in rail ink
    line(busL, ys[0], busL, ys[-1])
    line(busR, ys[0], busR, ys[-1])
    return (busL, cy), (busR, cy)

def panel(py, title, conceal_state):
    cy = py + 175
    text(40, py + 34, title, size=18, anchor="start", weight="700")
    # Station 1: deception = by-deceiving OR dishonest-concealment  (parallel)
    dec_x, dec_w = 70, 190
    dpin, dpout = parallel_group(dec_x, cy, dec_w,
        [("by deceiving", "live"), ("dishonest concealment", conceal_state)], gap=96)
    text(dec_x + dec_w / 2, cy - 78, "“there is a deception”  (Expl. 1)", size=12, fill="#555", style="italic")
    # Stations 2-4: AND intentionally AND causes-harm AND (harm group)
    s2x = dpout[0] + 46
    ports = series([(150, "intentionally", "live"), (120, "causes harm", "live")], cy, s2x)
    line(dpout[0], cy, ports[0][0][0], cy)                       # deception → intentionally
    # Station 4: harm group
    hg_x = ports[-1][1][0] + 64
    hpin, hpout = parallel_group(hg_x, cy, 120,
        [("body", "live"), ("mind", "live"), ("reputation", "live"), ("property", "live")])
    line(ports[-1][1][0], cy, hpin[0], cy)                       # causes-harm → harm group
    text(hg_x + 60, cy - 130, "harm to…", size=12, fill="#555", style="italic")
    # power rails in/out
    line(40, cy, dpin[0], cy)
    line(hpout[0], cy, W - 40, cy)
    svg.append(f'<circle cx="44" cy="{cy}" r="3.5" fill="{RAIL}"/>')
    svg.append(f'<circle cx="{W-44}" cy="{cy}" r="3.5" fill="{RAIL}"/>')

H = PANEL_H * 2 + 70
svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
svg.append(f'<rect width="{W}" height="{H}" fill="#ffffff"/>')
text(W / 2, 34, "Penal Code s 415, second limb (no property) — surplusage as a dead rung",
     size=16, weight="700")
panel(60, "The court’s reading  (Fourth Interpretation)", "live")
line(40, PANEL_H + 60, W - 40, PANEL_H + 60, "#e2e4e7", 1)
panel(PANEL_H + 60, "The applicants’ reading  (Second Interpretation)", "dead")
text(W / 2, H - 20,
     "The “dishonest concealment” rung can never carry current ⇒ a don’t-care ⇒ "
     "the minimiser deletes it ⇒ Explanation 1 is otiose.  (GD [30], [32])",
     size=12.5, fill="#444", style="italic")
svg.append("</svg>")

open("cheating-415-ladder.svg", "w").write("\n".join(svg))
print("wrote cheating-415-ladder.svg")
