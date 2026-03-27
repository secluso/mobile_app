#!/usr/bin/env python3

import pathlib
import subprocess
import sys
import tempfile
import zipfile


def apk_paths(apks_archive: pathlib.Path) -> list[str]:
    with zipfile.ZipFile(apks_archive) as zf:
        return sorted(
            name
            for name in zf.namelist()
            if name.endswith(".apk") and not name.endswith("/")
        )


def extract_member(
    apks_archive: pathlib.Path,
    member: str,
    destination: pathlib.Path,
) -> pathlib.Path:
    with zipfile.ZipFile(apks_archive) as zf:
        zf.extract(member, destination)
    return destination / member


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: apksdiff.py <first.apks> <second.apks>", file=sys.stderr)
        return 2

    first_archive = pathlib.Path(sys.argv[1]).resolve()
    second_archive = pathlib.Path(sys.argv[2]).resolve()
    apkdiff = pathlib.Path(__file__).resolve().with_name("apkdiff.py")

    if not first_archive.is_file():
        print(f"Missing APK set archive: {first_archive}", file=sys.stderr)
        return 2
    if not second_archive.is_file():
        print(f"Missing APK set archive: {second_archive}", file=sys.stderr)
        return 2

    first_apks = apk_paths(first_archive)
    second_apks = apk_paths(second_archive)

    if first_apks != second_apks:
        print("APK set members differ", file=sys.stderr)
        print(f"First:  {first_apks}", file=sys.stderr)
        print(f"Second: {second_apks}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="secluso-apksdiff-") as tmpdir:
        tmpdir_path = pathlib.Path(tmpdir)
        for member in first_apks:
            left = extract_member(first_archive, member, tmpdir_path / "left")
            right = extract_member(second_archive, member, tmpdir_path / "right")
            result = subprocess.run(
                [sys.executable, str(apkdiff), str(left), str(right)],
                check=False,
            )
            if result.returncode != 0:
                print(f"APK differs: {member}", file=sys.stderr)
                return result.returncode

    print("APK sets are equivalent (ignoring signing metadata).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
