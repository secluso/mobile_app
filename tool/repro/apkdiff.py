#!/usr/bin/env python3

# Inspired by Telegram's APK comparison utility and reproducible-build workflow:
# https://core.telegram.org/reproducible-builds

import os
import sys
from zipfile import ZipFile


FILES_TO_IGNORE = {
    "META-INF/MANIFEST.MF",
}

SIGNATURE_SUFFIXES = (
    ".RSA",
    ".SF",
    ".DSA",
    ".EC",
)


def should_ignore(filename):
    if filename in FILES_TO_IGNORE:
        return True

    if not filename.startswith("META-INF/"):
        return False

    leaf_name = os.path.basename(filename)
    return leaf_name.endswith(SIGNATURE_SUFFIXES)


def compare_files(first, second):
    while True:
        first_bytes = first.read(4096)
        second_bytes = second.read(4096)
        if first_bytes != second_bytes:
            return False
        if first_bytes == b"" and second_bytes == b"":
            return True


def compare(first_path, second_path):
    with ZipFile(first_path, "r") as first_zip, ZipFile(second_path, "r") as second_zip:
        first_entries = {
            info.filename: info
            for info in first_zip.infolist()
            if not should_ignore(info.filename)
        }
        second_entries = {
            info.filename: info
            for info in second_zip.infolist()
            if not should_ignore(info.filename)
        }

        missing_from_second = sorted(set(first_entries) - set(second_entries))
        missing_from_first = sorted(set(second_entries) - set(first_entries))

        if missing_from_second or missing_from_first:
            for filename in missing_from_second:
                print(f"file {filename} not found in second APK")
            for filename in missing_from_first:
                print(f"file {filename} not found in first APK")
            return False

        for filename in sorted(first_entries):
            with first_zip.open(first_entries[filename], "r") as first_file:
                with second_zip.open(second_entries[filename], "r") as second_file:
                    if not compare_files(first_file, second_file):
                        print(f"APK file {filename} does not match")
                        return False

        return True


def main():
    if len(sys.argv) != 3:
        print("Usage: apkdiff.py <path-to-first-apk> <path-to-second-apk>")
        return 1

    first_path, second_path = sys.argv[1], sys.argv[2]
    if first_path == second_path or compare(first_path, second_path):
        print("APKs are the same!")
        return 0

    print("APKs are different!")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
