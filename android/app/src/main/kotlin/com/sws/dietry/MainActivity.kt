package com.sws.dietry

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity statt FlutterActivity: benötigt vom health-Package,
// damit der ActivityResultLauncher für Health Connect Permissions registriert wird.
class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.sws.dietry/deeplink"
    private var startString: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        val action = intent.action
        val data = intent.data

        if (Intent.ACTION_VIEW == action && data != null) {
            startString = data.toString()
            println("🔗 Deep Link empfangen: $startString")
        }
    }

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInitialLink") {
                result.success(startString)
            } else {
                result.notImplemented()
            }
        }
    }
}
