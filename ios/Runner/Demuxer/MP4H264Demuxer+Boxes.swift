//! SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

extension MP4H264Demuxer {
    /// Parses top-level MP4 boxes from the internal byte buffer while the demuxer
    /// is in the header-reading state. This walks box headers safely using
    /// size/fourCC checks, supports 32-bit and extended 64-bit sizes, and treats
    /// size==0 as to EOF only for mdat. Non-mdat boxes are fully buffered
    /// before dispatch to specific parsers. Mdat is special-cased so streaming
    /// can begin as soon as its header is present. The method also performs
    /// lightweight resync if the next fourCC is not printable, and advances or
    /// trims the live buffer only after work is complete to avoid aliasing issues.
    func parseBoxesIfNeeded() {
        // Only parse when we're in the header-reading phase. Streaming happens in drainMdatIfPossible().
        guard state == .readingHeaders else { return }

        while true {
            // An ISO BMFF "box" (a.k.a. atom) header is at least 8 bytes: 4-byte big-endian size
            // followed by a 4-byte ASCII type (four-character code). Don’t attempt to parse until
            // we have at least those 8 bytes on hand. (ISO/IEC 14496-12 4.2)
            guard buffer.count >= 8 else { return }

            // Work on a snapshot to avoid slicing directly from a buffer we’ll mutate below. This
            // prevents aliasing and out-of-bounds mistakes when we later remove bytes from buffer.
            let bytes = buffer

            // Sanity-check the prospective type field: if the next 4 bytes after the size aren’t
            // printable ASCII, we likely aren’t aligned on a box boundary. Try to resync instead
            // of reading garbage as a size.
            if !hasPrintableFourCC(in: bytes, at: 4) {
                if resyncToBoxBoundary() == false { return }
                continue
            }

            // Read the 32-bit size and 4-char type. Size counts the entire box including the header.
            guard let size32 = bytes.be32(at: 0),
                let typ = bytes.fourCC(at: 4)
            else { return }

            var boxSize = Int(size32)
            var headerLen = 8

            // Extended size handling: size==1 means a 64-bit size follows at offset 8, and the
            // header is 16 bytes. This accommodates very large boxes. (ISO/IEC 14496-12 4.2)
            if boxSize == 1 {
                guard bytes.count >= 16, let size64 = bytes.be64(at: 8) else { return }
                boxSize = Int(size64)
                headerLen = 16

                // Size==0 means “extends to end of file”. In practice this is used for media data.
                // We treat it as valid only for mdat and defer other boxes until more bytes arrive.
            } else if boxSize == 0 && typ != "mdat" {
                // Only mdat sensibly uses to EOF here—others: wait for more bytes.
                emitDebug("[MP4] box '\(typ)' has size==0 (to EOF) – waiting for more bytes")
                return
            }

            // Guard against nonsensical headers (e.g., size smaller than header length).
            guard boxSize >= headerLen else {
                emitDebug(
                    "[MP4] invalid header for '\(typ)' (boxSize \(boxSize) < headerLen \(headerLen)); resync"
                )
                if resyncToBoxBoundary() == false { return }
                continue
            }

            if typ == "mdat" {
                // We have at least the header. Start streaming its payload immediately. If size32==0
                // the payload runs to EOF, otherwise the byte budget is (boxSize - headerLen).
                inMdat = true
                if size32 == 0 {
                    mdatRemaining = nil  // to EOF
                } else {
                    mdatRemaining = Int64(boxSize - headerLen)
                }

                emitDebug(
                    "[MP4] enter mdat: headerLen=\(headerLen) payloadLen=\(mdatRemaining.map { String($0) } ?? "∞")"
                )

                // If a previous partial NAL length/payload tail was stashed, prepend it so parsing
                // sees a seamless byte stream across mdat boundaries.
                if !mdatRemainder.isEmpty {
                    mdatPayload.append(mdatRemainder)
                    emitDebug("[MP4] carried tail into new mdat: +\(mdatRemainder.count)B")
                    mdatRemainder.removeAll(keepingCapacity: true)
                }

                // Move any already-available payload bytes (right after the header) from the snapshot
                // into the streaming buffer. Clamp to the declared remaining size when bounded.
                let available = bytes.count - headerLen
                if available > 0 {
                    let cap = mdatRemaining.map { max(0, Int($0)) } ?? available
                    let take = min(available, cap)

                    if take > 0 {
                        guard let chunk = safeSlice(bytes, headerLen, headerLen + take) else {
                            emitDebug(
                                "[MP4] mdat slice OOB: hdr=\(headerLen) take=\(take) buf=\(bytes.count)"
                            )
                            return
                        }
                        mdatPayload.append(chunk)
                        if let r = mdatRemaining { mdatRemaining = r - Int64(take) }

                        // Drop the header + consumed payload from the live buffer now that we’re done with the snapshot.
                        let toDrop = headerLen + take
                        if toDrop <= buffer.count {
                            buffer.removeFirst(toDrop)
                        } else {
                            // Defensive clamp if the live buffer changed size since we snapshotted
                            buffer.removeAll(keepingCapacity: false)
                        }
                    } else {
                        // Header-only so far, drop just the header from the live buffer.
                        if headerLen <= buffer.count {
                            buffer.removeFirst(headerLen)
                        } else {
                            buffer.removeAll(keepingCapacity: false)
                        }
                    }
                } else {
                    // No payload bytes yet; drop just the header from the live buffer.
                    if headerLen <= buffer.count {
                        buffer.removeFirst(headerLen)
                    } else {
                        buffer.removeAll(keepingCapacity: false)
                    }
                }

                // Switch to streaming mode, actual NAL/sample emission happens in drainMdatIfPossible().
                state = .streamingMdat
                break
            }

            // Non-mdat: require full box in snapshot
            // For metadata boxes we require the full box to be present in the snapshot before dispatching
            // to specialized parsers to avoid partial reads.
            if boxSize > bytes.count {
                emitDebug("[MP4] incomplete box '\(typ)': need \(boxSize)B, have \(bytes.count)B")
                return
            }

            let payloadStart = headerLen
            let payloadEnd = boxSize
            guard let payload = safeSlice(bytes, payloadStart, payloadEnd) else { return }

            // Dispatch based on type; only a few are relevant to the minimal demux path.
            switch typ {
            case "ftyp":
                break  // brand info not needed for basic demux
            case "moov":
                parseMoov(payload)  // movie header + track tables
            case "moof":
                // fragmented movies not needed
                break
            case "free", "skip", "wide", "sidx", "mvex", "prft", "uuid":
                break
            default:
                emitDebug("[MP4] skipping box '\(typ)' (\(payload.count)B)")
            }

            // Finished with this box: drop it from the live buffer and continue scanning.
            if boxSize <= buffer.count {
                buffer.removeFirst(boxSize)
            } else {
                // Defensive clamp if the live buffer changed size since we snapshotted
                buffer.removeAll(keepingCapacity: false)
            }

            // If fewer than 8 bytes remain, we can’t form another header yet.
            if buffer.count < 8 { return }
        }
    }

