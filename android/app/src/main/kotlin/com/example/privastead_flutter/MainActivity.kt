package com.example.privastead_flutter   // adjust

import android.content.Intent
import android.os.Bundle
import androidx.annotation.UiThread
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.LinkedBlockingQueue
import com.example.privastead_flutter.BytePlayerViewFactory

class MainActivity : FlutterActivity() {

    companion object {
        // Each active stream gets its own queue
        private val queues = ConcurrentHashMap<Int, LinkedBlockingQueue<ByteArray>>()
        private var nextId = 1
        fun queue(id: Int) = queues[id]
        fun finish(id: Int) = queues.remove(id)?.clear()
    }

    private val CHANNEL = "privastead/byte_player"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "createStream" -> {
                        val id = nextId++
                        queues[id] = LinkedBlockingQueue()
                        result.success(id)
                    }

                    "pushBytes" -> {
                        val id = call.argument<Int>("id")!!
                        val bytes = call.argument<ByteArray>("bytes")!!
                        queue(id)?.offer(bytes)
                        result.success(null)
                    }

                    "finishStream" -> {
                        val id = call.argument<Int>("id")!!
                        finish(id)
                        result.success(null)
                    }

                    "qLen" -> {
                        val id = call.argument<Int>("id")!!
                        result.success(queue(id)?.size ?: 0)
                    }

                    else -> result.notImplemented()
                }
            }

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "byte_player_view",
                BytePlayerViewFactory()
            )
    }
}
