"""Stage files for upload-artifact, which creates the downloadable ZIP itself."""
from pathlib import Path
import hashlib
import sys
import shutil

root = Path(__file__).resolve().parents[1]
platform = sys.argv[1]
if platform not in ('android', 'ios'):
    raise SystemExit('Expected android or ios')
binary = (root / 'app/build/app/outputs/flutter-apk/app-release.apk' if platform == 'android'
          else root / 'dist/ANT-BMS-unsigned.ipa')
if not binary.is_file():
    raise SystemExit(f'Missing binary: {binary}')
name = 'ANT-BMS-test.apk' if platform == 'android' else binary.name
notes = ('Android 11+ 测试版，使用测试签名，不用于正式发布。\n'
         '不同 CI 构建的测试签名可能不同，不能保证覆盖安装；卸载会清除本机数据，请先导出记录。\n'
         if platform == 'android' else 'iOS 未签名测试版，需自行使用有效证书重新签名后安装。\n')
digest = hashlib.sha256(binary.read_bytes()).hexdigest()
target = root / 'dist' / f'{platform}-artifact'
target.mkdir(parents=True, exist_ok=True)
shutil.copyfile(binary, target / name)
(target / 'README.txt').write_text(notes, encoding='utf-8')
(target / 'SHA256SUMS.txt').write_text(f'{digest}  {name}\n', encoding='utf-8')
if hashlib.sha256((target / name).read_bytes()).hexdigest() != digest:
    raise SystemExit('Staged binary integrity check failed')
print(target)
