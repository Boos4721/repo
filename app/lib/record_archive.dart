import 'dart:convert';
import 'dart:io';

class ArchiveLoad {
  final List<Map<String, dynamic>> rows;
  final String? warning;
  const ArchiveLoad(this.rows, {this.warning});
}

/// Bounded, validated local storage. Corrupt bytes are preserved before future saves.
class RecordArchive {
  final File file;
  final int limit;
  Future<void> _queue = Future<void>.value();
  RecordArchive(this.file, {this.limit = 7200});
  Future<ArchiveLoad> load() async {
    if (!await file.exists()) return const ArchiveLoad([]);
    try {
      if (await file.length() > 16 * 1024 * 1024)
        throw const FormatException('record archive too large');
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map || raw['version'] != 1 || raw['samples'] is! List)
        throw const FormatException('unknown archive schema');
      final rows = <Map<String, dynamic>>[];
      var skipped = 0;
      for (final value in raw['samples'] as List) {
        if (value is! Map ||
            value['time'] is! String ||
            DateTime.tryParse(value['time'] as String) == null ||
            [
              'voltage_v',
              'current_a',
              'power_w',
            ].any((k) => value[k] is! num || !(value[k] as num).isFinite)) {
          skipped++;
          continue;
        }
        final row = Map<String, dynamic>.from(value);
        row['session'] = row['session'] is String ? row['session'] : 'legacy';
        row['source'] = row['source'] is String ? row['source'] : 'unknown';
        for (final key in ['soc', 'delta_mv']) {
          if (row[key] is! num || !(row[key] as num).isFinite) row.remove(key);
        }
        rows.add(row);
      }
      return ArchiveLoad(
        rows.skip(rows.length > limit ? rows.length - limit : 0).toList(),
        warning: skipped > 0 ? '已跳过 $skipped 条无效记录' : null,
      );
    } on FormatException {
      final backup =
          '${file.path}.corrupt.${DateTime.now().microsecondsSinceEpoch}';
      await file.rename(backup);
      return const ArchiveLoad([], warning: '记录文件格式损坏，原文件已保留，当前从空记录开始。');
    }
  }

  Future<void> save(List<Map<String, dynamic>> rows) {
    final bounded = rows
        .skip(rows.length > limit ? rows.length - limit : 0)
        .toList();
    final content = jsonEncode({'version': 1, 'samples': bounded});
    final task = _queue.then((_) async {
      final tmp = File('${file.path}.tmp');
      await file.parent.create(recursive: true);
      await tmp.writeAsString(content, flush: true);
      await tmp.rename(file.path);
    });
    // Failed I/O is reported to the caller without poisoning later queue entries.
    _queue = task.catchError((Object _) {});
    return task;
  }
}

String exportRecordCsv(Iterable<Map<String, dynamic>> rows) {
  String quote(Object? value) =>
      '"${(value ?? '').toString().replaceAll('"', '""')}"';
  const keys = [
    'time',
    'session',
    'voltage_v',
    'current_a',
    'power_w',
    'soc',
    'delta_mv',
    'source',
  ];
  return '\uFEFF${keys.join(',')}\r\n${rows.map((row) => keys.map((key) => quote(row[key])).join(',')).join('\r\n')}';
}
