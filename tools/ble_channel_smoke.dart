import '../app/lib/ble_channel.dart';

void check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

BleCharacteristicInfo char(String id, {bool w = true, bool n = true}) =>
    BleCharacteristicInfo(id, writable: w, notifiable: n);
void main() {
  check(sameBleUuid('FFE0', '0000ffe0-0000-1000-8000-00805F9B34FB'),
      'short/long service');
  check(sameBleUuid('0000FFE1', 'ffe1'), '32/16-bit UUID');
  check(!sameBleUuid('FFE0', 'FFF0'), 'different assigned ids');
  check(!sameBleUuid('FFE0', '0000ffe0-0001-1000-8000-00805f9b34fb'),
      'different custom base');
  var rejected = false;
  try {
    normalizeBleUuid('FFE');
  } on FormatException {
    rejected = true;
  }
  check(rejected, 'invalid UUID rejected');
  final primary = matchBleChannel([
    BleServiceInfo('FFE0', [char('FFE1')])
  ], 'FFE1', 'FFE1');
  check(primary != null && primary.standardService, 'standard pair');
  final alternate = matchBleChannel([
    BleServiceInfo('FFF0', [char('FFE1')])
  ], 'FFE1', 'FFE1');
  check(alternate != null && !alternate.standardService,
      'known pair under other service');
  final preference = matchBleChannel([
    BleServiceInfo('FFF0', [char('FFE1')]),
    BleServiceInfo('FFE0', [char('FFE1')])
  ], 'FFE1', 'FFE1');
  check(preference!.serviceIndex == 1, 'prefer standard service');
  check(
      matchBleChannel([
            BleServiceInfo('FFE0', [char('FFF3'), char('FFF4')])
          ], 'FFE1', 'FFE1') ==
          null,
      'no implicit auxiliary switch');
  final aux = matchBleChannel([
    BleServiceInfo('FFE0', [char('FFF3', n: false), char('FFF4', w: false)])
  ], 'FFF3', 'FFF4');
  check(
      aux!.writeIndex == 0 && aux.notifyIndex == 1, 'explicit auxiliary pair');
  check(
      matchBleChannel([
            BleServiceInfo('FFE0', [char('FFE1', w: false)])
          ], 'FFE1', 'FFE1') ==
          null,
      'read-only rejected');
  check(
      matchBleChannel([
            BleServiceInfo('FFE0', [char('FFE1', n: false)])
          ], 'FFE1', 'FFE1') ==
          null,
      'no notifications rejected');
  check(
      matchBleChannel([
            BleServiceInfo('FFE0', [char('1234')])
          ], 'FFE1', 'FFE1') ==
          null,
      'no arbitrary characteristic');
  check(matchBleChannel([], 'FFE1', 'FFE1') == null, 'empty discovery');
  print('14 BLE UUID/channel regression scenarios passed.');
}
