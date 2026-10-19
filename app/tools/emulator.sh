#!/usr/bin/env bash
# Поднимает эмулятор Android и запускает tools/smoke.sh (используется в CI).
# Всё, что происходит, пишется в файлы папки OUT — они прикладываются к релизу,
# поэтому причину неудачи видно без доступа к журналам Actions.
#   bash tools/emulator.sh MyCycle-x86_64.apk smoke
APK="$1"
OUT="$2"
mkdir -p "$OUT"
SETUP="$OUT/emu_setup.txt"
: > "$SETUP"
log() { echo "[$(date +%T)] $*" | tee -a "$SETUP"; }

SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
BIN="$SDK/cmdline-tools/latest/bin"
[ -x "$BIN/sdkmanager" ] || BIN="$(dirname "$(ls -d "$SDK"/cmdline-tools/*/bin/sdkmanager | sort -V | tail -1)")"
IMG="system-images;android-34;google_apis;x86_64"
export PATH="$SDK/platform-tools:$SDK/emulator:$PATH"

log "SDK=$SDK BIN=$BIN"
df -h / >> "$SETUP" 2>&1
ls -la /dev/kvm >> "$SETUP" 2>&1 || log "нет /dev/kvm"

log "лицензии"
yes | "$BIN/sdkmanager" --licenses > /dev/null 2>&1
log "установка эмулятора и образа $IMG"
"$BIN/sdkmanager" --install "emulator" "platform-tools" "$IMG" 2>&1 | tr '\r' '\n' > "$OUT/sdk_install.txt"
log "sdkmanager код ${PIPESTATUS[0]}"
grep -iE "warning|error|done" "$OUT/sdk_install.txt" | tail -8 >> "$SETUP"
df -h / >> "$SETUP" 2>&1
ls "$SDK/system-images/android-34/google_apis/x86_64" >> "$SETUP" 2>&1

log "создание AVD"
echo no | "$BIN/avdmanager" create avd -n smoke -k "$IMG" -d pixel_6 --force >> "$SETUP" 2>&1
log "avdmanager код $?"
"$SDK/emulator/emulator" -list-avds >> "$SETUP" 2>&1

log "запуск эмулятора"
"$SDK/emulator/emulator" -avd smoke -no-window -gpu swiftshader_indirect -noaudio \
  -no-boot-anim -no-snapshot -camera-back none -camera-front none \
  > "$OUT/emulator_log.txt" 2>&1 &
EMU=$!

adb start-server >> "$SETUP" 2>&1
booted=0
for i in $(seq 1 120); do
  if ! kill -0 "$EMU" 2>/dev/null; then
    log "процесс эмулятора завершился"
    break
  fi
  b="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
  if [ "$b" = "1" ]; then
    booted=1
    break
  fi
  sleep 5
done
log "загрузка: $booted (через ~$((i * 5)) с)"
adb devices >> "$SETUP" 2>&1
tail -40 "$OUT/emulator_log.txt" >> "$SETUP"

if [ "$booted" = "1" ]; then
  # даём системе успокоиться и разблокируем экран
  sleep 15
  adb shell input keyevent 82 || true
  adb shell settings put global window_animation_scale 1 || true
  bash "$(dirname "$0")/smoke.sh" "$APK" "$OUT" >> "$OUT/smoke_run.txt" 2>&1
  log "smoke.sh код $?"
  { echo; echo "== подготовка эмулятора"; cat "$SETUP"; } >> "$OUT/smoke_report.txt"
  adb emu kill > /dev/null 2>&1 || true
else
  {
    echo "Эмулятор не загрузился."
    cat "$SETUP"
  } > "$OUT/smoke_report.txt"
fi
kill "$EMU" 2>/dev/null || true
exit 0
