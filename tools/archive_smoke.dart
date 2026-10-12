import 'dart:convert';
import 'dart:io';

import '../app/lib/record_archive.dart';

void check(bool v, String label) {
  if (!v) throw StateError(label);
}

Map<String, dynamic> row(int i) => {
  'time': '2026-10-12T20:00:00',
  'session': 's$i',
  'source': 'demo',
  'voltage_v': 78.22,
  'current_a': .1,
  'power_w': 7,
};
Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('ant-archive-test-');
  try {
    final file = File('${dir.path}/records.json'),
        archive = RecordArchive(File('${dir.path}/records.json'), limit: 3);
    check((await archive.load()).rows.isEmpty, 'missing file');
    await archive.save(List.generate(5, row));
    final loaded = await archive.load();
    check(
      loaded.rows.length == 3 && loaded.rows.first['session'] == 's2',
      'bounded restore',
    );
    await Future.wait([
      archive.save([row(10)]),
      archive.save([row(11)]),
    ]);
    check(
      (await archive.load()).rows.single['session'] == 's11',
      'ordered writes',
    );
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'samples': [
          row(1),
          {'time': 'bad'},
          {...row(2), 'source': 4, 'session': null},
        ],
      }),
    );
    final partial = await archive.load();
    check(
      partial.rows.length == 2 && partial.warning != null,
      'skip invalid rows',
    );
    check(partial.rows.last['session'] == 'legacy', 'legacy normalization');
    await file.writeAsString('{broken');
    final corrupt = await archive.load();
    check(corrupt.rows.isEmpty && corrupt.warning != null, 'corrupt recovery');
    check(
      await dir.list().any((p) => p.path.contains('.corrupt.')),
      'preserve corrupt bytes',
    );
    await archive.save([row(12)]);
    check(
      (await archive.load()).rows.single['session'] == 's12',
      'save after recovery',
    );
    final csv = exportRecordCsv([
      {...row(1), 'source': '设备,"测试"\n第二行'},
    ]);
    check(
      csv.startsWith('\uFEFF') && csv.contains('设备,""测试""\n第二行'),
      'UTF8 CSV escaping',
    );
    print('9 archive/export scenarios passed.');
  } finally {
    await dir.delete(recursive: true);
  }
}
