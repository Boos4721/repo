// Protocol-derived implementation; maibms MIT attribution in NOTICE.md.
enum DeviceFamily { ant, lanbao }

DeviceFamily? deviceFamily(String name) {
  final n = name.trim().toUpperCase();
  if (n.startsWith('ANT')) return DeviceFamily.ant;
  if (n.startsWith('BLUEBABE') || n.startsWith('BLUE') || n.startsWith('LB')) {
    return DeviceFamily.lanbao;
  }
  return null;
}

int protocolCrc(List<int> bytes, {int polynomial = 0xa001}) {
  var crc = 0xffff;
  for (final b in bytes) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ polynomial : crc >> 1;
    }
  }
  return crc & 0xffff;
}

List<int> antCommand(int command) {
  if (![9, 13, 14].contains(command)) throw ArgumentError('Unsupported control');
  return antFrame(0x51, command, []);
}

List<int> antFrame(int function, int register, List<int> payload) {
  final frame = [0x7e, 0xa1, function, register & 255, register >> 8, payload.length, ...payload];
  final crc = protocolCrc(frame.sublist(1));
  return [...frame, crc & 255, crc >> 8, 0xaa, 0x55];
}

List<int> antUserPermission(String password) {
  if (!RegExp(r'^[\x20-\x7e]{8}$').hasMatch(password)) {
    throw const FormatException('请输入已有的三级权限密码（8 位 ASCII），不是设置新密码');
  }
  return antFrame(0x23, 346, password.codeUnits);
}

String balanceText(Map<String, dynamic>? snapshot) {
  final value = snapshot?['balance_state'];
  return switch (value) {
    0 => '关闭', 1 => '极限均衡', 2 => '充电压差', 3 => '均衡过温',
    4 => '自动均衡', 5 => '手动均衡', null => '设备未提供',
    _ => '未知状态 $value',
  };
}

/// Type 33 requires model/extension evidence: never guess a bitmap.
bool? cellBalancing(Map<String, dynamic>? snapshot, int index) {
  final type = snapshot?['bms_type'];
  final raw = snapshot?['balance_raw'];
  if (type == null || raw is! int || [1, 2, 33].contains(type) || index >= 32) return null;
  return (raw & (1 << index)) != 0;
}

class LanbaoProtocol {
  final List<int> _buffer = [];
  List<int> _match = List.filled(6, 6);
  int _poll = 0;
  int invalidFrames = 0;

  void setMatchCode(String input) {
    final code = input.replaceAll(' ', '').trim();
    if (RegExp(r'^\d{6}$').hasMatch(code)) {
      _match = code.split('').map(int.parse).toList();
    } else if (RegExp(r'^[0-9a-fA-F]{12}$').hasMatch(code)) {
      _match = List.generate(6, (i) => int.parse(code.substring(i * 2, i * 2 + 2), radix: 16));
    } else {
      throw const FormatException('匹配码须为 6 位数字或 12 位十六进制');
    }
  }

  void reset() { _buffer.clear(); _poll = 0; invalidFrames = 0; }
  List<int> request() {
    final table = ++_poll % 5 == 0 ? 2 : 1;
    final frame = [0xfa, 0x50, 0x28, 0xa0, 0x15, 0, 9, ..._match, table, 0, table == 1 ? 111 : 134];
    final crc = protocolCrc(frame, polynomial: 49960);
    return [...frame, crc >> 8, crc & 255, 0xe5];
  }

  /// Two known full tables only. Reassemble BLE fragments and reject partial fields.
  List<Map<String, dynamic>> feed(List<int> bytes) {
    _buffer.addAll(bytes);
    if (_buffer.length > 4096) { _buffer.clear(); invalidFrames++; return []; }
    final result = <Map<String, dynamic>>[];
    while (_buffer.length >= 2) {
      if (_buffer[0] != 0xfa || _buffer[1] != 0x50) { _buffer.removeAt(0); continue; }
      if (_buffer.length < 16) break;
      if (_buffer[4] != 0x15) { _buffer.removeAt(0); invalidFrames++; continue; }
      var size = 0;
      for (final candidate in [130, 153]) {
        if (_buffer.length < candidate || _buffer[candidate - 1] != 0xe5) continue;
        final crc = protocolCrc(_buffer.sublist(0, candidate - 3), polynomial: 49960);
        if (crc == (_buffer[candidate - 3] << 8 | _buffer[candidate - 2])) { size = candidate; break; }
      }
      if (size == 0) {
        if (_buffer.length < 153) break;
        _buffer.removeAt(0); invalidFrames++; continue;
      }
      final table = size == 130 ? 1 : 2;
      final frame = _buffer.sublist(0, size);
      _buffer.removeRange(0, size);
      final d = frame.sublist(16, size - 3);
      int raw(int offset, int length, {bool signed = false}) {
        var value = 0;
        for (final byte in d.sublist(offset, offset + length)) { value = value << 8 | byte; }
        if (signed && (value & (1 << (length * 8 - 1))) != 0) value -= 1 << (length * 8);
        return value;
      }
      String ascii(int offset, int length) => String.fromCharCodes(d.sublist(offset, offset + length)
          .takeWhile((b) => b != 0).where((b) => b >= 32 && b <= 126)).trim();
      if (table == 2) {
        result.add({'table': 2, 'capacity_ah': raw(48, 4) / 1000,
          'cycle_count': raw(57, 2), 'reported_cell_count': raw(47, 1),
          'serial': ascii(0, 16), 'hardware': ascii(16, 8), 'firmware': ascii(24, 8)});
      } else {
        final current = raw(2, 4, signed: true) / 100;
        result.add({'table': 1, 'cells': <Map<String, dynamic>>[],
          'temperatures_c': [raw(14, 1, signed: true)],
          'voltage_v': raw(0, 2) / 100, 'current_a': current, 'soc': raw(6, 2) / 10,
          'remaining_ah': raw(15, 4) / 100000000,
          'power_w': raw(19, 4, signed: true),
          'max_cell_v': raw(82, 2) / 1000, 'min_cell_v': raw(84, 2) / 1000,
          'delta_v': raw(86, 2) / 1000,
          'state': current > 0.3 ? 2 : current < -0.3 ? 4 : 1,
          'relay_name': ascii(57, 25), 'relay_brand': raw(50, 1),
          'relay_mac': d.sublist(51, 57).map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase()});
      }
    }
    return result;
  }
}
