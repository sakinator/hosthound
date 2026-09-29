package com.playtorrio.nuvio.addon

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.playtorrio.nuvio.addon/player"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playStream" -> {
                    val url = call.argument<String>("url")
                    val title = call.argument<String>("title")
                    val packageName = call.argument<String>("package")
                    val forceChooser = call.argument<Boolean>("forceChooser") ?: false

                    if (url.isNullOrEmpty()) {
                        result.error("INVALID_URL", "URL is null or empty", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val mimeType = when {
                            url.contains(".m3u8", ignoreCase = true) -> "application/x-mpegURL"
                            url.contains(".mpd", ignoreCase = true) -> "application/dash+xml"
                            else -> "video/*"
                        }

                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(Uri.parse(url), mimeType)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            if (!title.isNullOrEmpty()) {
                                putExtra("title", title)
                            }
                        }

                        if (!packageName.isNullOrEmpty()) {
                            val resolvedPackage = resolvePackage(packageName)
                            if (resolvedPackage != null) {
                                intent.setPackage(resolvedPackage)
                                startActivity(intent)
                                result.success(true)
                            } else {
                                result.error("APP_NOT_INSTALLED", "$packageName is not installed", null)
                            }
                        } else if (forceChooser) {
                            val chooser = Intent.createChooser(intent, "Play with...")
                            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(chooser)
                            result.success(true)
                        } else {
                            startActivity(intent)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("LAUNCH_ERROR", e.message, null)
                    }
                }
                "checkInstalledPlayers" -> {
                    val players = listOf(
                        "org.videolan.vlc",
                        "com.brouken.player",
                        "com.mxtech.videoplayer.ad",
                        "com.mxtech.videoplayer.pro",
                        "is.xyz.mpv",
                        "org.courville.nova",
                        "dev.anilbeesetti.nextplayer"
                    )
                    val installed = mutableListOf<String>()
                    for (pkg in players) {
                        if (isInstalled(pkg)) {
                            installed.add(pkg)
                        }
                    }
                    result.success(installed)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun resolvePackage(packageName: String): String? {
        if (packageName == "com.mxtech.videoplayer") {
            if (isInstalled("com.mxtech.videoplayer.pro")) return "com.mxtech.videoplayer.pro"
            if (isInstalled("com.mxtech.videoplayer.ad")) return "com.mxtech.videoplayer.ad"
            return null
        }
        return if (isInstalled(packageName)) packageName else null
    }

    private fun isInstalled(packageName: String): Boolean {
        return try {
            packageManager.getPackageInfo(packageName, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        } catch (_: Exception) {
            false
        }
    }
}
