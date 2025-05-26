package com.example.privastead_flutter

import android.content.Context
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import android.util.Log
import io.flutter.plugin.common.StandardMessageCodec

class BytePlayerViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        val streamId = (args as Map<*, *>)["streamId"] as Int
        Log.d("BytePV","BytePlayerViewFactory.create() id=$id")
        return BytePlayerPlatformView(context, streamId)
    }
}
