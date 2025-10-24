import 'dart:io';
import 'dart:typed_data';

class Mp4DurationFixerResult {
  final bool patched;
  final int frames;
  final double fps;
  final Duration duration;
  final String note;

  Mp4DurationFixerResult({
    required this.patched,
    required this.frames,
    required this.fps,
    required this.duration,
    required this.note,
  });
}

class MvexMehdInfo {
  final int mvexStart;
  final int mvexSize;
  final int? mehdStart;
  const MvexMehdInfo({
    required this.mvexStart,
    required this.mvexSize,
    required this.mehdStart,
  });
}

class MoofScanResult {
  final int frames;
  final int ticks;
  final int? tfhdTrackId;
  final List<int> moofOffsets;
  final List<int> tfdtTimes;
  MoofScanResult(
    this.frames,
    this.ticks,
    this.tfhdTrackId,
    this.moofOffsets,
    this.tfdtTimes,
  );
}

class Mp4DurationFixer {
  final File input;
  final void Function(String) log;
  final bool forceTrackIdFromTfhd;

  Mp4DurationFixer(
    this.input, {
    void Function(String)? log,
    this.forceTrackIdFromTfhd = false,
  }) : log = log ?? ((s) => stdout.writeln(s));

  // helpers (big-endian r/w)
  int _u32(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  int _u24(Uint8List b, int o) => (b[o] << 16) | (b[o + 1] << 8) | b[o + 2];
  int _u64(Uint8List b, int o) =>
      ((_u32(b, o) & 0xFFFFFFFF) << 32) | (_u32(b, o + 4) & 0xFFFFFFFF);

  void _p32(Uint8List b, int o, int v) {
    b[o] = (v >>> 24) & 0xFF;
    b[o + 1] = (v >>> 16) & 0xFF;
    b[o + 2] = (v >>> 8) & 0xFF;
    b[o + 3] = v & 0xFF;
  }

  void _p64(Uint8List b, int o, int v) {
    _p32(b, o, (v >> 32) & 0xFFFFFFFF);
    _p32(b, o + 4, v & 0xFFFFFFFF);
  }

  String _fourCC(Uint8List b, int o) =>
      String.fromCharCodes([b[o], b[o + 1], b[o + 2], b[o + 3]]);

  int _payloadStart(int boxStart) => boxStart + 8;

  MvexMehdInfo _findMvexMehd(Uint8List f, int moovStart, int moovSize) {
    final moovEnd = moovStart + moovSize;
    int i = moovStart + 8;
    while (i + 8 <= moovEnd) {
      final size = _u32(f, i);
      if (size == 0 || i + size > moovEnd) break;
      final typ = _fourCC(f, i + 4);
      if (typ == 'mvex') {
        final mvexStart = i, mvexSize = size;
        final mvexEnd = mvexStart + mvexSize;

        int? mehdStart;
        int j = mvexStart + 8;
        while (j + 8 <= mvexEnd) {
          final s2 = _u32(f, j);
          if (s2 == 0 || j + s2 > mvexEnd) break;
          final t2 = _fourCC(f, j + 4);
          if (t2 == 'mehd') mehdStart = j;
          j += s2;
        }

        return MvexMehdInfo(
          mvexStart: mvexStart,
          mvexSize: mvexSize,
          mehdStart: mehdStart,
        );
      }
      i += size;
    }
    throw StateError('mvex not found inside moov');
  }

  void _patchMehdDuration(Uint8List f, int mehdStart, int newDur90k) {
    final p = _payloadStart(mehdStart); // version/flags at p..p+3
    final ver = f[p];
    if (ver == 1) {
      final cur = _u64(f, p + 4);
      log("[mehd] v1 cur=$cur -> $newDur90k");
      _p64(f, p + 4, newDur90k);
    } else {
      final cur = _u32(f, p + 4);
      log("[mehd] v0 cur=$cur -> $newDur90k");
      _p32(f, p + 4, newDur90k);
    }
  }

  int? _readMehdDuration(Uint8List f, int mehdStart) {
    final p = _payloadStart(mehdStart);
    final ver = f[p];
    return (ver == 1) ? _u64(f, p + 4) : _u32(f, p + 4);
  }

  (int pos, int size) _findMoov(Uint8List f) {
    int i = 0;
    while (i + 8 <= f.length) {
      final size = _u32(f, i);
      if (size == 0 || i + size > f.length) break;
      final typ = _fourCC(f, i + 4);
      if (typ == 'moov') return (i, size);
      i += size;
    }
    throw StateError('moov not found');
  }

  List<(int pos, int size)> _findMoofs(Uint8List f) {
    final out = <(int, int)>[];
    int i = 0;
    while (i + 8 <= f.length) {
      final size = _u32(f, i);
      if (size == 0 || i + size > f.length) break;
      final typ = _fourCC(f, i + 4);
      if (typ == 'moof') out.add((i, size));
      i += size;
    }
    return out;
  }

  /// Patch mvhd duration
  void _patchMvhdDuration(Uint8List f, int mvhdStart, int newDur90k) {
    final p = _payloadStart(mvhdStart);
    final ver = f[p];
    if (ver == 1) {
      final timescaleOff = p + 4 + 8 + 8; // v1: ver/flags + ctime(8) + mtime(8)
      final durOff = timescaleOff + 4; // timescale(4) then duration(8)
      final ts = _u32(f, timescaleOff);
      final cur = _u64(f, durOff);
      log("[mvhd] v1 ts=$ts cur=$cur -> $newDur90k");
      _p64(f, durOff, newDur90k);
    } else {
      final timescaleOff = p + 4 + 4 + 4; // v0: ver/flags + ctime(4) + mtime(4)
      final durOff = timescaleOff + 4; // timescale(4) then duration(4)
      final ts = _u32(f, timescaleOff);
      final cur = _u32(f, durOff);
      log("[mvhd] v0 ts=$ts cur=$cur -> $newDur90k");
      _p32(f, durOff, newDur90k);
    }
  }

  /// Patch tkhd duration and (optionally) repair track_ID.
  /// We only overwrite tkhd.track_ID if it's 0 (clearly broken), or
  /// forceTrackIdFromTfhd == true (explicit user choice to repair a bad file).
  void _patchTkhd(
    Uint8List f,
    int tkhdStart,
    int mvhdTimescale,
    int newDur90k,
    int? tfhdTrackId,
  ) {
    final p = _payloadStart(tkhdStart);
    final ver = f[p];

    bool maybeRepairId(int curId) {
      if (tfhdTrackId == null) return false;
      if (curId == 0 || forceTrackIdFromTfhd) {
        if (curId != tfhdTrackId) {
          log("[tkhd] track_ID fix: $curId -> $tfhdTrackId");
          return true;
        }
      } else if (curId != tfhdTrackId) {
        log(
          "[tkhd] track_ID differs (tkhd=$curId, tfhd=$tfhdTrackId) — leaving as-is",
        );
      }
      return false;
    }

    if (ver == 1) {
      final idOff = p + 4 + 8 + 8;
      final durOff = idOff + 4 + 4;
      final curId = _u32(f, idOff);
      final curDur = _u64(f, durOff);

      if (maybeRepairId(curId)) _p32(f, idOff, tfhdTrackId!);

      final newDur = (newDur90k * (mvhdTimescale.toDouble() / 90000.0)).round();
      log("[tkhd] v1 dur fix ts=$mvhdTimescale cur=$curDur -> $newDur");
      _p64(f, durOff, newDur);
    } else {
      final idOff = p + 4 + 4 + 4;
      final durOff = idOff + 4 + 4;
      final curId = _u32(f, idOff);
      final curDur = _u32(f, durOff);

      if (maybeRepairId(curId)) _p32(f, idOff, tfhdTrackId!);

      final newDur = (newDur90k * (mvhdTimescale.toDouble() / 90000.0)).round();
      log("[tkhd] v0 dur fix ts=$mvhdTimescale cur=$curDur -> $newDur");
      _p32(f, durOff, newDur);
    }
  }

  /// Patch mdhd duration
  void _patchMdhd(Uint8List f, int mdhdStart, int newDur90k) {
    final p = _payloadStart(mdhdStart);
    final ver = f[p];
    if (ver == 1) {
      final tsOff = p + 4 + 8 + 8; // ver/flags + ctime(8) + mtime(8)
      final durOff = tsOff + 4; // timescale(4) then duration(8)
      final ts = _u32(f, tsOff);
      final curDur = _u64(f, durOff);
      // Convert 90k-based duration to track media timescale
      final newDur = (newDur90k * (ts.toDouble() / 90000.0)).round();
      log("[mdhd] v1 ts=$ts cur=$curDur -> $newDur (from 90k=$newDur90k)");
      _p64(f, durOff, newDur);
    } else {
      final tsOff = p + 4 + 4 + 4; // v0 layout
      final durOff = tsOff + 4;
      final ts = _u32(f, tsOff);
      final curDur = _u32(f, durOff);
      final newDur = (newDur90k * (ts.toDouble() / 90000.0)).round();
      log("[mdhd] v0 ts=$ts cur=$curDur -> $newDur (from 90k=$newDur90k)");
      _p32(f, durOff, newDur);
    }
  }

  /// Finds mvhd, tkhd, mdhd offsets inside moov (first trak only).
  (int mvhd, int tkhd, int mdhd) _findMvhdTkhdMdhd(
    Uint8List f,
    int moovStart,
    int moovSize,
  ) {
    final moovEnd = moovStart + moovSize;
    int? mvhd, tkhd, mdhd;
    int i = moovStart + 8;
    while (i + 8 <= moovEnd) {
      final size = _u32(f, i);
      if (size == 0 || i + size > moovEnd) break;
      final typ = _fourCC(f, i + 4);
      if (typ == 'mvhd') mvhd = i;
      if (typ == 'trak') {
        // enter trak
        final trakEnd = i + size;
        int j = i + 8;
        while (j + 8 <= trakEnd) {
          final s2 = _u32(f, j);
          if (s2 == 0 || j + s2 > trakEnd) break;
          final t2 = _fourCC(f, j + 4);
          if (t2 == 'tkhd') tkhd ??= j;
          if (t2 == 'mdia') {
            // enter mdia -> mdhd
            final mdiaEnd = j + s2;
            int k = j + 8;
            while (k + 8 <= mdiaEnd) {
              final s3 = _u32(f, k);
              if (s3 == 0 || k + s3 > mdiaEnd) break;
              final t3 = _fourCC(f, k + 4);
              if (t3 == 'mdhd') mdhd ??= k;
              k += s3;
            }
          }
          j += s2;
        }
      }
      i += size;
    }
    if (mvhd == null || tkhd == null || mdhd == null) {
      throw StateError("mvhd/tkhd/mdhd not found inside moov");
    }
    return (mvhd!, tkhd!, mdhd!);
  }

  /// Reads movie timescale from mvhd.
  int _readMovieTimescale(Uint8List f, int mvhdStart) {
    final p = _payloadStart(mvhdStart);
    final ver = f[p];
    if (ver == 1) {
      return _u32(f, p + 4 + 8 + 8);
    } else {
      return _u32(f, p + 4 + 4 + 4);
    }
  }

  /// Reads tkhd.track_ID.
  int _readTkhdTrackId(Uint8List f, int tkhdStart) {
    final p = _payloadStart(tkhdStart);
    final ver = f[p];
    if (ver == 1) {
      return _u32(f, p + 4 + 8 + 8);
    } else {
      return _u32(f, p + 4 + 4 + 4);
    }
  }

  MoofScanResult _deriveFromMoofs(Uint8List f) {
    final moofs = _findMoofs(f);
    int totalTicks = 0;
    int frames = 0;
    int? tfhdTrackId;
    final moofOffsets = <int>[];
    final tfdtTimes = <int>[];

    for (var idx = 0; idx < moofs.length; idx++) {
      final (moofStart, moofSize) = moofs[idx];
      moofOffsets.add(moofStart);
      log(
        "[scan] moof#${idx + 1} @ $moofStart..${moofStart + moofSize - 1} size=$moofSize",
      );

      final moofEnd = moofStart + moofSize;
      int i = moofStart + 8;
      while (i + 8 <= moofEnd) {
        final size = _u32(f, i);
        if (size == 0 || i + size > moofEnd) break;
        final typ = _fourCC(f, i + 4);
        if (typ == 'traf') {
          final trafEnd = i + size;
          int? localTrack;
          int? tfdtBase;
          int localTicks = 0;
          int localFrames = 0;

          int j = i + 8;
          while (j + 8 <= trafEnd) {
            final s2 = _u32(f, j);
            if (s2 == 0 || j + s2 > trafEnd) break;
            final t2 = _fourCC(f, j + 4);

            if (t2 == 'tfhd') {
              final pp = _payloadStart(j);
              final version = f[pp];
              final flags = _u24(f, pp + 1);

              localTrack = _u32(f, pp + 4);
              tfhdTrackId ??= localTrack;
              log(
                "  tfhd track_ID=$localTrack (flags=0x${flags.toRadixString(16)})",
              );
            } else if (t2 == 'tfdt') {
              final pp = _payloadStart(j);
              final ver = f[pp];
              tfdtBase = (ver == 1) ? _u64(f, pp + 4) : _u32(f, pp + 4);
              tfdtTimes.add(tfdtBase);
              log("  tfdt ver=$ver base=$tfdtBase @ $j");
            } else if (t2 == 'trun') {
              final pp = _payloadStart(j);
              final flags = _u24(f, pp + 1);
              final sc = _u32(f, pp + 4);

              int off = pp + 8;
              if ((flags & 0x000001) != 0) off += 4; // data_offset
              if ((flags & 0x000004) != 0) off += 4; // first_sample_flags

              final hasDuration = (flags & 0x000100) != 0;
              int stride = 0;
              if (hasDuration) stride += 4;
              if ((flags & 0x000200) != 0) stride += 4; // size
              if ((flags & 0x000400) != 0) stride += 4; // flags
              if ((flags & 0x000800) != 0) stride += 4; // cts offset

              int tickSum = 0;
              if (hasDuration) {
                for (int s = 0; s < sc; s++) {
                  tickSum += _u32(f, off + s * stride);
                }
              }
              localTicks += tickSum;
              localFrames += sc;
              log(
                "    [trun] flags=0x${flags.toRadixString(16)} sc=$sc hasDur=$hasDuration localTicks=$tickSum",
              );
            }
            j += s2;
          }
          totalTicks += localTicks;
          frames += localFrames;
        }
        i += size;
      }
    }

    log("[scan] trun totals: frames=$frames ticks=$totalTicks");
    log("[scan] tfdt list: ${tfdtTimes.isEmpty ? '[]' : tfdtTimes}");
    return MoofScanResult(
      frames,
      totalTicks,
      tfhdTrackId,
      moofOffsets,
      tfdtTimes,
    );
  }

  Future<Mp4DurationFixerResult> fix() async {
    log(
      "==[Mp4DurationFixer v3.3]================================================",
    );
    log("Input: ${input.path}");

    final data = await input.readAsBytes();
    final f = Uint8List.fromList(data);

    // Find moov + essential boxes
    final (moovStart, moovSize) = _findMoov(f);
    log("[moov] @ $moovStart size=$moovSize");

    final (mvhdStart, tkhdStart, mdhdStart) = _findMvhdTkhdMdhd(
      f,
      moovStart,
      moovSize,
    );
    final movieTs = _readMovieTimescale(f, mvhdStart);
    final tkhdIdBefore = _readTkhdTrackId(f, tkhdStart);
    log("[mvhd] movie timescale=$movieTs");
    log("[tkhd] current track_ID=$tkhdIdBefore");

    // Derive duration from fragments
    final scan = _deriveFromMoofs(f);
    if (scan.frames == 0 || scan.ticks == 0) {
      log("[exit] Could not derive duration (no frames/ticks). No changes.");
      return Mp4DurationFixerResult(
        patched: false,
        frames: 0,
        fps: 0,
        duration: Duration.zero,
        note: "no trun durations",
      );
    }

    final seconds = scan.ticks / 90000.0;
    final fps = scan.frames / seconds;
    final dur = Duration(microseconds: (seconds * 1e6).round());
    log(
      "[derived] frames=${scan.frames} totalTicks=${scan.ticks} -> $dur (fps≈${fps.toStringAsFixed(3)})",
    );

    // Patch durations
    _patchMvhdDuration(f, mvhdStart, scan.ticks);
    _patchTkhd(f, tkhdStart, movieTs, scan.ticks, scan.tfhdTrackId);
    _patchMdhd(f, mdhdStart, scan.ticks);

    // Patch mehd
    try {
      final mvexInfo = _findMvexMehd(f, moovStart, moovSize);
      if (mvexInfo.mehdStart != null) {
        _patchMehdDuration(f, mvexInfo.mehdStart!, scan.ticks);
        log("[mehd] patched");
      } else {
        log("[mehd] not present — skipping");
      }
    } catch (e) {
      log("[mvex/mehd] not found — skipping ($e)");
    }

    // Atomic rewrite
    final tmp = File("${input.path}.tmp_fix");
    await tmp.writeAsBytes(f, flush: true);
    await tmp.rename(input.path);
    log("[write] atomic rename OK");

    // Verify what we wrote: read back mvhd/mdhd durations only
    final back = await input.readAsBytes();
    final bf = Uint8List.fromList(back);
    final (mv2Start, mv2Size) = _findMoov(bf);
    final (mvhd2, tkhd2, mdhd2) = _findMvhdTkhdMdhd(bf, mv2Start, mv2Size);
    final movieTs2 = _readMovieTimescale(bf, mvhd2);

    try {
      final mvexInfo2 = _findMvexMehd(bf, mv2Start, mv2Size);
      if (mvexInfo2.mehdStart != null) {
        final mdur = _readMehdDuration(bf, mvexInfo2.mehdStart!);
        log(
          "[verify] mehd dur=$mdur expect=${scan.ticks} -> ${mdur == scan.ticks ? 'ok' : 'mismatch!'}",
        );
      } else {
        log("[verify] mehd absent");
      }
    } catch (_) {
      log("[verify] mvex/mehd not found");
    }

    // read mvhd duration again
    final mvhdP = _payloadStart(mvhd2);
    final mvVer = bf[mvhdP];
    final mvDur =
        (mvVer == 1)
            ? _u64(bf, mvhdP + 4 + 8 + 8 + 4) // v1 path to duration
            : _u32(bf, mvhdP + 4 + 4 + 4 + 4);
    log(
      "[verify] mvhd ts=$movieTs2 dur=$mvDur expect=${scan.ticks} -> ${mvDur == scan.ticks ? 'ok' : 'mismatch!'}",
    );

    final tkIdAfter = _readTkhdTrackId(bf, tkhd2);
    log(
      "[verify] tkhd track_ID=$tkIdAfter (was $tkhdIdBefore, tfhd=${scan.tfhdTrackId})",
    );

    return Mp4DurationFixerResult(
      patched: true,
      frames: scan.frames,
      fps: fps,
      duration: dur,
      note: "patched durations (mvhd/tkhd/mdhd); track_ID=${tkIdAfter}",
    );
  }
}
