#!/usr/bin/env bash
# Самопроверка релизного APK на эмуляторе Android (запускается в CI).
# Приложение стартует в режиме /smoke: пример данных, все напоминания
# включены, через 8 секунд — пробное уведомление.
APK="$1"
OUT="$2"
PKG=ru.atomicpel.cycle_app
mkdir -p "$OUT"
set -x
adb wait-for-device
adb shell getprop ro.build.version.release
adb install -r "$APK" > "$OUT/install.txt" 2>&1
cat "$OUT/install.txt"
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS || true
adb logcat -c
adb shell am start -W -n $PKG/.MainActivity --es route /smoke
sleep 30
adb exec-out screencap -p > "$OUT/smoke_1_home.png"
adb shell input swipe 540 1700 540 700 500
sleep 3
adb exec-out screencap -p > "$OUT/smoke_2_scrolled.png"
adb shell cmd statusbar expand-notifications
sleep 3
adb exec-out screencap -p > "$OUT/smoke_3_notifications.png"
adb shell cmd statusbar collapse
adb shell dumpsys alarm > "$OUT/alarm_full.txt" 2>&1
grep -i -A3 "$PKG" "$OUT/alarm_full.txt" | head -120 > "$OUT/alarms.txt"
adb shell dumpsys appwidget > "$OUT/appwidget_full.txt" 2>&1
grep -i -B2 -A8 "CycleWidget" "$OUT/appwidget_full.txt" | head -60 > "$OUT/widget.txt"
adb shell dumpsys notification --noredact > "$OUT/notif_full.txt" 2>&1
grep -i -A6 "pkg=$PKG" "$OUT/notif_full.txt" | head -80 > "$OUT/notifications.txt"
adb shell pidof $PKG > "$OUT/pid.txt" 2>&1 || echo "not running" > "$OUT/pid.txt"
adb shell dumpsys package $PKG | grep -E "versionName|POST_NOTIFICATIONS|USE_EXACT_ALARM|USE_BIOMETRIC" > "$OUT/package.txt" 2>&1
adb shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp" > "$OUT/focus.txt" 2>&1
adb logcat -d > "$OUT/logcat_full.txt"
grep -E "FATAL|AndroidRuntime|Exception|Error|flutter" "$OUT/logcat_full.txt" | head -300 > "$OUT/logcat.txt"
# Сводка в один файл
{
  echo "== pid"; cat "$OUT/pid.txt"
  echo "== focus"; cat "$OUT/focus.txt"
  echo "== package"; cat "$OUT/package.txt"
  echo "== install"; cat "$OUT/install.txt"
  echo "== alarms"; cat "$OUT/alarms.txt"
  echo "== widget"; cat "$OUT/widget.txt"
  echo "== notifications"; cat "$OUT/notifications.txt"
  echo "== logcat"; cat "$OUT/logcat.txt"
} > "$OUT/smoke_report.txt"
ls -la "$OUT"
exit 0
