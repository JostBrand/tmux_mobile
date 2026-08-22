package de.jostbrandstetter.tmux_mobile

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var intentChannel: MethodChannel? = null
    private val pendingTexts = mutableListOf<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "tmux_mobile/wakelock",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepScreenOn" -> {
                    val enabled = call.arguments as? Boolean ?: false
                    if (enabled) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                "setSecureScreen" -> {
                    val enabled = call.arguments as? Boolean ?: false
                    if (enabled) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        intentChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "tmux_mobile/intents",
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    // Dart side asks for texts received before the engine was up.
                    "drainPendingTexts" -> {
                        val texts = pendingTexts.toList()
                        pendingTexts.clear()
                        result.success(texts)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // Share OUT: hand text to the Android share sheet.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "tmux_mobile/share",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareText" -> {
                    val text = call.arguments as? String ?: ""
                    val sendIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    startActivity(Intent.createChooser(sendIntent, "Share"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Texts received before the engine was ready (launch via share).
        for (text in pendingTexts) {
            intentChannel?.invokeMethod("onText", text)
        }
        pendingTexts.clear()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        val text = when (intent.action) {
            Intent.ACTION_PROCESS_TEXT ->
                intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
            Intent.ACTION_SEND ->
                if (intent.type == "text/plain") intent.getStringExtra(Intent.EXTRA_TEXT) else null
            else -> null
        } ?: return
        intentChannel?.invokeMethod("onText", text) ?: pendingTexts.add(text)
    }
}
