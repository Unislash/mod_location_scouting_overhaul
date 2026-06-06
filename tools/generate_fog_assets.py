#!/usr/bin/env python3

import math
import struct
import zlib
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
GFX_DIR = REPO_ROOT / "src/gfx"
BRUSH_DIR = REPO_ROOT / "src/brushes"
PRELOAD_PATH = REPO_ROOT / "src/preload/on_running.txt"
BASE_PNG_PATH = GFX_DIR / "mod_location_scouting.png"
BASE_BRUSH_PATH = BRUSH_DIR / "mod_location_scouting.brush"

CONTENT_WIDTH = 240
CONTENT_HEIGHT = 120
BLEED = 6
CELL_WIDTH = CONTENT_WIDTH + BLEED * 2
CELL_HEIGHT = CONTENT_HEIGHT + BLEED * 2
ATLAS_COLUMNS = 8

HEX_VERTICES = [
    (60.0, 0.0),
    (180.0, 0.0),
    (239.0, 60.0),
    (180.0, 119.0),
    (60.0, 119.0),
    (0.0, 60.0),
]

HEX_EDGES = []
for i in range(len(HEX_VERTICES)):
    ax, ay = HEX_VERTICES[i]
    bx, by = HEX_VERTICES[(i + 1) % len(HEX_VERTICES)]
    ex = bx - ax
    ey = by - ay
    length = math.hypot(ex, ey)
    HEX_EDGES.append(
        {
            "ax": ax,
            "ay": ay,
            "tx": ex / length,
            "ty": ey / length,
            "length": length,
        }
    )

EDGE_PAIR_INDEX = [0, 1, 2, 0, 1, 2]
EDGE_PROFILE_MIRROR = [False, False, False, True, True, True]
EDGE_PROFILE_PARAMS = [
    {
        "warp_a": 0.19,
        "warp_b": 0.08,
        "lobes": [(0.18, 0.11, 7.0), (0.47, 0.16, -5.5), (0.78, 0.12, 5.0)],
    },
    {
        "warp_a": -0.16,
        "warp_b": 0.10,
        "lobes": [(0.23, 0.13, -4.5), (0.58, 0.18, 7.5), (0.83, 0.10, -3.5)],
    },
    {
        "warp_a": 0.12,
        "warp_b": -0.11,
        "lobes": [(0.14, 0.09, 4.0), (0.39, 0.14, 6.0), (0.71, 0.17, -6.5)],
    },
]

SHARED_TEXTURE_HASH = 0xBF795EF4D3FE85C5
RECORD_U32S = [240, 120, 0, 100, 0, 0, 0x403, 0, 0, 0]
RECORD_EXTRA_U32 = 0
RECORD_SCALE = 2.0
RECORD_EXTRA_U16 = 1
BOUNDS = (-120.0, 120.0, -60.0, 60.0)
HEADER_BYTES = bytes([1, 0, 1, 1, 1, 0, 0, 0, 1, 0, 0, 0])
SPRITE_FLAG = 0x6400
SPRITE_TAIL_BYTES = bytes([0, 0, 0, 0, 0])
SPRITE_MID_BYTES = bytes([3, 4, 0, 0])
SPRITE_TRAILER_BYTES = bytes([0, 0, 0])
BRUSH_VERSION = 17
BRUSH_I0 = 1000

