package com.clipsync.mobile_build

import com.clipsync.mobile_build.withdraw.WithdrawNotifyPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(SlipObserverPlugin())
        flutterEngine.plugins.add(WithdrawNotifyPlugin())
    }
}
