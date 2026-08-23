"""Emit a V-shaped laurel wreath as inline SVG (two mirrored branches).

Shape target: shallow open wreath, wider than tall (~2.2:1), leaves on both
sides of each stem, stems crossing at the bottom centre.
"""
import math

W, H = 200.0, 92.0

# Right-hand branch stem: starts just right of centre-bottom, sweeps up/right.
P0 = (100.0, 84.0)
P1 = (140.0, 82.0)
P2 = (180.0, 62.0)
P3 = (196.0, 12.0)


def bez(t):
    mt = 1 - t
    x = (mt ** 3) * P0[0] + 3 * (mt ** 2) * t * P1[0] + 3 * mt * (t ** 2) * P2[0] + (t ** 3) * P3[0]
    y = (mt ** 3) * P0[1] + 3 * (mt ** 2) * t * P1[1] + 3 * mt * (t ** 2) * P2[1] + (t ** 3) * P3[1]
    return x, y


def tangent(t):
    mt = 1 - t
    dx = 3 * (mt ** 2) * (P1[0] - P0[0]) + 6 * mt * t * (P2[0] - P1[0]) + 3 * (t ** 2) * (P3[0] - P2[0])
    dy = 3 * (mt ** 2) * (P1[1] - P0[1]) + 6 * mt * t * (P2[1] - P1[1]) + 3 * (t ** 2) * (P3[1] - P2[1])
    return math.degrees(math.atan2(dy, dx))


def leaf(length):
    """Pointed leaf lying along +x, origin at its stem end."""
    w = length * 0.32
    return (f"M0 0 C {length * 0.26:.1f} {-w:.1f} {length * 0.74:.1f} {-w:.1f} {length:.1f} 0 "
            f"C {length * 0.74:.1f} {w:.1f} {length * 0.26:.1f} {w:.1f} 0 0 Z")


def branch():
    out = []
    # stem, running past the centre into a crossing tail
    out.append(f'<path d="M74 92 C 86 88 94 87 {P0[0]} {P0[1]} C {P1[0]} {P1[1]} '
               f'{P2[0]} {P2[1]} {P3[0]} {P3[1]}" '
               'fill="none" stroke="#0F0F0F" stroke-width="1.9" stroke-linecap="round"/>')

    steps = 11
    for i in range(steps):
        u = i / (steps - 1)
        t = 0.13 + (0.97 - 0.13) * u
        x, y = bez(t)
        ang = tangent(t)
        # leaves are biggest mid-branch, smaller at both ends
        bell = math.sin(math.pi * (0.22 + 0.78 * u))
        ln_out = 11.5 + 7.2 * bell
        out.append(f'<path d="{leaf(ln_out)}" fill="#0F0F0F" '
                   f'transform="translate({x:.1f} {y:.1f}) rotate({ang - 56:.1f})"/>')
        # inner row sits between the outer leaves, half a step along
        if i % 2 == 0 and i < steps - 1:
            t2 = t + (0.97 - 0.13) / (steps - 1) * 0.5
            x2, y2 = bez(t2)
            ang2 = tangent(t2)
            out.append(f'<path d="{leaf(ln_out * 0.62)}" fill="#0F0F0F" '
                       f'transform="translate({x2:.1f} {y2:.1f}) rotate({ang2 + 68:.1f})"/>')
    return "".join(out)


right = branch()
svg = (f'<svg viewBox="0 0 {W:.0f} {H:.0f}" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">'
       f'<g>{right}</g>'
       f'<g transform="translate({W:.0f} 0) scale(-1 1)">{right}</g>'
       '</svg>')
print(svg)
