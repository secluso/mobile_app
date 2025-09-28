import Foundation

/// Utilities for reading big-endian values and FourCCs directly from Data.
/// Each accessor performs explicit bounds checks and returns nil when the
/// requested range would be out of bounds. The implementations build values
/// byte-by-byte to avoid unaligned loads and to keep behavior consistent on
/// all architectures. These helpers are suitable for tight parsing loops and
/// for producing readable log output without sprinkling manual pointer math
/// across call sites.
extension Data {

    /// Reads an unsigned 16-bit big-endian integer starting at byte offset o.
    /// The method returns nil if there are fewer than two bytes available
    /// from that position. The value is assembled one byte at a time to avoid
    /// unaligned memory access.
    @inline(__always)
    func be16(at o: Int) -> UInt16? {
        guard o >= 0, o <= count - 2 else { return nil }
        return withUnsafeBytes { raw -> UInt16 in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            let p = base.advanced(by: o)
            let b0 = UInt16(p.pointee)
            let b1 = UInt16(p.advanced(by: 1).pointee)
            return (b0 << 8) | b1
        }
    }

    /// Reads an unsigned 32-bit big-endian integer starting at byte offset o.
    /// The method returns nil if there are fewer than four bytes available.
    /// Bytes are combined manually to keep the code portable and predictable.
    @inline(__always)
    func be32(at o: Int) -> UInt32? {
        guard o >= 0, o <= count - 4 else { return nil }
        return withUnsafeBytes { raw -> UInt32 in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            let p = base.advanced(by: o)
            let b0 = UInt32(p.pointee)
            let b1 = UInt32(p.advanced(by: 1).pointee)
            let b2 = UInt32(p.advanced(by: 2).pointee)
            let b3 = UInt32(p.advanced(by: 3).pointee)
            return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        }
    }

    // /Reads an unsigned 64-bit big-endian integer starting at byte offset o.
    /// The method returns nil if there are fewer than eight bytes available.
    /// A simple loop composes the value to avoid any undefined behavior from
    /// unaligned loads.
    @inline(__always)
    func be64(at o: Int) -> UInt64? {
        guard o >= 0, o <= count - 8 else { return nil }
        return withUnsafeBytes { raw -> UInt64 in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            let p = base.advanced(by: o)
            var v: UInt64 = 0
            for i in 0..<8 { v = (v << 8) | UInt64(p.advanced(by: i).pointee) }
            return v
        }
    }

    /// Reads four bytes at offset o and returns them as an ASCII String.
    /// The method returns nil if there are fewer than four bytes or if the
    /// bytes cannot be decoded as ASCII. Use this for human-readable logging
    /// of MP4 FourCCs and box types.
    @inline(__always)
    func fourCC(at o: Int) -> String? {
        guard o >= 0, o <= count - 4 else { return nil }
        return withUnsafeBytes { raw -> String? in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            let p = base.advanced(by: o)
            var bytes = [UInt8](repeating: 0, count: 4)
            bytes[0] = p.pointee
            bytes[1] = p.advanced(by: 1).pointee
            bytes[2] = p.advanced(by: 2).pointee
            bytes[3] = p.advanced(by: 3).pointee
            return String(bytes: bytes, encoding: .ascii)
        }
    }
}