# Outside-of-hex seam support tuning.
#
# These arrays are indexed by the hex edge id chosen as `outer_edge` below,
# i.e. whichever edge is currently the "nearest way back into the hex" for
# a pixel that lies slightly OUTSIDE the ideal mathematical hex boundary.
#
# Edge index -> geometric side in screen space:
#   0 = top horizontal edge
#       from HEX_VERTICES[0] (60, 0) to HEX_VERTICES[1] (180, 0)
#   1 = upper-right slanted edge
#       from HEX_VERTICES[1] (180, 0) to HEX_VERTICES[2] (239, 60)
#   2 = lower-right slanted edge
#       from HEX_VERTICES[2] (239, 60) to HEX_VERTICES[3] (180, 119)
#   3 = bottom horizontal edge
#       from HEX_VERTICES[3] (180, 119) to HEX_VERTICES[4] (60, 119)
#   4 = lower-left slanted edge
#       from HEX_VERTICES[4] (60, 119) to HEX_VERTICES[5] (0, 60)
#   5 = upper-left slanted edge
#       from HEX_VERTICES[5] (0, 60) to HEX_VERTICES[0] (60, 0)
#
# Why these exist:
#   At many zoom levels the renderer samples a little outside the exact sprite
#   boundary. If the fog abruptly ends exactly at the mathematical hex edge,
#   tiny light cracks can appear between neighboring tiles. These constants
#   tell the generator to keep drawing a faint "support skirt" slightly
#   OUTSIDE the hex so those cracks are filled in.
#
# What EDGE_OUTER_WIDTH does:
#   Width, in pixels, of that outside support region for each edge.
#   Example: EDGE_OUTER_WIDTH[0] = 2.4 means the top edge gets up to 2.4 px of
#   extra support outside the ideal hex boundary before alpha falls to 0.
#
# What EDGE_OUTER_ALPHA does:
#   Strength of that outside support, expressed as a fraction of `base_alpha`.
#   Example: EDGE_OUTER_ALPHA[0] = 0.72 means the support floor can be as high
#   as 72% of the pixel's pre-frontier-fade alpha right on the top edge.
#
# Why the values are asymmetric:
#   The engine does not sample all six sides equally once the overlay is drawn
#   onto the world map and then zoomed. In practice:
#   - top / bottom edges often need MORE outside coverage to avoid bright gaps
#   - slanted side edges often need LESS outside coverage to avoid a dark
#     doubled-up zig-zag where neighboring tiles overlap
#   That is why edges 0 and 3 are wider/stronger than 1, 2, 4, and 5.
#
# Note that these only matter for pixels with `min_dist < 0.0`, meaning pixels
# already outside the ideal hex. They do NOT directly change the frontier fade
# inside the hex; they only control the anti-crack support skirt outside it.
EDGE_OUTER_WIDTH = [2.8, 1.35, 1.35, 2.4, 1.35, 1.35]
EDGE_OUTER_ALPHA = [0.72, 0.34, 0.34, 0.64, 0.34, 0.34]


def sdbm_hash(text: str) -> int:
    h = 0
    for b in text.encode("ascii"):
        h = (b + (h << 6) + (h << 16) - h) & 0xFFFFFFFFFFFFFFFF
    return h


def hash_u32(value: int) -> int:
    value &= 0xFFFFFFFF
    value = ((value >> 16) ^ value) * 0x45D9F3B
    value &= 0xFFFFFFFF
    value = ((value >> 16) ^ value) * 0x45D9F3B
    value &= 0xFFFFFFFF
    return ((value >> 16) ^ value) & 0xFFFFFFFF


def rand01(ix: int, iy: int, seed: int) -> float:
    value = hash_u32(ix * 73856093 ^ iy * 19349663 ^ seed * 83492791)
    return value / 0xFFFFFFFF


def smoothstep(t: float) -> float:
    if t <= 0.0:
        return 0.0
    if t >= 1.0:
        return 1.0
    return t * t * (3.0 - 2.0 * t)


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def value_noise(x: float, y: float, seed: int, scale: float) -> float:
    gx = math.floor(x / scale)
    gy = math.floor(y / scale)
    tx = (x / scale) - gx
    ty = (y / scale) - gy

    v00 = rand01(gx, gy, seed)
    v10 = rand01(gx + 1, gy, seed)
    v01 = rand01(gx, gy + 1, seed)
    v11 = rand01(gx + 1, gy + 1, seed)

    sx = smoothstep(tx)
    sy = smoothstep(ty)
    nx0 = lerp(v00, v10, sx)
    nx1 = lerp(v01, v11, sx)
    return lerp(nx0, nx1, sy)


def edge_distances(x: float, y: float):
    result = []
    count = len(HEX_VERTICES)
    for i in range(count):
        ax, ay = HEX_VERTICES[i]
        bx, by = HEX_VERTICES[(i + 1) % count]
        ex = bx - ax
        ey = by - ay
        length = math.hypot(ex, ey)
        cross = ex * (y - ay) - ey * (x - ax)
        result.append(cross / length)
    return result


def point_distance(ax: float, ay: float, bx: float, by: float) -> float:
    return math.hypot(ax - bx, ay - by)


