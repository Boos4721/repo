import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/app_theme.dart';

void main() {
  test('Theme choices select independent appearance modes', () {
    final themes = AppThemes();
    expect(themes.mode, ThemeMode.light);
    final blue = themes.theme(Brightness.light).colorScheme.primary;
    themes.choice = AppThemeChoice.green;
    expect(themes.theme(Brightness.light).colorScheme.primary, isNot(blue));
    themes.choice = AppThemeChoice.dark;
    expect(themes.mode, ThemeMode.dark);
    expect(themes.theme(Brightness.dark).brightness, Brightness.dark);
    themes.choice = AppThemeChoice.system;
    expect(themes.mode, ThemeMode.system);
  });
}
