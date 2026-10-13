import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

enum AppThemeChoice { blue, green, dark, system }

class AppThemes extends ChangeNotifier {
  AppThemeChoice choice = AppThemeChoice.blue;
  String? error;
  File? _file;
  static const labels = ['蓝白', '青绿', '深色', '跟随系统'];
  Future<void> restore() async {
    try {
      _file = File('${(await getApplicationSupportDirectory()).path}/appearance.json');
      if (await _file!.exists()) {
        final value = jsonDecode(await _file!.readAsString());
        if (value is Map) {
          choice = AppThemeChoice.values.firstWhere((e) => e.name == value['theme'], orElse: () => AppThemeChoice.blue);
        }
      }
    } catch (_) { error = '主题偏好读取失败，可重新选择保存'; }
    notifyListeners();
  }
  Future<void> _pending = Future.value();
  Future<void> select(AppThemeChoice value) async {
    choice = value;
    error = null;
    notifyListeners();
    try {
      final file = _file ?? File('${(await getApplicationSupportDirectory()).path}/appearance.json');
      _file = file;
      await file.parent.create(recursive: true);
      _pending = _pending.catchError((_) {}).then((_) => file.writeAsString(jsonEncode({'theme': value.name}), flush: true).then((_) {}));
      await _pending;
    } catch (_) { error = '主题已切换，但未能保存，下次启动可能恢复默认'; }
    notifyListeners();
  }
  ThemeMode get mode => choice == AppThemeChoice.dark ? ThemeMode.dark
      : choice == AppThemeChoice.system ? ThemeMode.system : ThemeMode.light;
  ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final accent = choice == AppThemeChoice.green
        ? const Color(0xff00877c) : const Color(0xff078bed);
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
        .copyWith(primary: dark ? const Color(0xff83c7ff) : accent,
          onPrimary: dark ? const Color(0xff00334f) : Colors.white);
    return ThemeData(useMaterial3: true, colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xff101819) : const Color(0xfff4f7f7));
  }
}

final appThemes = AppThemes();
