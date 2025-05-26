package com.example.privastead_flutter

import android.content.Context
import android.graphics.SurfaceTexture
import android.util.Log
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import android.widget.ProgressBar
import androidx.core.view.isVisible
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.plugin.platform.PlatformView
import java.util.concurrent.LinkedBlockingQueue

class BytePlayerPlatformView(
    ctx: Context,
    streamId: Int
) : PlatformView {

    private val container: FrameLayout
    private val player: ExoPlayer
    private val spinner: ProgressBar

    init {
        Log.d("BytePV", "▶️ BytePlayerPlatformView ctor for stream $streamId")

        // Grab the shared byte‐queue
        val q: LinkedBlockingQueue<ByteArray> =
            MainActivity.queue(streamId) ?: error("Queue missing")

        // Build an ExoPlayer instance
        val dsFactory = DataSource.Factory { ByteQueueDataSource(q) }
        val mediaSrc = ProgressiveMediaSource.Factory(dsFactory)
            .createMediaSource(MediaItem.fromUri("queue://dummy"))

        player = ExoPlayer.Builder(ctx)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dsFactory))
            .build().apply {
                setMediaSource(mediaSrc, 0)
                playWhenReady = true
            }

        // Create a TextureView for video output
        val texture = TextureView(ctx).apply {
            surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                override fun onSurfaceTextureAvailable(
                    surfaceTexture: SurfaceTexture,
                    width: Int,
                    height: Int
                ) {
                    Log.d("BytePV", "texture available, attaching to player")
                    player.setVideoSurface(Surface(surfaceTexture))
                    // Now that the surface exists, prepare the stream
                    player.prepare()
                }

                override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, w: Int, h: Int) {}
                override fun onSurfaceTextureDestroyed(st: SurfaceTexture) = true
                override fun onSurfaceTextureUpdated(st: SurfaceTexture) {}
            }
        }

        // A little spinner while the first frame buffers
        spinner = ProgressBar(ctx).apply { isIndeterminate = true }

        container = FrameLayout(ctx).apply {
            setBackgroundColor(0xFF000000.toInt())
            addView(
                texture, FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            )
            addView(spinner, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply { gravity = Gravity.CENTER })
        }

        // Listen for first‐frame
        player.addListener(object : Player.Listener {
            override fun onRenderedFirstFrame() {
                Log.d("BytePV", "first frame rendered ✓")
                spinner.isVisible = false
            }

            override fun onPlayerError(error: PlaybackException) {
                Log.e("BytePV", "PLAYER ERROR", error)
            }
        })
    }

    override fun getView(): View {
        Log.d("BytePV", "▶️ getView() called; returning container")
        return container
    }

    override fun dispose() {
        Log.d("BytePV", "▶️ dispose() called")
        player.release()
    }
}