def edge_profile_jitter(edge: int, along: float) -> float:
    edge_meta = HEX_EDGES[edge]
    t = max(0.0, min(1.0, along / edge_meta["length"]))
    if EDGE_PROFILE_MIRROR[edge]:
        t = 1.0 - t
    u = min(t, 1.0 - t)
    pair = EDGE_PAIR_INDEX[edge]
    params = EDGE_PROFILE_PARAMS[pair]

    # Force edge-specific displacement to die out at vertices so neighboring
    # tiles converge on the same corner location instead of nearly matching.
    end_falloff = smoothstep(min(1.0, u / 0.34))

    warp = (value_noise(t * 180.0, 17.0 + pair * 31.0, 400 + pair * 97, 52.0) - 0.5) * params["warp_a"]
    warp += (value_noise(t * 96.0, 53.0 + pair * 19.0, 700 + pair * 131, 34.0) - 0.5) * params["warp_b"]
    warped_t = max(0.0, min(1.0, t + warp))

    wave = (value_noise(warped_t * 220.0, 23.0 + pair * 41.0, 1000 + pair * 73, 64.0) - 0.5) * 7.0
    wave += (value_noise(warped_t * 120.0, 61.0 + pair * 29.0, 1300 + pair * 101, 40.0) - 0.5) * 3.5

    for center, width, amplitude in params["lobes"]:
        lobe_t = (warped_t - center) / width
        wave += math.exp(-(lobe_t * lobe_t)) * amplitude

    return wave * end_falloff


def get_variant_count(mask: int) -> int:
    if mask == 0:
        # The engine intermittently fails to render alternate fully-fogged
        # variants in-world, so only generate the stable mask-00 brush.
        return 1
    if mask.bit_count() == 1:
        return 2
    return 1


def iter_entries():
    for mask in range(64):
        for variant in range(get_variant_count(mask)):
            yield {
                "mask": mask,
                "variant": variant,
                "name": f"world_tile_fog_{mask:02d}_v{variant}",
                "png_name": f"world_tile_fog_{mask:02d}_v{variant}.png",
            }


