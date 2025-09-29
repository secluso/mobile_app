//! SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

extension MP4H264Demuxer {

    /// This method decodes the Sample Table (stbl) box, which groups together sample description, sample size, and other timing tables.
    ///  It iterates through the child boxes and selectively handles the stsd and stsz boxes, delegating each to its own parser.
    /// Any other box types are skipped. The function updates the provided Trak structure in place with the parsed results.
    func parseStbl(_ data: Data, into t: inout Trak) {
        var cursor = 0
        while cursor + 8 <= data.count {
            // Read a standard ISO BMFF box header from data[cursor...]:
            // size32: 32-bit big-endian box size field (includes header bytes)
            // typ: 4-byte ASCII FourCC identifying the child box (e.g. "stsd", "stsz").
            // If size==1, the real size is carried in an extended 64-bit field per ISO/IEC 14496-12.
            guard let size32 = data.be32(at: cursor),
                let typ = data.fourCC(at: cursor + 4)
            else { break }
            var boxSize = Int(size32)
            var headerLen = 8
            if boxSize == 1 {
                guard let size64 = data.be64(at: cursor + 8) else { break }
                boxSize = Int(size64)
                headerLen = 16
            }
            guard boxSize >= headerLen, cursor + boxSize <= data.count else { break }

            // Compute the child box payload range [payloadStart, payloadEnd) relative to stbl.
            // Guard against truncated input so we never slice beyond data.count.
            let payloadStart = cursor + headerLen
            let payloadEnd = cursor + boxSize
            guard let payload = safeSlice(data, payloadStart, payloadEnd) else { break }

            switch typ {
            case "stsd":
                // "stsd" (Sample Description): declares sample entries (codec + decoder config).
                // We parse it to find the avcC (AVCDecoderConfigurationRecord) and cache SPS/PPS/NAL length size.
                parseStsd(payload, into: &t)
            case "stsz":
                // "stsz" (Sample Size): gives either a single default size for all samples or
                // an array of per-sample byte sizes. We need this to slice mdat into samples.
                t.stsz = parseStsz(payload)
            default:
                break
            }

            // Advance to the next child inside stbl by adding the full box size (header + payload).
            cursor += boxSize
        }
    }

    /// This method parses the Sample Description (stsd) box, which declares the codec and codec-specific data for the track.
    /// It walks through each entry, checking for AVC-related sample entries (avc1, avc3, encv), and records the four-character code for logging.
    /// After skipping the Visual Sample Entry header, it inspects child boxes like avcC.
    /// The AVC decoder configuration record provides SPS, PPS, and NAL length size, which are stored in the track’s avcC field.

    private func parseStsd(_ data: Data, into t: inout Trak) {
        guard data.count >= 16, let entryCountU = data.be32(at: 4) else { return }
        // stsd FullBox layout (ISO/IEC 14496-12):
        //   version(1) flags(3) entry_count(4) followed by entry_count SampleEntry boxes.
        // We only care about Visual Sample Entries like "avc1"/"avc3" (or "encv" with an avcC child).

        var cursor = 8
        let entryCount = Int(entryCountU)

        for _ in 0..<entryCount {
            guard cursor + 8 <= data.count,
                let size32 = data.be32(at: cursor),
                let typ = data.fourCC(at: cursor + 4)
            else { return }

            // For each SampleEntry, read its 32-bit size and type FourCC. If size==1,
            // an extended 64-bit size follows. The box size bounds the entire SampleEntry.
            var boxSize = Int(size32)
            var headerLen = 8
            if boxSize == 1 {
                guard let size64 = data.be64(at: cursor + 8) else { return }
                boxSize = Int(size64)
                headerLen = 16
            }
            guard cursor + boxSize <= data.count else { return }

            // Slice the SampleEntry payload (after its header). VisualSampleEntry carries
            // fixed fields (width/height, compressor name, etc.) followed by child boxes
            // like "avcC", "pasp", "btrt". We skip the 78-byte VisualSampleEntry header
            // (per QT/ISOBMFF conventions) and then iterate child boxes.
            let entryStart = cursor + headerLen
            let entryEnd = cursor + boxSize
            guard let entry = safeSlice(data, entryStart, entryEnd) else { return }

            if typ == "avc1" || typ == "avc3" || typ == "encv" {
                sampleEntryFourCC = typ
                emitDebug("[MP4] stsd entry=\(typ)")

                // Skip VisualSampleEntry header (78 bytes)
                let visualHeaderLen = min(78, entry.count)
                var ec = visualHeaderLen

                // Walk nested boxes inside the SampleEntry payload. Each child starts with
                // size(4) + type(4); size==1 indicates a 64-bit extended size. Bounds checks
                // prevent reading past entry.count.
                while ec + 8 <= entry.count {
                    guard let esizeU = entry.be32(at: ec),
                        let etyp = entry.fourCC(at: ec + 4)
                    else { break }
                    var esize = Int(esizeU)
                    var eh = 8
                    if esize == 1 {
                        guard let ext = entry.be64(at: ec + 8) else { break }
                        esize = Int(ext)
                        eh = 16
                    }
                    guard esize >= eh, ec + esize <= entry.count else { break }
                    let epStart = ec + eh
                    let epEnd = ec + esize

                    if etyp == "avcC", let avcPayload = safeSlice(entry, epStart, epEnd) {
                        // "avcC" (AVCDecoderConfigurationRecord): carries decoder config for H.264/AVC,
                        // including NAL length field size and the SPS/PPS parameter sets needed to build
                        // a CMVideoFormatDescription later.
                        let conf = parseAvcC(avcPayload)
                        t.avcC = conf
                        emitDebug(
                            "[MP4] avcC: nalLenSize=\(conf.nalLengthSize) sps=\(conf.sps.count) pps=\(conf.pps.count)"
                        )
                        // Don't break immediately. some files have multiple children, but avcC is the one we need.
                    }

                    ec += esize
                }
            }

            cursor += boxSize
        }
    }

