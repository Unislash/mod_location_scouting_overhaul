#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import argparse
import sys


KEY = b"MSU.mod_location_scouting.LegendaryScoutedIDs.data.4"
MAX_SAFE_STRING_LEN = 65535


def is_printable_ascii(data: bytes) -> bool:
    return all(32 <= b < 127 for b in data)


def find_next_flag_entry(data: bytes, start: int) -> tuple[int, str]:
    """
    Find the next plausible World.Flags entry after the overflowing payload.

    The Battle Brothers tag_collection format stores each entry as:
      U16 key_len
      key bytes
      U8 type
      value bytes

    We search for the next "MSU." key and validate that the two bytes before it
    look like a sane key length and that the following type byte is one of the
    expected tag_collection primitive types.
    """
    pos = start
    while True:
        key_pos = data.find(b"MSU.", pos)
        if key_pos == -1:
            raise ValueError("could not find a plausible next MSU flag entry")

        if key_pos >= 2:
            key_len = int.from_bytes(data[key_pos - 2:key_pos], "little")
            key_end = key_pos + key_len

            if 1 <= key_len <= 255 and key_end < len(data):
                key_bytes = data[key_pos:key_end]
                value_type = data[key_end]
                if (
                    key_bytes.startswith(b"MSU.")
                    and is_printable_ascii(key_bytes)
                    and value_type in (0, 1, 2, 3)
                ):
                    return key_pos - 2, key_bytes.decode("ascii")

        pos = key_pos + 1


def repair_save(path: Path, output_path: Path) -> None:
    data = path.read_bytes()

    key_pos = data.find(KEY)
    if key_pos == -1:
        raise ValueError(f"{KEY.decode()} not found")

    type_pos = key_pos + len(KEY)
    if data[type_pos] != 3:
        raise ValueError("LegendaryScoutedIDs.data.4 is not stored as a string")

    stored_len = int.from_bytes(data[type_pos + 1:type_pos + 3], "little")
    payload_start = type_pos + 3
    next_entry_start, next_key = find_next_flag_entry(data, payload_start)
    actual_len = next_entry_start - payload_start

    if actual_len <= MAX_SAFE_STRING_LEN:
        raise ValueError(
            f"payload is already within range ({actual_len}); no overflow to repair"
        )

    payload = data[payload_start:next_entry_start]
    cut = payload.rfind(b",", 0, MAX_SAFE_STRING_LEN + 1)
    if cut == -1:
        raise ValueError("could not find a comma boundary before the safe limit")

    truncated_payload = payload[:cut]
    new_len = len(truncated_payload)
    assert new_len <= MAX_SAFE_STRING_LEN

    repaired = bytearray()
    repaired += data[:type_pos + 1]
    repaired += new_len.to_bytes(2, "little")
    repaired += truncated_payload
    repaired += data[next_entry_start:]

    output_path.write_bytes(repaired)

    print(f"repaired: {path.name} -> {output_path.name}")
    print(f"stored_len={stored_len} actual_len={actual_len} new_len={new_len}")
    print(f"next_key={next_key}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Repair Battle Brothers saves corrupted by an overflowed "
            "MSU.mod_location_scouting.LegendaryScoutedIDs.data.4 string."
        )
    )
    parser.add_argument("save", nargs="+", help="Path(s) to corrupted save file(s)")
    args = parser.parse_args(argv)

    for raw_path in args.save:
        path = Path(raw_path)
        output_path = path.with_name(path.name + ".repaired")
        repair_save(path, output_path)

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
