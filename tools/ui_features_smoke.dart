import '../app/lib/snapshot_store.dart';
import '../app/lib/frame_diagnostics.dart';
import '../app/lib/device_history.dart';
import '../app/lib/device_protocol.dart';

void check(bool value, String label) { if (!value) throw StateError(label); }
void main() {
  final store = SnapshotStore();
  final source = <String, dynamic>{'voltage_v': 78.07, 'soc': 55, 'pair_code': 'secret',
    'password': 'hidden', 'gps_lat': 30, 'cells': [{'voltage_v': 3.72, 'flags': 0, 'secret': 'hidden'}],
    'temperatures_c': [25, -40]};
  final row = store.capture(name: '模拟电池', deviceId: null, family: 'ant', demo: true,
    data: source, identity: {'软件版本': 'v1', 'Code Key': 'secret'});
  source['voltage_v'] = 1;
  (source['cells'] as List).first['voltage_v'] = 9;
  final data = row['data'] as Map;
  check(data['voltage_v'] == 78.07 && (data['cells'] as List).first['voltage_v'] == 3.72, 'immutable capture');
  check(!store.encode().contains('secret') && !store.encode().contains('hidden') && !store.encode().contains('gps_lat'), 'credentials and location excluded');
  final restored = SnapshotStore()..decode(store.encode());
  check(restored.rows.single['demo'] == true, 'demo label retained');
  check(snapshotData({'soc': 'bad', 'voltage_v': double.nan}).isEmpty, 'invalid numeric fields filtered');
  final passwordFrame = antUserPermission('abcdefgh');
  check(!safeTxSummary(passwordFrame, meter: false).contains('61 62 63'), 'password TX hidden');
  check(!safeTxSummary(LanbaoProtocol().request(), meter: true).contains('06 06'), 'meter match code hidden');
  check(!safeRxSummary(passwordFrame.sublist(5), meter: false, commandBusy: false).contains('61 62'), 'fragment RX hidden');
  check(!safeRxSummary([0x7e, 0xa1, 0x11, 0, 0, 4, 65, 66, 67, 68], meter: false, commandBusy: false).contains('41 42'), 'RX payload hidden');
  final prefs = DeviceHistory()
    ..pollMs = 900
    ..frameLogging = true
    ..logLines = 80;
  final copy = DeviceHistory()..decode(prefs.encode());
  check(copy.pollMs == 900 && copy.frameLogging && copy.logLines == 80, 'developer preferences persisted');
  print('UI support / redaction / snapshot regression checks passed.');
}
