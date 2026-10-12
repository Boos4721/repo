/// Screenshot-derived target metadata; never presented as live device identity.
class DeviceProfile {
  final String name, hardware, firmware;
  final int cells;
  final double capacityAh;
  const DeviceProfile({
    required this.name,
    required this.hardware,
    required this.firmware,
    required this.cells,
    required this.capacityAh,
  });
  static const target = DeviceProfile(
    name: 'ANT@BLE24CBUB-5P4P',
    hardware: '24ZHE6TB420A',
    firmware: '24CBUB00-241008A',
    cells: 21,
    capacityAh: 170,
  );
  String match(String actualName, {bool demo = false}) {
    if (demo) return '截图参考演示 · 未验证真机';
    final actual = actualName.toUpperCase();
    if (actual == name.toUpperCase()) return '名称与适配目标一致 · 固件待读取';
    if (actual.startsWith('ANT@BLE24CBUB-')) return '同系列设备 · 固件兼容性待验证';
    return '通用 ANT 读取 · 未匹配适配目标';
  }

  List<String> differences(Map<String, dynamic>? data) {
    if (data == null) return [];
    final result = <String>[];
    final actualCells = (data['cells'] as List).length;
    if (actualCells != cells)
      result.add('设备返回 $actualCells 串，与档案 $cells 串不同，以设备数据为准。');
    final actualCapacity = (data['capacity_ah'] as num).toDouble();
    if ((actualCapacity - capacityAh).abs() > 0.5)
      result.add(
        '设备容量 ${actualCapacity.toStringAsFixed(1)}Ah 与档案 ${capacityAh.toStringAsFixed(0)}Ah 不同。',
      );
    return result;
  }
}

String temperatureText(num? value) =>
    value == null ? '--' : '${value.toStringAsFixed(0)} °C';
String temperatureStatus(num? value) => value == null
    ? '设备未返回'
    : value == -40
    ? '疑似未接探头 · 保留原值'
    : '原始读数';
String remainingTime(num? minutes) {
  if (minutes == null) return '--';
  if (minutes <= 0) return '无可用估算';
  final n = minutes.toInt(),
      days = n ~/ 1440,
      hours = (n % 1440) ~/ 60,
      mins = n % 60;
  return [
    if (days > 0) '$days天',
    if (hours > 0) '$hours小时',
    if (mins > 0) '$mins分钟',
  ].join(' ');
}

String permissionText(num? level) => level == null
    ? '权限未知'
    : level >= 3
    ? '${level.toInt()}级 · 设备允许写入，本版仅开放读取'
    : level >= 2
    ? '${level.toInt()}级 · 可读取参数'
    : level >= 1
    ? '${level.toInt()}级 · 实时监控'
    : '0级 · 仅尝试读取实时数据';
