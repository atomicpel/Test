package ru.atomicpel.cycle_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * FlutterFragmentActivity нужна для входа по отпечатку (local_auth).
 * Свой канал: виджет, «Поделиться», настройки приложения.
 */
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ru.atomicpel.cycle/native")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "updateWidget" -> {
                            val e = getSharedPreferences(CycleWidgetProvider.PREFS, Context.MODE_PRIVATE).edit()
                            e.putString("mode", call.argument<String>("mode") ?: "none")
                            for (k in listOf("lastStart", "lastEnd", "periodLen", "nextStart", "cycleLen", "lmp", "ring")) {
                                val v = call.argument<Any>(k)
                                e.putLong(k, (v as? Number)?.toLong() ?: -1L)
                            }
                            e.putBoolean("secret", call.argument<Boolean>("secret") ?: false)
                            e.apply()
                            CycleWidgetProvider.updateAll(this)
                            result.success(null)
                        }
                        "share" -> {
                            val i = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "")
                                putExtra(Intent.EXTRA_SUBJECT, call.argument<String>("subject") ?: "")
                            }
                            startActivity(Intent.createChooser(i, null))
                            result.success(null)
                        }
                        "openAppSettings" -> {
                            val i = Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName")
                            )
                            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("native", t.message, null)
                }
            }
    }
}
