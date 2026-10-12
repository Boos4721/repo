import '../app/lib/device_profile.dart';

void expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  expect(remainingTime(null) == '--', 'absent field');
  expect(remainingTime(0) == '无可用估算', 'zero is not empty');
  expect(remainingTime(1561) == '1天 2小时 1分钟', 'device minutes');
  expect(remainingTime(60) == '1小时', 'whole hour');
  expect(remainingTime(1) == '1分钟', 'single minute');
  expect(temperatureText(-40) == '-40 °C', 'retain signed sensor value');
  expect(temperatureStatus(-40).contains('疑似'), 'sensor state is uncertain');
  expect(
      temperatureStatus(-39) == '原始读数', 'do not suppress negative temperature');
  expect(DeviceProfile.target.match('ANT@BLE24CBUB-5P4P').contains('固件待读取'),
      'name is not firmware verification');
  expect(DeviceProfile.target.match('ANT@BLE24CBUB-XXXX').contains('同系列'),
      'family match');
  expect(DeviceProfile.target.match('ANT@OTHER').contains('未匹配'),
      'generic device');
  expect(
      DeviceProfile.target
          .match('ANT@BLE24CBUB-5P4P', demo: true)
          .contains('未验证'),
      'demo not hardware');
  expect(
      DeviceProfile.target.differences(
              {'cells': List.filled(20, 0), 'capacity_ah': 113}).length ==
          2,
      'mismatched pack');
  expect(
      DeviceProfile.target.differences(
          {'cells': List.filled(21, 0), 'capacity_ah': 170}).isEmpty,
      'matching pack');
  expect(permissionText(1).contains('实时监控'), 'level1');
  expect(permissionText(3).contains('仅开放读取'), 'write still gated');
  print('16 profile/presentation scenarios passed.');
}
