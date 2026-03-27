#!/usr/bin/env python3

import pathlib
import sys
import zipfile


def member_names(archive: pathlib.Path) -> list[str]:
    with zipfile.ZipFile(archive) as zf:
        return sorted(name for name in zf.namelist() if not name.endswith("/"))


def member_bytes(archive: pathlib.Path, member: str) -> bytes:
    with zipfile.ZipFile(archive) as zf:
        return zf.read(member)


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: aabdiff.py <first.aab> <second.aab>", file=sys.stderr)
        return 2

    first_archive = pathlib.Path(sys.argv[1]).resolve()
    second_archive = pathlib.Path(sys.argv[2]).resolve()

    if not first_archive.is_file():
        print(f"Missing AAB archive: {first_archive}", file=sys.stderr)
        return 2
    if not second_archive.is_file():
        print(f"Missing AAB archive: {second_archive}", file=sys.stderr)
        return 2

    first_members = member_names(first_archive)
    second_members = member_names(second_archive)

    if first_members != second_members:
        print("AAB member sets differ", file=sys.stderr)
        print(f"First:  {first_members}", file=sys.stderr)
        print(f"Second: {second_members}", file=sys.stderr)
        return 1

    for member in first_members:
        left = member_bytes(first_archive, member)
        right = member_bytes(second_archive, member)
        if left != right:
            print(f"AAB member differs: {member}", file=sys.stderr)
            return 1

    print("AABs are identical at the member-payload level.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
