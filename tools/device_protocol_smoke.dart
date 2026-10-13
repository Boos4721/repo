import '../app/lib/device_protocol.dart';

void check(bool value, String message) { if (!value) throw StateError(message); }
String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
List<int> response(List<int> data) {
  final frame = [0xfa, 0x50, 0, 0, 0x15, 0, 0, 0, 0, 0, 0, 0, 0, data.length == 111 ? 1 : 2, 0, 0, ...data];
  final crc = protocolCrc(frame, polynomial: 49960);
  return [...frame, crc >> 8, crc & 255, 0xe5];
}
void main() {
  check(hex(antCommand(13)) == '7EA1510D000018E6AA55', 'balance on vector');
  check(hex(antCommand(14)) == '7EA1510E0000E8E6AA55', 'balance off vector');
  check(hex(antCommand(9)) == '7EA1510900005927AA55', 'restart vector');
  var rejected = false;
  try { antCommand(12); } catch (_) { rejected = true; }
  check(rejected, 'factory reset not supported');
  check(antUserPermission('abcdefgh')[3] == 0x5a, 'third-level slot low byte');
  rejected = false;
  try { antUserPermission('密码'); } catch (_) { rejected = true; }
  check(rejected, 'invalid credentials rejected');
  check(deviceFamily('ANT@REAL') == DeviceFamily.ant, 'ANT name');
  check(deviceFamily('BlueBabe01') == DeviceFamily.lanbao, 'BlueBabe name');
  check(deviceFamily('LB-01') == DeviceFamily.lanbao, 'LB name');
  check(deviceFamily('CJ01') == null, 'controller excluded');
  final protocol = LanbaoProtocol();
  final request = protocol.request();
  check(request.length == 19 && request[13] == 1 && request[15] == 111, 'table1 request');
  for (var i = 0; i < 3; i++) { protocol.request(); }
  check(protocol.request()[13] == 2, 'table2 poll');
  protocol.setMatchCode('1821A33B4556');
  check(protocol.request().sublist(7, 13).join(',') == '24,33,163,59,69,86', 'hex code');
  rejected = false;
  try { protocol.setMatchCode('bad'); } catch (_) { rejected = true; }
  check(rejected, 'invalid match code rejected');
  final data = List.filled(111, 0);
  void put(int off, int length, int value) {
    for (var i = 0; i < length; i++) { data[off + i] = value >> (8 * (length - 1 - i)) & 255; }
  }
  put(0, 2, 7840); put(2, 4, -1234); put(6, 2, 560);
  put(14, 1, -5); put(15, 4, 9470000); put(19, 4, -967);
  put(82, 2, 3730); put(84, 2, 3720); put(86, 2, 10);
  final frame = response(data);
  protocol.reset();
  final readings = <Map<String, dynamic>>[];
  for (final byte in frame) { readings.addAll(protocol.feed([byte])); }
  check(readings.length == 1, 'fragmented frame');
  final reading = readings.single;
  check(reading['current_a'] == -12.34 && reading['power_w'] == -967, 'signed 32-bit');
  check(reading['voltage_v'] == 78.4 && reading['soc'] == 56.0, 'voltage and soc');
  check(reading['remaining_ah'] == 94.7, 'real-device capacity scale: no extra /1000');
  check((reading['temperatures_c'] as List).single == -5, 'signed temperature');
  check(!reading.containsKey('permission') && !reading.containsKey('charge_mos'), 'no fabricated board fields');
  check(protocol.feed([...frame, ...response(List.filled(134, 0))]).length == 2, 'combined tables');
  final bad = [...frame]; bad[20] ^= 1;
  protocol.reset();
  check(protocol.feed([...bad, ...frame]).length == 1, 'CRC rejection and resync');
  protocol.reset();
  check(protocol.feed(frame.sublist(0, 100)).isEmpty, 'truncation waits');
  protocol.reset();
  check(protocol.feed(frame.sublist(100)).isEmpty, 'reset clears fragments');
  check(cellBalancing({'bms_type': 0, 'balance_raw': 2}, 1) == true, 'passive bitmap');
  check(cellBalancing({'bms_type': 2, 'balance_raw': 2}, 1) == null, 'active not bitmap');
  check(cellBalancing({'bms_type': 33, 'balance_raw': 2}, 1) == null, 'unknown model not bitmap');
  check(balanceText({'balance_state': 3}) == '均衡过温', 'overtemperature not simply enabled');
  print('Device protocol regression checks passed (synthetic meter frames, no hardware claim).');
}
