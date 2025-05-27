package com.example.privastead_flutter   // adjust

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.LinkedBlockingQueue

class MainActivity : FlutterActivity() {

    companion object {
        // Each active stream gets its own queue
        private val queues = ConcurrentHashMap<Int, LinkedBlockingQueue<ByteArray>>()
        private var nextId = 1
        fun queue(id: Int) = queues[id]
        fun finish(id: Int) = queues.remove(id)?.clear()
    }

    private val CHANNEL_PREFIX = "privastead.com/android/"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_PREFIX + "byte_player")
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_PREFIX + "wifi")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connectToWifi" -> {
                        Log.e("WIFI", "Found connectToWifi request");
                        val ssid = call.argument<String>("ssid")!!
                        val passphrase = call.argument<String>("password")!!
                        Log.e("WIFI", "SSID = $ssid, passphrase = $passphrase")

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            Log.e("WIFI", "Using new version of SSID connect");

                            val builder = WifiNetworkSpecifier.Builder();

                            builder.setSsid(ssid);
                            builder.setIsHiddenSsid(true);
                            builder.setWpa2Passphrase(passphrase);

                            val wifiNetworkSpecifier = builder.build();
                            val networkRequestBuilder = NetworkRequest.Builder();
                            networkRequestBuilder.addTransportType(NetworkCapabilities.TRANSPORT_WIFI);
                            networkRequestBuilder.setNetworkSpecifier(wifiNetworkSpecifier);

                            val networkRequest = networkRequestBuilder.build();
                            val cm = applicationContext
                                .getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager;
                            val callback = object : ConnectivityManager.NetworkCallback() {
                                override fun onAvailable(network: Network) {
                                    cm.bindProcessToNetwork(network);
                                    result.success("connected");
                                    cm.unregisterNetworkCallback(this);
                                }

                                override fun onUnavailable() {
                                    result.success("failed");
                                    cm.unregisterNetworkCallback(this);
                                }
                            }
                            cm.requestNetwork(networkRequest, callback);
                        } else { // Below version 10
                            Log.e("WIFI", "Using old version of SSID connect");
                            val wifiMgr =
                                context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                            val config = WifiConfiguration().apply {
                                SSID = ssid
                                preSharedKey = passphrase
                            }
                            val netId = wifiMgr.addNetwork(config)
                            val success = wifiMgr.enableNetwork(netId, true)
                            result.success(if (success) "connected" else "failed")
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        // Register platform view for byte player
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "byte_player_view",
                BytePlayerViewFactory()
            )
    }
}
