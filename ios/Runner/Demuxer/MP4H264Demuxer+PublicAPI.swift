import Foundation

extension MP4H264Demuxer {
    /// Appends new bytes into the parser buffer. This triggers box parsing
    /// while in header-reading state, and drains any available mdat
    /// payload into H.264 access units when in streaming state.
    func append(_ data: Data) {
        emitDebug("[MP4] append \(data.count)B (buf:\(buffer.count + data.count)) st=\(state)")
        buffer.append(data)
        parseBoxesIfNeeded()
        drainMdatIfPossible()
    }

    /// Signals the end of input. The demuxer itself does not need to
    /// flush or finalize, since the display layer will continue to
    /// present the last decoded frame once no further buffers arrive.
    func finish() {
        // nothing special; display layer will keep last image
    }

    /// Registers a callback for receiving debug log messages emitted
    /// during parsing and scheduling. The callback may be invoked on
    /// the actor's isolation context.
    func setOnDebug(_ cb: ((String) -> Void)?) { self.onDebug = cb }

    /// Registers a callback that is triggered when the coded width and
    /// height are known, allowing the UI to adjust its aspect ratio to
    /// match the video stream.
    func setOnAspectRatio(_ cb: ((Double) -> Void)?) { self.onAspectRatio = cb }
}
