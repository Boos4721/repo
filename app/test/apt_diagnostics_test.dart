import 'package:flutter_test/flutter_test.dart';
import '../lib/apt_diagnostics.dart';

void main() {
  test('APT preserves packet boundaries, bounds memory and counts all bytes', () {
    final packets = AptPackets();
    packets.accept([]);
    expect(packets.count, 0);
    packets.accept([0, 0xfe, 0x10]);
    expect(packets.rows.single, contains('00 FE 10'));
    for (var i = 0; i < 50; i++) { packets.accept(List.filled(300, 0xff)); }
    expect(packets.rows.length, 40);
    expect(packets.count, 51);
    expect(packets.bytes, 15003);
    expect(packets.rows.first, contains('截断'));
    expect(packets.rows.first.length, lessThan(900));
    packets.clear();
    expect(packets.rows, isEmpty);
    expect(packets.bytes, 0);
    expect(packets.lastReceived, isNull);
  });
}
