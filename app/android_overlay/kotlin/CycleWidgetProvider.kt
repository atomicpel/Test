package ru.atomicpel.cycle_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.util.TimeZone

/**
 * Виджет «Мой цикл»: кольцо и сколько дней до месячных.
 * Числа пересчитываются здесь каждый день по датам, которые
 * передало приложение, поэтому виджет не устаревает.
 */
class CycleWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, build(context))
    }

    companion object {
        const val PREFS = "cycle_widget"

        private fun todayEpoch(): Long {
            val now = System.currentTimeMillis()
            val off = TimeZone.getDefault().getOffset(now)
            return Math.floorDiv(now + off, 86400000L)
        }

        fun build(context: Context): RemoteViews {
            val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val mode = p.getString("mode", "none") ?: "none"
            val secret = p.getBoolean("secret", false)
            val today = todayEpoch()
            var big = "—"
            var small = "Откройте приложение"
            if (mode == "preg") {
                val lmp = p.getLong("lmp", -1)
                if (lmp >= 0) {
                    big = "${(today - lmp) / 7} нед."
                    small = if (secret) "неделя" else "беременности"
                }
            } else if (mode == "cycle") {
                val lastStart = p.getLong("lastStart", -1)
                val lastEnd = p.getLong("lastEnd", -1)
                var cycleLen = p.getLong("cycleLen", 28)
                if (cycleLen < 15) cycleLen = 28
                if (lastStart >= 0 && today in lastStart..lastEnd) {
                    big = "${today - lastStart + 1}-й день"
                    small = if (secret) "отметка" else "месячные"
                } else if (lastStart >= 0) {
                    val left = lastStart + cycleLen - today
                    when {
                        left > 0 -> {
                            big = "$left дн."
                            small = if (secret) "до отметки" else "до месячных"
                        }
                        left == 0L -> {
                            big = "Сегодня"
                            small = if (secret) "отметка" else "ожидаются месячные"
                        }
                        else -> {
                            big = "+${-left} дн."
                            small = if (secret) "позже срока" else "задержка"
                        }
                    }
                }
            } else {
                small = "Отметьте месячные"
            }
            val v = RemoteViews(context.packageName, R.layout.cycle_widget)
            v.setTextViewText(R.id.widget_big, big)
            v.setTextViewText(R.id.widget_small, small)
            val ring = p.getLong("ring", -1)
            if (ring != -1L) v.setInt(R.id.widget_ring, "setColorFilter", ring.toInt())
            val intent = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val pi = PendingIntent.getActivity(
                context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            v.setOnClickPendingIntent(R.id.widget_root, pi)
            return v
        }

        fun updateAll(context: Context) {
            val m = AppWidgetManager.getInstance(context)
            val ids = m.getAppWidgetIds(ComponentName(context, CycleWidgetProvider::class.java))
            for (id in ids) m.updateAppWidget(id, build(context))
        }
    }
}