    /// Attempts to realign the internal buffer to the start of a plausible MP4
    /// box header. It scans for a 4-byte size that is 0, 1, or greater than 8 followed by
    /// an ASCII fourCC, drops any stray bytes before that position, and reports
    /// whether progress was made. If insufficient bytes are available to decide,
    /// it leaves the buffer untouched and returns false.
    @inline(__always)
    private func resyncToBoxBoundary() -> Bool {
        // Attempt to realign the buffer so index 0 starts at a plausible box header. We scan for
        // the pattern: 4-byte big-endian size (0, 1, or greater than 8) followed by 4 printable ASCII bytes.
        // On success, drop any stray prefix from the live buffer so parsing can resume at that point.
        let bytes = buffer
        let n = bytes.count
        guard n >= 8 else { return false }

        var i = 0
        while i <= n - 8 {
            if let sz = bytes.be32(at: i), sz == 0 || sz == 1 || sz >= 8,
                hasPrintableFourCC(in: bytes, at: i + 4)
            {
                if i > 0 {
                    emitDebug("[MP4] resync: dropped \(i) stray bytes before 4CC @\(i+4)")
                    buffer.removeFirst(i)  // mutate real buffer only here
                }
                return true
            }
            i += 1
        }

        // If we still can’t find a header, log a small prefix to aid debugging.
        if n >= 12 {
            let head = buffer.prefix(12).map { String(format: "%02x", $0) }.joined(separator: " ")
            emitDebug("[MP4] header not aligned yet; head=\(head)")
        }
        return false
    }

