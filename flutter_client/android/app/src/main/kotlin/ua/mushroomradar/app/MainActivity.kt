package ua.mushroomradar.app

import android.content.Context
import android.os.BatteryManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Заряд батареї для «Похід»: попередження при 20 % і економний запис треку (ADR-022 §22.3 п.13).
        // Свій канал замість battery_plus: той конфліктує з wakelock_plus (dbus) на Linux.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mushroomradar/battery").setMethodCallHandler { call, result ->
            if (call.method == "level") {
                val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                result.success(bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY))
            } else {
                result.notImplemented()
            }
        }
    }
}
