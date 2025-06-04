package com.privastead.mobile

import android.content.Context
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.BinaryMessenger
import android.util.Log
import io.flutter.plugin.common.StandardMessageCodec

class BytePlayerViewFactory(
    private val messenger: BinaryMessenger
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        val streamId = (args as Map<*, *>)["streamId"] as Int
        Log.d("BytePV","BytePlayerViewFactory.create() id=$id")
        return BytePlayerPlatformView(context, streamId, messenger)
    }
}
