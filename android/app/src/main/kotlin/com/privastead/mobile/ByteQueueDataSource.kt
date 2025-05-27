package com.privastead.mobile

import androidx.media3.common.C
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSpec
import java.util.concurrent.LinkedBlockingQueue

class ByteQueueDataSource(
    private val q: LinkedBlockingQueue<ByteArray>
) : BaseDataSource(false) {

    private var internal = ByteArray(0)
    private var finished = false

    override fun open(dataSpec: DataSpec): Long {
        android.util.Log.d("ByteDS", "open() called, uri=${dataSpec.uri}")
        return C.LENGTH_UNSET.toLong()
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (internal.isEmpty()) {
            if (finished && q.isEmpty()) return C.RESULT_END_OF_INPUT
            internal = q.take()
            android.util.Log.d("ByteDS", "take() got ${internal.size} bytes")
            if (internal.isEmpty()) {
                finished = true
                return C.RESULT_END_OF_INPUT
            }
        }
        val toCopy = minOf(length, internal.size)
        System.arraycopy(internal, 0, buffer, offset, toCopy)
        internal = internal.copyOfRange(toCopy, internal.size)
        return toCopy
    }

    override fun close() {
        android.util.Log.d("ByteDS", "close()")
    }

    override fun getUri() = null
}
