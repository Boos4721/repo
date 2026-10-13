import 'dart:convert';
import 'dart:io';

class SavedDevice {
  final String id, name, family, channel;
  final DateTime connectedAt;
  const SavedDevice(this.id, this.name, this.family, this.channel, this.connectedAt);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'family': family,
    'channel': channel, 'connected_at': connectedAt.toIso8601String()};
  static SavedDevice? fromJson(dynamic value) {
    if (value is! Map) return null;
    final id = value['id'], name = value['name'], family = value['family'], channel = value['channel'];
    final time = DateTime.tryParse(value['connected_at']?.toString() ?? '');
    if (id is! String || id.isEmpty || id.length > 256 || name is! String || name.length > 256 ||
        !['ant', 'lanbao'].contains(family) || !['standard', 'auxiliaryA', 'auxiliaryB'].contains(channel) || time == null) return null;
    return SavedDevice(id, name, family as String, channel as String, time);
  }
}

/// Non-secret metadata only. Pairing codes belong in platform secure storage.
class DeviceHistory {
  File? file;
  final List<SavedDevice> devices = [];
  bool autoConnect = true;
  int pollMs = 600, logLines = 20;
  bool frameLogging = false;
  String? autoId;
  Future<void> _tail = Future.value();
  SavedDevice? find(String? id) {
    for (final device in devices) { if (device.id == id) return device; }
    return null;
  }
  void decode(String text) {
    final value = jsonDecode(text);
    if (value is! Map || value['version'] != 1 || value['devices'] is! List) throw const FormatException('Invalid history');
    devices.clear();
    for (final item in (value['devices'] as List).take(20)) {
      final device = SavedDevice.fromJson(item);
      if (device != null && find(device.id) == null) devices.add(device);
    }
    devices.sort((a, b) => b.connectedAt.compareTo(a.connectedAt));
    autoConnect = value['auto_connect'] != false;
    pollMs = [300, 600, 900].contains(value['poll_ms']) ? value['poll_ms'] as int : 600;
    logLines = [20, 80].contains(value['log_lines']) ? value['log_lines'] as int : 20;
    frameLogging = value['frame_logging'] == true;
    autoId = value['auto_id'] is String && find(value['auto_id']) != null ? value['auto_id'] as String : null;
  }
  String encode() => jsonEncode({'version': 1, 'auto_connect': autoConnect,
    'poll_ms': pollMs, 'log_lines': logLines, 'frame_logging': frameLogging,
    'auto_id': autoId, 'devices': devices.map((device) => device.toJson()).toList()});
  Future<void> load() async {
    final target = file;
    if (target == null || !await target.exists()) return;
    if (await target.length() > 128 * 1024) throw const FormatException('History too large');
    try { decode(await target.readAsString()); }
    catch (_) {
      devices.clear(); autoId = null;
      await target.copy('${target.path}.corrupt.${DateTime.now().microsecondsSinceEpoch}');
      rethrow;
    }
  }
  void remember(SavedDevice device) {
    devices.removeWhere((old) => old.id == device.id);
    devices.insert(0, device);
    if (devices.length > 20) devices.removeRange(20, devices.length);
    autoId = device.id;
  }
  void forget(String id) {
    devices.removeWhere((device) => device.id == id);
    if (autoId == id) autoId = null;
  }
  Future<void> save() {
    final text = encode(), target = file;
    if (target == null) return Future.error(StateError('History directory unavailable'));
    final result = _tail.catchError((Object _) {}).then((_) async {
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(text, flush: true);
      await temp.rename(target.path);
    });
    _tail = result;
    return result;
  }
}
