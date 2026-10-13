"""Wrap platform binaries with installation notes and integrity checks."""
from pathlib import Path
import hashlib
import sys
import zipfile

root = Path(__file__).resolve().parents[1]
platform = sys.argv[1]
if platform not in ('android', 'ios'):
    raise SystemExit('Expected android or ios')
binary = (root / 'app/build/app/outputs/flutter-apk/app-release.apk' if platform == 'android'
          else root / 'dist/ANT-BMS-unsigned.ipa')
if not binary.is_file():
    raise SystemExit(f'Missing binary: {binary}')
name = 'ANT-BMS-test.apk' if platform == 'android' else binary.name
notes = ('Android 8.0+ 测试版，使用测试签名，不用于正式发布。\n'
         '不同 CI 构建的测试签名可能不同，不能保证覆盖安装；卸载会清除本机数据，请先导出记录。\n'
         if platform == 'android' else 'iOS 未签名测试版，需自行使用有效证书重新签名后安装。\n')
digest = hashlib.sha256(binary.read_bytes()).hexdigest()
target = root / 'dist' / f'ANT-BMS-{platform}-test.zip'
target.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as archive:
    archive.write(binary, name)
    archive.writestr('README.txt', notes)
    archive.writestr('SHA256SUMS.txt', f'{digest}  {name}\n')
with zipfile.ZipFile(target) as archive:
    if archive.testzip() is not None:
        raise SystemExit('ZIP integrity check failed')
print(target)
