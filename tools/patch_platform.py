"""Run after `flutter create`: adds Android permissions/service + macOS entitlements."""
import os, re
def rw(path, fn):
    if os.path.exists(path):
        s = open(path).read(); open(path, 'w').write(fn(s))
perms = ["INTERNET","ACCESS_WIFI_STATE","CHANGE_WIFI_STATE","CHANGE_WIFI_MULTICAST_STATE","ACCESS_NETWORK_STATE",
 "FOREGROUND_SERVICE","FOREGROUND_SERVICE_DATA_SYNC","POST_NOTIFICATIONS","WAKE_LOCK","REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"]
def manifest(s):
    if 'ForegroundService' in s: return s
    p = ''.join(f'    <uses-permission android:name="android.permission.{x}"/>\n' for x in perms)
    s = s.replace('<application', p + '    <application', 1)
    svc = '<service android:name="com.pravera.flutter_foreground_task.service.ForegroundService" android:foregroundServiceType="dataSync" android:exported="false"/>\n    </application>'
    return s.replace('</application>', svc, 1)
rw('android/app/src/main/AndroidManifest.xml', manifest)
keys = {"com.apple.security.network.client":1,"com.apple.security.network.server":1,
 "com.apple.security.files.downloads.read-write":1,"com.apple.security.files.user-selected.read-write":1}
def ent(s):
    add = ''.join(f'\t<key>{k}</key>\n\t<true/>\n' for k in keys if k not in s)
    return s[:s.rindex('</dict>')] + add + s[s.rindex('</dict>'):]
for f in ('DebugProfile','Release'):
    rw(f'macos/Runner/{f}.entitlements', ent)
rw('macos/Runner/Info.plist', lambda s: s if 'NSAppSleepDisabled' in s else
   s[:s.rindex('</dict>')] + '\t<key>NSAppSleepDisabled</key>\n\t<true/>\n' + s[s.rindex('</dict>'):])
print('patched')
