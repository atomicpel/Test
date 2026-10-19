package ru.atomicpel.cycle_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import java.io.File
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * FlutterFragmentActivity нужна для входа по отпечатку (local_auth).
 * Свой канал: виджет, «Поделиться», настройки приложения,
 * версия приложения и установка обновления, скачанного с вашего сервера.
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
                        "appVersion" -> {
                            @Suppress("DEPRECATION")
                            val pi = packageManager.getPackageInfo(packageName, 0)
                            val code = if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode
                            else @Suppress("DEPRECATION") pi.versionCode.toLong()
                            result.success(mapOf("name" to (pi.versionName ?: ""), "code" to code))
                        }
                        "installApk" -> {
                            if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                                // Android попросит разрешить установку из этого приложения
                                val i = Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                )
                                startActivity(i)
                                result.success("permission")
                            } else {
                                val src = File(call.argument<String>("path") ?: "")
                                val dir = File(cacheDir, "updates").apply { mkdirs() }
                                val apk = File(dir, "MyCycle.apk")
                                if (src.canonicalPath != apk.canonicalPath) src.copyTo(apk, overwrite = true)
                                val uri = FileProvider.getUriForFile(this, "$packageName.apkprovider", apk)
                                val i = Intent(Intent.ACTION_VIEW)
                                    .setDataAndType(uri, "application/vnd.android.package-archive")
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(i)
                                result.success("ok")
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("native", t.message, null)
                }
            }
    }
}
