import 'dart:convert';
import 'dart:io';

const snapshotFields = {'state', 'permission', 'cells', 'temperatures_c', 'voltage_v', 'current_a',
  'soc', 'soh', 'capacity_ah', 'remaining_ah', 'power_w', 'runtime_s', 'bms_type',
  'charge_mos', 'discharge_mos', 'balance_state', 'balance_raw', 'mos_temperature_c',
  'balance_temperature_c', 'max_cell_v', 'min_cell_v', 'max_cell_index', 'min_cell_index',
  'average_v', 'delta_v', 'cycle_ah', 'cycle_count', 'battery_type', 'protection_bits', 'warning_bits',
  'total_discharge_ah', 'total_charge_ah', 'total_discharge_s', 'total_charge_s',
  'charge_remaining_min', 'discharge_remaining_min', 'hardware', 'firmware', 'reported_cell_count'};

Map<String, dynamic> snapshotData(Map<String, dynamic> source) {
  final result = <String, dynamic>{};
  for (final key in snapshotFields) {
    final value = source[key];
    if (!source.containsKey(key)) continue;
    if (key == 'cells' && value is List) {
      result[key] = value.whereType<Map>().where((cell) => cell['voltage_v'] is num &&
          (cell['voltage_v'] as num).isFinite).take(64).map((cell) => {
            'voltage_v': cell['voltage_v'], 'flags': cell['flags'] is int ? cell['flags'] : 0}).toList();
    } else if (key == 'temperatures_c' && value is List) {
      result[key] = value.whereType<num>().where((n) => n.isFinite).take(16).toList();
    } else if (['protection_bits', 'warning_bits', 'hardware', 'firmware'].contains(key)) {
      if (value is String && value.length <= 256) result[key] = value;
    } else if (value == null || value is num && value.isFinite) {
      result[key] = value;
    }
  }
  return Map<String, dynamic>.from(jsonDecode(jsonEncode(result)) as Map);
}

class SnapshotStore {
  File? file;
  final List<Map<String, dynamic>> rows = [];
  Future<void> _tail = Future.value();
  Map<String, dynamic> capture({required String name, required String? deviceId,
      required String family, required bool demo, required Map<String, dynamic> data,
      required Map<String, String> identity}) {
    final now = DateTime.now();
    final row = <String, dynamic>{'id': '${now.microsecondsSinceEpoch}', 'time': now.toIso8601String(),
      'name': name, 'device_id': deviceId, 'family': family, 'demo': demo,
      'data': snapshotData(data),
      'identity': {for (final key in ['硬件版本', '软件版本', 'Boot版本', '电池编号'])
        if (identity.containsKey(key)) key: identity[key]}};
    rows.insert(0, row);
    if (rows.length > 20) rows.removeRange(20, rows.length);
    return row;
  }
  void decode(String text) {
    final value = jsonDecode(text);
    if (value is! Map || value['version'] != 1 || value['rows'] is! List) throw const FormatException('Invalid snapshots');
    rows.clear();
    for (final raw in (value['rows'] as List).take(20)) {
      if (raw is! Map || raw['id'] is! String || raw['name'] is! String || raw['data'] is! Map ||
          !['ant', 'lanbao'].contains(raw['family']) || DateTime.tryParse('${raw['time']}') == null) continue;
      final identity = raw['identity'] is Map ? raw['identity'] as Map : {};
      rows.add({'id': raw['id'], 'name': raw['name'], 'time': raw['time'], 'family': raw['family'],
        'demo': raw['demo'] == true, 'device_id': raw['device_id'] is String ? raw['device_id'] : null,
        'data': snapshotData(Map<String, dynamic>.from(raw['data'] as Map)),
        'identity': {for (final key in ['硬件版本', '软件版本', 'Boot版本', '电池编号'])
          if (identity[key] is String) key: identity[key]}});
    }
  }
  String encode() => jsonEncode({'version': 1, 'rows': rows});
  Future<void> load() async {
    if (file == null || !await file!.exists()) return;
    if (await file!.length() > 2 * 1024 * 1024) throw const FormatException('Snapshots too large');
    try { decode(await file!.readAsString()); }
    catch (_) {
      rows.clear();
      await file!.copy('${file!.path}.corrupt.${DateTime.now().microsecondsSinceEpoch}');
      rethrow;
    }
  }
  Future<void> save() {
    final target = file, text = encode();
    if (target == null) return Future.error(StateError('Snapshot directory unavailable'));
    final result = _tail.catchError((Object _) {}).then((_) async {
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(text, flush: true);
      await temp.rename(target.path);
    });
    _tail = result;
    return result;
  }
}
