import 'dart:convert';
import 'dart:io';
import '../app/lib/device_history.dart';

void check(bool value, String label) { if (!value) throw StateError(label); }
Future<void> main() async {
  final history = DeviceHistory();
  final time = DateTime.utc(2026, 10, 13);
  history.remember(SavedDevice('a', '真实 ANT', 'ant', 'auxiliaryA', time));
  history.remember(SavedDevice('b', 'BlueBabeQC6528', 'lanbao', 'standard', time));
  history.remember(SavedDevice('a', '真实 ANT', 'ant', 'standard', time.add(const Duration(seconds: 1))));
  check(history.devices.length == 2 && history.autoId == 'a', 'deduplicate and most recent target');
  final copy = DeviceHistory()..decode(history.encode());
  check(copy.devices.first.id == 'a' && copy.find('b')?.family == 'lanbao', 'roundtrip');
  check(copy.find('a')?.channel == 'standard', 'channel restored');
  copy.forget('a');
  check(copy.autoId == null && copy.devices.length == 1, 'forget target does not choose another device');
  copy.autoConnect = false;
  check(!(DeviceHistory()..decode(copy.encode())).autoConnect, 'auto-connect preference');
  final json = jsonDecode(history.encode()) as Map;
  (json['devices'] as List).add({'id': 'bad'});
  (json['devices'] as List).first['pair_code'] = 'not-a-real-code';
  final sanitized = DeviceHistory()..decode(jsonEncode(json));
  check(sanitized.devices.length == 2 && !sanitized.encode().contains('not-a-real-code'), 'invalid rows and secret fields excluded');
  for (var i = 0; i < 30; i++) { history.remember(SavedDevice('$i', 'ANT$i', 'ant', 'standard', time)); }
  check(history.devices.length == 20 && history.autoId == '29', 'bounded history');
  final dir = await Directory.systemTemp.createTemp('ant-device-history-test-');
  try {
    history.file = File('${dir.path}/devices.json');
    await history.save();
    final loaded = DeviceHistory()..file = history.file;
    await loaded.load();
    check(loaded.devices.length == 20 && loaded.autoId == '29', 'disk restore');
    await history.file!.writeAsString('{bad json');
    var rejected = false;
    try { await loaded.load(); } catch (_) { rejected = true; }
    check(rejected && loaded.devices.isEmpty && loaded.autoId == null, 'corrupt file disables auto target');
    check((await dir.list().toList()).any((file) => file.path.contains('.corrupt.')), 'corrupt copy retained');
  } finally { await dir.delete(recursive: true); }
  print('Device history regression checks passed.');
}
