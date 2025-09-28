import Foundation

/// A simple bitstream reader for parsing H.264 SPS and other fields that use
/// Exp-Golomb coding. The reader wraps a byte array and exposes methods to
/// consume single bits, fixed-width values, and unsigned or signed Exp-Golomb
/// codes. State is tracked by a bit position that advances as reads occur.
struct BitReader {
    let bytes: [UInt8]
    var bitPos: Int = 0

    /// Initializes a new reader positioned at the start of the given byte array.
    init(bytes: [UInt8]) { self.bytes = bytes }

    /// Reads a single bit from the stream and advances the position.
    /// Returns 0 or 1, or nil if the end of the array is reached.
    mutating func readBit() -> Int? {
        let byteIndex = bitPos >> 3
        guard byteIndex < bytes.count else { return nil }
        let bitIndex = 7 - (bitPos & 7)
        let bit = (bytes[byteIndex] >> bitIndex) & 1
        bitPos += 1
        return Int(bit)
    }

    /// Reads n bits (up to 32) and assembles them into an integer.
    /// Bits are read most-significant first. Returns nil if there are
    /// not enough bits left in the stream.
    mutating func readBits(_ n: Int) -> Int? {
        guard n >= 0 && n <= 32 else { return nil }
        var v = 0
        for _ in 0..<n {
            guard let b = readBit() else { return nil }
            v = (v << 1) | b
        }
        return v
    }

    /// Reads an unsigned Exp-Golomb (UE) value. This consists of a run of
    /// leading zero bits followed by a one and the remainder bits. Returns
    /// the decoded integer or nil if the code is malformed or truncated.
    mutating func readUE() -> Int? {
        var zeros = 0
        while let b = readBit(), b == 0 { zeros += 1 }
        if zeros > 24 { return nil }
        var value = 1
        for _ in 0..<zeros {
            guard let b = readBit() else { return nil }
            value = (value << 1) | b
        }
        return value - 1
    }

    /// Reads a signed Exp-Golomb (SE) value. This decodes the unsigned code
    /// first, then maps it onto positive and negative integers using the
    /// standard mapping rule: 0->0, 1->1, 2-> -1, 3->2, 4-> -2, and so on.
    mutating func readSE() -> Int? {
        guard let ue = readUE() else { return nil }
        let k = ue + 1
        return (k & 1) == 1 ? (k >> 1) : -(k >> 1)
    }
}