    /// Validates that the 4 bytes at the given offset form a printable ASCII
    /// fourCC. This is used as a quick sanity check while walking box headers
    /// and when attempting to resync to a box boundary.
    @inline(__always)
    private func hasPrintableFourCC(in bytes: Data, at off: Int) -> Bool {
        let end = off + 4
        guard end <= bytes.count, let four = safeSlice(bytes, off, end) else { return false }
        for b in four { if b < 0x20 || b > 0x7E { return false } }
        return true
    }

    /// Drains media payload bytes when inside an mdat or when leftover mdat
    /// data remains. It first moves any newly received bytes from the main buffer
    /// into an internal mdatPayload, then ensures a format description and frame
    /// duration exist before emitting samples. If a sample size table is present,
    /// it slices fixed or per-sample lengths into discrete AVCC samples. Otherwise,
    /// it falls back to length-prefixed NAL parsing directly from the payload.
    /// When the declared mdat byte count reaches zero and the payload is empty,
    /// it returns to header parsing to look for subsequent boxes.
    func drainMdatIfPossible() {
        // Move newly arrived media bytes from buffer into mdatPayload. If mdatRemaining is
        // non-nil, it tracks the number of bytes left in the current mdat. Otherwise, the box
        // extends to EOF and we consume everything available.
        if inMdat {
            if var remaining = mdatRemaining {
                if !buffer.isEmpty && remaining > 0 {
                    let take = min(Int64(buffer.count), remaining)
                    mdatPayload.append(buffer.prefix(Int(take)))
                    buffer.removeFirst(Int(take))
                    remaining -= take
                    mdatRemaining = remaining
                }
            } else {
                if !buffer.isEmpty {
                    mdatPayload.append(buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
        } else {
            // If we’re not currently inside an mdat and there’s no leftover payload, return to
            // header parsing to find the next box. Otherwise, keep draining the existing payload.
            if mdatPayload.isEmpty {
                emitDebug("[MP4] not in mdat → parse headers")
                parseBoxesIfNeeded()
                return
            }
            // else: we still have leftover payload from a fully-seeded mdat, keep draining below.
        }

        emitDebug(
            "[MP4] drainMdat: payload=\(mdatPayload.count)B remaining=\(mdatRemaining.map { String($0) } ?? "∞") sampleIndex=\(sampleIndex)"
        )

        // We cannot emit samples until a CMVideoFormatDescription exists and we’ve derived
        // a frame duration from the SPS timing (VUI). Format description is required for
        // CMSampleBuffer creation, timing is required to schedule against the layer timebase.
        ensureFormatDescription()
        let frameDur = currentFrameDuration()
        guard fmtDesc != nil, frameDur.isValid else {
            emitDebug("[MP4] waiting for SPS VUI timing and fmtDesc before scheduling")
            return
        }

        if sampleSizes.isEmpty && defaultSampleSize == 0 {
            // No stsz/default sizing available: parse AVCC length-prefixed NAL units directly
            // from mdatPayload into access units.
            drainAvccFromMdatPayload()
        } else {
            // stsz/default-size path: slice contiguous bytes at the known per-sample or fixed sizes
            // and emit them as AVCC-framed samples in order.
            while true {
                guard let sampleLen = nextSampleSize() else { break }
                guard mdatPayload.count >= sampleLen else { break }
                let sample = mdatPayload.prefix(sampleLen)
                emitDebug("[MP4] emit sample len=\(sample.count)")
                emitSample(avccSample: sample)
                mdatPayload.removeFirst(sampleLen)
                sampleIndex += 1
            }
        }

        // If we had a bounded mdat and we’ve consumed its payload, switch back to header parsing
        // to look for subsequent boxes (e.g., another mdat or trailer metadata).
        if let rem = mdatRemaining, rem <= 0, mdatPayload.isEmpty {
            emitDebug("[MP4] mdat drained → back to readingHeaders")
            inMdat = false
            state = .readingHeaders
            mdatRemaining = nil
            parseBoxesIfNeeded()
        }
    }

    /// Returns the next sample size according to stsz. If a default size was
    /// specified, that fixed size is used for every sample, otherwise the method
    /// reads the next entry from the per-sample size array and advances the
    /// running index. A nil return indicates there are no more samples described
    /// by the table.
    private func nextSampleSize() -> Int? {
        if defaultSampleSize != 0 {
            return defaultSampleSize
        }
        guard sampleIndex < sampleSizes.count else { return nil }
        return sampleSizes[sampleIndex]
    }
}