def render_entry(mask: int, variant: int):
    rows = []
    seed = mask * 97 + variant * 1009 + 17

    for y in range(CONTENT_HEIGHT):
        row = bytearray(CONTENT_WIDTH * 4)
        for x in range(CONTENT_WIDTH):
            px = x + 0.5
            py = y + 0.5
            dists = edge_distances(px, py)
            min_dist = min(dists)
            outer_edge = 0
            for i in range(1, len(dists)):
                if dists[i] < dists[outer_edge]:
                    outer_edge = i

            # `outer_edge` is the edge whose signed distance is most negative,
            # i.e. the closest edge for a point that has wandered outside the
            # ideal hex. We use that edge's width/alpha entries to decide how
            # much anti-crack support to keep around this pixel.
            outer_width = EDGE_OUTER_WIDTH[outer_edge]
            if min_dist < -outer_width:
                # This pixel is farther outside the hex than the support skirt
                # for the nearest edge allows, so it contributes nothing.
                continue

            alpha = 76.0
            alpha *= 0.97 + 0.06 * value_noise(px + seed * 0.07, py + seed * 0.05, seed, 90.0)
            alpha *= 0.98 + 0.04 * value_noise(px + 37.0, py + 19.0, seed + 41, 56.0)
            base_alpha = alpha

            for edge in range(6):
                if (mask & (1 << edge)) == 0:
                    continue

                edge_meta = HEX_EDGES[edge]
                along = (px - edge_meta["ax"]) * edge_meta["tx"] + (py - edge_meta["ay"]) * edge_meta["ty"]
                edge_t = max(0.0, min(1.0, along / edge_meta["length"]))
                edge_u = min(edge_t, 1.0 - edge_t)
                corner_blend = smoothstep(min(1.0, edge_u / 0.30))
                boundary_jitter = edge_profile_jitter(edge, along)
                fade_width = 24.0 + 14.0 * value_noise(px + edge * 13.0, py + edge * 29.0, 900 + edge * 131, 46.0)
                fade_width = lerp(30.0, fade_width, corner_blend)
                t = (dists[edge] + boundary_jitter) / fade_width
                alpha *= smoothstep(t)

            for edge in range(6):
                next_edge = (edge + 1) % 6
                if (mask & (1 << edge)) == 0 or (mask & (1 << next_edge)) == 0:
                    continue

                vx, vy = HEX_VERTICES[(edge + 1) % 6]
                corner_dist = point_distance(px, py, vx, vy)
                corner_radius = 38.0
                corner_radius += 7.0 * value_noise(corner_dist * 0.45, 40.0 + edge * 23.0, 1200 + edge * 257, 26.0)
                corner_radius += 4.0 * value_noise(px + vx * 0.35, py + vy * 0.35, 1500 + edge * 311, 44.0)
                alpha *= smoothstep(corner_dist / corner_radius)

            for edge in range(6):
                if (mask & (1 << edge)) == 0:
                    continue

                prev_edge = (edge + 5) % 6
                next_edge = (edge + 1) % 6
                edge_band = 1.0 - smoothstep(min(1.0, dists[edge] / 24.0))

                if (mask & (1 << prev_edge)) == 0:
                    vx, vy = HEX_VERTICES[edge]
                    endpoint_dist = point_distance(px, py, vx, vy)
                    endpoint_cap = 1.0 - smoothstep(min(1.0, endpoint_dist / 24.0))
                    alpha = max(alpha, base_alpha * 0.42 * endpoint_cap * edge_band)

                if (mask & (1 << next_edge)) == 0:
                    vx, vy = HEX_VERTICES[next_edge]
                    endpoint_dist = point_distance(px, py, vx, vy)
                    endpoint_cap = 1.0 - smoothstep(min(1.0, endpoint_dist / 24.0))
                    alpha = max(alpha, base_alpha * 0.42 * endpoint_cap * edge_band)

            if min_dist < 0.0:
                # Outside the ideal hex: fade the support skirt from full
                # strength at the boundary (min_dist = 0) down to 0 at
                # min_dist = -outer_width.
                outer_fade = smoothstep((min_dist + outer_width) / outer_width)

                # Two competing alpha values exist here:
                # 1. `alpha * outer_fade`
                #    The naturally-computed fog alpha, faded out as we move
                #    beyond the hex boundary.
                # 2. `base_alpha * EDGE_OUTER_ALPHA[outer_edge] * outer_fade`
                #    A minimum support floor whose only job is to stop bright
                #    seams from showing through.
                #
                # We take the max so the seam-support floor can "prop up" the
                # alpha if the ordinary fog computation falls too low near the
                # border. A larger EDGE_OUTER_ALPHA makes dark overlaps more
                # likely; a smaller one makes bright cracks more likely.
                alpha = max(alpha * outer_fade, base_alpha * EDGE_OUTER_ALPHA[outer_edge] * outer_fade)

            # Keep the interior soft even when all six sides are open.
            alpha = max(0.0, min(122.0, alpha))
            if alpha < 1.0:
                continue

            i = x * 4
            row[i] = 0
            row[i + 1] = 0
            row[i + 2] = 0
            row[i + 3] = int(alpha)
        rows.append(row)

    return rows


def next_power_of_two(value: int) -> int:
    result = 1
    while result < value:
        result <<= 1
    return result


