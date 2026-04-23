#!/usr/bin/env python3
"""
coord_math.py — ThatThingOS coordinate / grid math toolbox
Covers: Minecraft overworld ↔ nether conversions, circle/spiral generation,
        chunk math, distance, bearing, and grid region splitting.
Usage:  python3 coord_math.py --help
"""
import argparse
import math
import sys

C = "\033[36m"; Y = "\033[33m"; G = "\033[32m"; W = "\033[0m"; B = "\033[1m"

BANNER = f"{C}{B}[ ThatThingOS // COORD_MATH ]{W}\n"

# ─────────────────────────────────────────────────────────────────────
def ow_to_nether(x, z):
    return x // 8, z // 8

def nether_to_ow(x, z):
    return x * 8, z * 8

def chunk_of(x, z):
    return x >> 4, z >> 4

def region_of(x, z):
    cx, cz = chunk_of(x, z)
    return cx >> 5, cz >> 5

def distance(x1, z1, x2, z2):
    return math.sqrt((x2 - x1)**2 + (z2 - z1)**2)

def bearing(x1, z1, x2, z2):
    """Minecraft bearing: 0=south, 90=west, 180=north, 270=east"""
    dx, dz = x2 - x1, z2 - z1
    ang = math.degrees(math.atan2(-dx, dz)) % 360
    dirs = ["S","SW","W","NW","N","NE","E","SE"]
    idx  = int((ang + 22.5) / 45) % 8
    return ang, dirs[idx]

def circle_outline(cx, cz, radius, step=1):
    """Integer-block circle outline (XZ plane)"""
    points = set()
    for deg in range(0, 360, max(1, step)):
        rad = math.radians(deg)
        x = round(cx + radius * math.sin(rad))
        z = round(cz + radius * math.cos(rad))
        points.add((x, z))
    return sorted(points)

def spiral(cx, cz, rings):
    """Generates chunk spiral coords from center outward (chunk units)"""
    results = [(cx, cz)]
    x, z = 0, 0
    dx, dz = 0, -1
    size = 2 * rings + 1
    for _ in range(size * size):
        if (-rings <= x <= rings) and (-rings <= z <= rings):
            results.append((cx + x, cz + z))
        if x == z or (x < 0 and x == -z) or (x > 0 and x == 1 - z):
            dx, dz = -dz, dx
        x, z = x + dx, z + dz
    return results[1:]   # exclude center repeat

def subdivide_region(x1, z1, x2, z2, cols, rows):
    """Split a bounding box into a cols×rows grid, return list of (x1,z1,x2,z2)"""
    w = (x2 - x1) / cols
    h = (z2 - z1) / rows
    grid = []
    for r in range(rows):
        for c in range(cols):
            grid.append((
                round(x1 + c * w), round(z1 + r * h),
                round(x1 + (c+1) * w), round(z1 + (r+1) * h)
            ))
    return grid

# ─────────────────────────────────────────────────────────────────────
def main():
    print(BANNER)
    parser = argparse.ArgumentParser(description="Coordinate math toolbox")
    sub = parser.add_subparsers(dest="cmd")

    # ow2n
    p = sub.add_parser("ow2n", help="Overworld → Nether")
    p.add_argument("x", type=int); p.add_argument("z", type=int)

    # n2ow
    p = sub.add_parser("n2ow", help="Nether → Overworld")
    p.add_argument("x", type=int); p.add_argument("z", type=int)

    # chunk
    p = sub.add_parser("chunk", help="Block → Chunk")
    p.add_argument("x", type=int); p.add_argument("z", type=int)

    # region
    p = sub.add_parser("region", help="Block → Region file")
    p.add_argument("x", type=int); p.add_argument("z", type=int)

    # dist
    p = sub.add_parser("dist", help="Distance + bearing between two points")
    p.add_argument("x1", type=int); p.add_argument("z1", type=int)
    p.add_argument("x2", type=int); p.add_argument("z2", type=int)

    # circle
    p = sub.add_parser("circle", help="Circle outline coords")
    p.add_argument("cx", type=int); p.add_argument("cz", type=int)
    p.add_argument("radius", type=int)

    # spiral
    p = sub.add_parser("spiral", help="Chunk spiral from center")
    p.add_argument("cx", type=int); p.add_argument("cz", type=int)
    p.add_argument("rings", type=int)

    # grid
    p = sub.add_parser("grid", help="Subdivide region into grid")
    p.add_argument("x1",type=int); p.add_argument("z1",type=int)
    p.add_argument("x2",type=int); p.add_argument("z2",type=int)
    p.add_argument("cols",type=int); p.add_argument("rows",type=int)

    args = parser.parse_args()
    if not args.cmd:
        parser.print_help(); sys.exit(0)

    if args.cmd == "ow2n":
        nx, nz = ow_to_nether(args.x, args.z)
        print(f"{G}OW ({args.x},{args.z}) → Nether ({nx},{nz}){W}")

    elif args.cmd == "n2ow":
        ox, oz = nether_to_ow(args.x, args.z)
        print(f"{G}Nether ({args.x},{args.z}) → OW ({ox},{oz}){W}")

    elif args.cmd == "chunk":
        cx, cz = chunk_of(args.x, args.z)
        print(f"{G}Block ({args.x},{args.z}) → Chunk [{cx},{cz}]{W}")

    elif args.cmd == "region":
        rx, rz = region_of(args.x, args.z)
        print(f"{G}Block ({args.x},{args.z}) → r.{rx}.{rz}.mca{W}")

    elif args.cmd == "dist":
        d  = distance(args.x1, args.z1, args.x2, args.z2)
        ang, dir_ = bearing(args.x1, args.z1, args.x2, args.z2)
        print(f"{G}Distance: {d:.1f} blocks  |  Bearing: {ang:.1f}° ({dir_}){W}")

    elif args.cmd == "circle":
        pts = circle_outline(args.cx, args.cz, args.radius)
        print(f"{Y}Circle r={args.radius} center=({args.cx},{args.cz}): {len(pts)} blocks{W}")
        for p in pts:
            print(f"  {p[0]},{p[1]}")

    elif args.cmd == "spiral":
        pts = spiral(args.cx, args.cz, args.rings)
        print(f"{Y}Chunk spiral {args.rings} rings from ({args.cx},{args.cz}): {len(pts)} chunks{W}")
        for p in pts[:50]:
            print(f"  chunk {p[0]},{p[1]}  → block {p[0]*16},{p[1]*16}")
        if len(pts) > 50:
            print(f"  ... and {len(pts)-50} more")

    elif args.cmd == "grid":
        cells = subdivide_region(args.x1, args.z1, args.x2, args.z2, args.cols, args.rows)
        print(f"{Y}{args.cols}×{args.rows} grid over ({args.x1},{args.z1})→({args.x2},{args.z2}):{W}")
        for i, (a,b,c,d) in enumerate(cells):
            print(f"  [{i:02d}] ({a},{b}) → ({c},{d})")


if __name__ == "__main__":
    main()
