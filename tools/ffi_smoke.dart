import '../app/lib/core.dart';

void main() {
  final core = AntCore();
  try {
    if (core.request().join(',') != '126,161,1,0,0,245,88,98,170,85')
      throw StateError('request mismatch');
    final demo = core.demo();
    var seen = 0;
    for (final byte in demo) {
      for (final event in core.feed([byte])['events'] as List) {
        if (event['type'] == 'snapshot') {
          seen++;
          final s = event['data'];
          if ((s['cells'] as List).length != 21 ||
              s['soc'] != 56 ||
              s['capacity_ah'] != 170.0 ||
              s['discharge_remaining_min'] != 1561 ||
              s['voltage_v'] != 78.22) throw StateError('snapshot mismatch');
        }
      }
    }
    if (seen != 1) throw StateError('chunked FFI feed failed');
    core.reset();
    for (var i = 0; i < 100; i++) {
      if ((core.feed(demo)['events'] as List).length != 1)
        throw StateError('repeat failed');
    }
    print(
        'Dart ↔ Rust FFI smoke passed: request, demo, bytewise feed, reset, 100 repeated calls.');
  } finally {
    core.dispose();
  }
}
