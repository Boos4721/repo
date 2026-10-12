import '../app/lib/bms_details.dart';
import '../app/lib/device_protocol.dart';

void check(bool value, String label) { if (!value) throw StateError(label); }
void main() {
  check(decodeBmsBits(null).single == '设备未提供', 'missing not clear');
  check(decodeBmsBits('0000000000000000').isEmpty, 'valid zero');
  check(decodeBmsBits('8000000000000000').single.contains('bit63'), 'unsigned 64bit unknown retained');
  check(decodeBmsBits('0000000000800000', warning: true).isEmpty, 'MOS open is not alarm');
  check(decodeBmsBits('0000000000800000', warning: true, states: true).single.contains('充电MOS开'), 'MOS state decoded');
  check(decodeBmsBits('0020000000000000', warning: true).single.contains('内部通信不稳定'), 'high warning bit');
  check(batteryChemistry(0xfaf1) == '三元锂', 'actual enum');
  check(batteryChemistry(1).contains('未知'), 'do not guess legacy enum');
  check(elapsedSeconds(null) == '--', 'absent time');
  check(elapsedSeconds(90061) == '1天 1小时 1分钟', 'duration');
  check(parameterAscii([65, 66, 0, 67]) == 'AB', 'zero terminated identity');
  final active = activeBalance({'bms_type': 2, 'balance_raw': 0x040af600})!;
  check(active['cell'] == 4 && active['current_a'] == -1.0 && active['resistance_mohm'] == 0.1, 'active signed bytes');
  check(activeBalance({'bms_type': 33, 'balance_raw': 0}) == null, 'ambiguous type');
  check(balanceParameterValue(144, 20) == '0.020 V', 'voltage delta register');
  check(balanceParameterValue(148, 180) == '180', 'unknown units remain raw');
  check(antReadParameter(620, 16).sublist(0, 6).join(',') == '126,161,2,108,2,16', 'version read byte layout');
  var rejected = false;
  try { antReadParameter(330, 8); } catch (_) { rejected = true; }
  check(rejected, 'password block excluded');
  check(antUserPermission('abcdefgh', level: 1)[3] == 0x4a, 'read-level slot');
  print('BMS details regression checks passed.');
}
