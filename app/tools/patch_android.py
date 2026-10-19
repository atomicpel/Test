"""Донастройка Android-проекта после `flutter create` (запускается в CI).

- разрешения и приёмники для уведомлений, виджет, отпечаток;
- MainActivity на FlutterFragmentActivity + свой канал;
- без R8/сжатия: из-за него были вылеты с NoSuchMethod/ClassNotFound;
- desugaring (нужен flutter_local_notifications), minSdk 24;
- при необходимости поднимает версию Android Gradle Plugin.
"""
import re
import shutil
import sys
from pathlib import Path

app = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
android = app / 'android'
main = android / 'app' / 'src' / 'main'
overlay = app / 'android_overlay'


def log(msg):
    print(f'[patch] {msg}')


# ---------- AndroidManifest.xml
man_p = main / 'AndroidManifest.xml'
man = man_p.read_text()
perms = [
    'android.permission.INTERNET',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.VIBRATE',
    'android.permission.USE_EXACT_ALARM',
    'android.permission.USE_BIOMETRIC',
    'android.permission.REQUEST_INSTALL_PACKAGES',
]
block = ''
for p in perms:
    if p not in man:
        block += f'    <uses-permission android:name="{p}"/>\n'
if 'SCHEDULE_EXACT_ALARM' not in man:
    block += ('    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" '
              'android:maxSdkVersion="32"/>\n')
man = re.sub(r'(<application)', block + r'    \1', man, count=1)
man = man.replace('android:label="cycle_app"', 'android:label="Мой цикл"')

receivers = '''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
        <receiver android:name=".CycleWidgetProvider" android:exported="true" android:label="Мой цикл">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/cycle_widget_info" />
        </receiver>
        <provider
            android:name=".ApkFileProvider"
            android:authorities="${applicationId}.apkprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/apk_paths" />
        </provider>
        <!-- Impeller выключен: на части Xiaomi/HyperOS он давал чёрный экран -->
        <meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="false" />
    </application>'''
if 'ScheduledNotificationReceiver' not in man:
    man = man.replace('</application>', receivers.lstrip('\n'), 1)
man_p.write_text(man)
log('manifest ok')

# ---------- Kotlin и ресурсы
kt_dir = next((main / 'kotlin').rglob('MainActivity.kt')).parent
for f in (overlay / 'kotlin').glob('*.kt'):
    shutil.copy(f, kt_dir / f.name)
    log(f'kotlin {f.name} -> {kt_dir}')
for sub in (overlay / 'res').iterdir():
    dst = main / 'res' / sub.name
    dst.mkdir(parents=True, exist_ok=True)
    for f in sub.iterdir():
        shutil.copy(f, dst / f.name)
        log(f'res {sub.name}/{f.name}')

# ---------- app/build.gradle(.kts)
gk = android / 'app' / 'build.gradle.kts'
if gk.exists():
    g = gk.read_text()
    if 'isCoreLibraryDesugaringEnabled' not in g:
        g = g.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
    g = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24', g)
    if 'isMinifyEnabled' not in g:
        g = re.sub(r'(release\s*\{)',
                   r'\1\n            isMinifyEnabled = false\n            isShrinkResources = false', g, count=1)
    if 'desugar_jdk_libs' not in g:
        g += ('\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n'
              '    implementation("androidx.core:core:1.13.1")\n}\n')
    gk.write_text(g)
    log('build.gradle.kts ok')
else:
    gg = android / 'app' / 'build.gradle'
    g = gg.read_text()
    if 'coreLibraryDesugaringEnabled' not in g:
        g = g.replace('compileOptions {', 'compileOptions {\n        coreLibraryDesugaringEnabled true', 1)
    g = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 24', g)
    g = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24', g)
    if 'minifyEnabled' not in g:
        g = re.sub(r'(release\s*\{)', r'\1\n            minifyEnabled false\n            shrinkResources false', g, count=1)
    if 'desugar_jdk_libs' not in g:
        g += ("\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n"
              "    implementation 'androidx.core:core:1.13.1'\n}\n")
    gg.write_text(g)
    log('build.gradle ok')

# ---------- gradle.properties: без сжатия кода
gp = android / 'gradle.properties'
props = gp.read_text() if gp.exists() else ''
if 'shrink=' not in props:
    props += '\nshrink=false\n'
gp.write_text(props)

# ---------- версия Android Gradle Plugin (flutter_local_notifications 22 требует 8.11.1+)
def ver(s):
    return tuple(int(x) for x in re.findall(r'\d+', s)[:3])

for sp in [android / 'settings.gradle.kts', android / 'settings.gradle']:
    if not sp.exists():
        continue
    s = sp.read_text()
    m = re.search(r'id\(?\s*"com\.android\.application"\s*\)?\s+version\s+"([\d.]+)"', s)
    if m:
        cur = m.group(1)
        log(f'AGP {cur}')
        if ver(cur) < (8, 11, 1):
            s = s.replace(f'"{cur}"', '"8.11.1"', 1)
            sp.write_text(s)
            wp = android / 'gradle' / 'wrapper' / 'gradle-wrapper.properties'
            w = wp.read_text()
            m2 = re.search(r'gradle-([\d.]+)-(all|bin)\.zip', w)
            if m2 and ver(m2.group(1)) < (8, 13):
                w = w.replace(m2.group(0), 'gradle-8.14.3-all.zip')
                wp.write_text(w)
                log('gradle wrapper -> 8.14.3')
            log('AGP -> 8.11.1')
    km = re.search(r'id\(?\s*"org\.jetbrains\.kotlin\.android"\s*\)?\s+version\s+"([\d.]+)"', s)
    if km:
        log(f'Kotlin {km.group(1)}')

print(man)