def build_atlas(entries):
    rows = (len(entries) + ATLAS_COLUMNS - 1) // ATLAS_COLUMNS
    atlas_width = next_power_of_two(ATLAS_COLUMNS * CELL_WIDTH)
    atlas_height = next_power_of_two(rows * CELL_HEIGHT)
    atlas = [bytearray(atlas_width * 4) for _ in range(atlas_height)]

    for index, entry in enumerate(entries):
        sprite = render_entry(entry["mask"], entry["variant"])
        col = index % ATLAS_COLUMNS
        row = index // ATLAS_COLUMNS
        origin_x = col * CELL_WIDTH + BLEED
        origin_y = row * CELL_HEIGHT + BLEED

        # Match Battle Brothers' bbrusher packer, which flips source frames
        # vertically when copying them into the atlas. Extend a generous bleed
        # border with clamped edge pixels so zoom/minification never samples
        # transparent neighbor texels and creates white seams.
        for local_y in range(-BLEED, CONTENT_HEIGHT + BLEED):
            src_y = min(CONTENT_HEIGHT - 1, max(0, CONTENT_HEIGHT - 1 - local_y))
            src = sprite[src_y]
            dst = atlas[origin_y + local_y]

            for local_x in range(-BLEED, CONTENT_WIDTH + BLEED):
                src_x = min(CONTENT_WIDTH - 1, max(0, local_x))
                dst_index = (origin_x + local_x) * 4
                src_index = src_x * 4
                dst[dst_index : dst_index + 4] = src[src_index : src_index + 4]

        entry["frame_name"] = entry["png_name"]
        entry["x1"] = origin_x
        entry["x2"] = origin_x + CONTENT_WIDTH
        entry["y1"] = origin_y
        entry["y2"] = origin_y + CONTENT_HEIGHT

    return atlas, atlas_width, atlas_height


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def write_png(path: Path, rows, width: int):
    height = len(rows)
    raw = bytearray()
    for row in rows:
        raw.append(0)
        raw.extend(row)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    data = zlib.compress(bytes(raw), level=9)
    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png.extend(png_chunk(b"IHDR", ihdr))
    png.extend(png_chunk(b"sRGB", b"\x00"))
    png.extend(png_chunk(b"gAMA", struct.pack(">I", 45455)))
    png.extend(png_chunk(b"IDAT", data))
    png.extend(png_chunk(b"IEND", b""))
    path.write_bytes(png)


def write_string(buffer: bytearray, text: str):
    encoded = text.encode("utf-8")
    buffer.extend(struct.pack("<H", len(encoded)))
    buffer.extend(encoded)


def build_brush(path: Path, texture_path: str, entries, atlas_width: int, atlas_height: int):
    data = bytearray()
    data.extend(struct.pack("<IH", 0xBAADFAAD, BRUSH_VERSION))
    write_string(data, texture_path)
    data.extend(struct.pack("<HH", atlas_width, atlas_height))
    data.extend(HEADER_BYTES)
    data.extend(struct.pack("<I", len(entries)))
    data.extend(b"\x00\x00")
    data.extend(struct.pack("<I", BRUSH_I0))

    for entry in entries:
        data.extend(struct.pack("<Q", sdbm_hash(entry["name"])))
        write_string(data, entry["name"])
        data.extend(struct.pack("<Q", SHARED_TEXTURE_HASH))
        data.extend(struct.pack("<iihhI", CONTENT_WIDTH, CONTENT_HEIGHT, 0, 0, SPRITE_FLAG))
        data.extend(SPRITE_TAIL_BYTES)
        data.extend(struct.pack("<f", 0.0))
        data.extend(SPRITE_MID_BYTES)
        data.extend(struct.pack("<ffIf", 0.0, 0.0, 0, 2.0))
        data.extend(struct.pack("<H", 1))
        write_string(data, entry["frame_name"])
        data.extend(
            struct.pack(
                "<4f",
                entry["x1"] / atlas_width,
                entry["x2"] / atlas_width,
                entry["y1"] / atlas_height,
                entry["y2"] / atlas_height,
            )
        )
        data.extend(struct.pack("<4f", *BOUNDS))
        data.extend(SPRITE_TRAILER_BYTES)

    path.write_bytes(data)


def cleanup_generated_files():
    for folder, prefix, suffix in [
        (GFX_DIR, "mod_location_scouting_", ".png"),
        (BRUSH_DIR, "mod_location_scouting_", ".brush"),
    ]:
        for child in folder.iterdir():
            if child.name.startswith(prefix) and child.name.endswith(suffix):
                child.unlink()


def write_preload():
    PRELOAD_PATH.write_text("gfx/mod_location_scouting.png\n", encoding="ascii")


def main():
    cleanup_generated_files()
    entries = list(iter_entries())
    atlas, atlas_width, atlas_height = build_atlas(entries)
    write_png(BASE_PNG_PATH, atlas, atlas_width)
    build_brush(BASE_BRUSH_PATH, "gfx/mod_location_scouting.png", entries, atlas_width, atlas_height)
    write_preload()
    print(f"Generated {len(entries)} fog brushes in {BASE_PNG_PATH.name} ({atlas_width}x{atlas_height})")


if __name__ == "__main__":
    main()
