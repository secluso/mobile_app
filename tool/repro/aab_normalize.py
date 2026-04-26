#!/usr/bin/env python3

import pathlib
import sys
import zipfile


FIXED_DT = (1980, 1, 1, 0, 0, 0)


def normalize_archive(input_path: pathlib.Path, output_path: pathlib.Path) -> None:
    with zipfile.ZipFile(input_path, "r") as src, zipfile.ZipFile(
        output_path,
        "w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
        allowZip64=True,
    ) as dst:
        dst.comment = b""
        for name in sorted(info.filename for info in src.infolist() if not info.is_dir()):
            data = src.read(name)
            info = zipfile.ZipInfo(filename=name, date_time=FIXED_DT)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 0
            info.create_version = 20
            info.extract_version = 20
            info.flag_bits = 0
            info.volume = 0
            info.internal_attr = 0
            info.external_attr = 0
            info.extra = b""
            info.comment = b""
            dst.writestr(info, data)


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: aab_normalize.py <input.aab> <output.aab>", file=sys.stderr)
        return 2

    input_path = pathlib.Path(sys.argv[1]).resolve()
    output_path = pathlib.Path(sys.argv[2]).resolve()

    if not input_path.is_file():
        print(f"Missing AAB archive: {input_path}", file=sys.stderr)
        return 2
    if input_path == output_path:
        print("Input and output paths must differ.", file=sys.stderr)
        return 2

    output_path.parent.mkdir(parents=True, exist_ok=True)
    normalize_archive(input_path, output_path)
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
