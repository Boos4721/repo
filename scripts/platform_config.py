from pathlib import Path
import plistlib
root=Path(__file__).resolve().parents[1]/'app'
manifest=root/'android/app/src/main/AndroidManifest.xml'
if manifest.exists():
    text=manifest.read_text()
    if 'android.permission.BLUETOOTH_SCAN' not in text:
        permissions='''    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
'''
        text=text.replace('    <application',permissions+'    <application',1)
    text=text.replace('<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />', '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />')
    if 'android.permission.ACCESS_COARSE_LOCATION' not in text:
        text=text.replace('    <application', '    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />\n    <application', 1)
    manifest.write_text(text)
for name in ['build.gradle.kts','build.gradle']:
    gradle=root/'android/app'/name
    if gradle.exists():
        text=gradle.read_text().replace('minSdk = flutter.minSdkVersion','minSdk = 26').replace('minSdkVersion flutter.minSdkVersion','minSdkVersion 26')
        gradle.write_text(text)
info=root/'ios/Runner/Info.plist'
if info.exists():
    with info.open('rb') as f:data=plistlib.load(f)
    data['CFBundleDisplayName']='ANT BMS'
    data['NSBluetoothAlwaysUsageDescription']='用于连接你的蚂蚁保护板并读取电池数据。'
    data['NSBluetoothPeripheralUsageDescription']='用于连接你的蚂蚁保护板并读取电池数据。'
    data['NSLocationWhenInUseUsageDescription']='仅在开启 GPS 车速时使用手机定位显示实时车速，不保存或上传位置。'
    with info.open('wb') as f:plistlib.dump(data,f)
for name in ['Debug.xcconfig','Release.xcconfig']:
    config=root/'ios/Flutter'/name
    if config.exists() and 'Rust.xcconfig' not in config.read_text():
        with config.open('a') as f:f.write('\n#include "Rust.xcconfig"\n')

# The app only needs when-in-use location; do not compile the always-permission path.
podfile=root/'ios/Podfile'
if podfile.exists():
    text=podfile.read_text()
    marker='flutter_additional_ios_build_settings(target)'
    if 'BYPASS_PERMISSION_LOCATION_ALWAYS=1' not in text and marker in text:
        text=text.replace(marker, marker+'''
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)']
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] << 'BYPASS_PERMISSION_LOCATION_ALWAYS=1'
    end
''',1)
        podfile.write_text(text)
print('Android/iOS permissions and native-library configuration updated.')

# Flutter create generates a counter sample test which does not describe our app.
sample=root/'test/widget_test.dart'
if sample.exists() and 'Counter increments smoke test' in sample.read_text() and 'MyApp' in sample.read_text():
    sample.unlink()