    /// This helper interprets the AVCDecoderConfigurationRecord contained inside an avcC box.
    /// It extracts the declared NAL length size, followed by the sequence parameter sets (SPS) and picture parameter sets (PPS).
    /// These arrays are returned in a lightweight struct so the demuxer can later construct a format description.
    /// The method validates boundaries carefully to avoid overruns.

    private func parseAvcC(_ data: Data) -> AvcC {
        // AVCDecoderConfigurationRecord
        guard data.count >= 7 else { return .init(nalLengthSize: 4, sps: [], pps: []) }

        // AVCDecoderConfigurationRecord layout (ISO/IEC 14496-15):
        //   configurationVersion(1)
        //   AVCProfileIndication(1), profile_compatibility(1), AVCLevelIndication(1)
        //   lengthSizeMinusOne(1 low 2 bits)  → nalLengthSize = (value & 0x3) + 1
        //   numOfSequenceParameterSets(1 low 5 bits) then repeated [be16 length + SPS]
        //   numOfPictureParameterSets(1) then repeated [be16 length + PPS]
        // We extract nalLengthSize, then copy each SPS/PPS blob verbatim.

        let nalLenSize = Int((data[4] & 0x03) + 1)  // lengthSizeMinusOne + 1
        var i = 5

        // numOfSequenceParameterSets (lower 5 bits)
        var spsArr: [Data] = []
        var ppsArr: [Data] = []

        // Lower 5 bits: number of SPS. Each SPS is length-prefixed with a big-endian u16,
        // followed by that many bytes of the SPS RBSP (without start codes).
        let numSPS = Int(data[i] & 0x1F)
        i += 1
        for _ in 0..<numSPS {
            guard let n = data.be16(at: i) else {
                return .init(nalLengthSize: nalLenSize, sps: spsArr, pps: ppsArr)
            }
            i += 2
            guard i + Int(n) <= data.count else {
                return .init(nalLengthSize: nalLenSize, sps: spsArr, pps: ppsArr)
            }
            spsArr.append(data.subdata(in: i..<(i + Int(n))))
            i += Int(n)
        }

        guard i < data.count else {
            return .init(nalLengthSize: nalLenSize, sps: spsArr, pps: ppsArr)
        }

        // Next: number of PPS. Each PPS is likewise a big-endian u16 length + payload.
        let numPPS = Int(data[i])
        i += 1
        for _ in 0..<numPPS {
            guard let n = data.be16(at: i) else { break }
            i += 2
            guard i + Int(n) <= data.count else { break }
            ppsArr.append(data.subdata(in: i..<(i + Int(n))))
            i += Int(n)
        }

        // Return a compact summary so callers can cache SPS/PPS and the nalLengthSize
        // used to parse length-prefixed NAL units in samples.
        return .init(nalLengthSize: nalLenSize, sps: spsArr, pps: ppsArr)
    }

    /// This helper decodes the Sample Size (stsz) box.
    /// It first checks whether the box declares a single default size, in which case all samples are assumed to share that length.
    /// Otherwise, it builds an array of per-sample sizes by reading each entry sequentially.
    /// The results are packaged into the STSZ struct so the demuxer can later stream samples without ambiguity.
    private func parseStsz(_ data: Data) -> STSZ {
        // fullbox(4) + sample_size(4) + sample_count(4) + sizes[]
        guard data.count >= 16,
            let defaultSize32 = data.be32(at: 4),
            let count32 = data.be32(at: 8)
        else {
            return .init(defaultSize: 0, sizes: [])
        }

        // stsz (Sample Size) box (ISO/IEC 14496-12):
        //   version(1) flags(3) sample_size(4) sample_count(4) [entry_size[i]]*
        // If sample_size != 0, that fixed size applies to all samples and the table is omitted.
        // Otherwise, a sample_count-length table of 32-bit sizes follows starting at offset 12.
        let defaultSize = Int(defaultSize32)
        let count = Int(count32)

        // Fast path: constant sample size. No per-sample table to read.
        if defaultSize != 0 { return .init(defaultSize: defaultSize, sizes: []) }

        var sizes: [Int] = []
        sizes.reserveCapacity(count)
        var i = 12
        // Variable sample sizes: read count entries of 32-bit big-endian sizes.
        // We pre-reserve capacity and stop early if any entry would run past data.count.
        for _ in 0..<count {
            guard let sz = data.be32(at: i) else { break }
            sizes.append(Int(sz))
            i += 4
        }

        // Return a dense array of per-sample sizes; the demuxer will use it to slice mdat
        // into discrete AVCC samples when draining payload bytes.
        return .init(defaultSize: 0, sizes: sizes)
    }

}
