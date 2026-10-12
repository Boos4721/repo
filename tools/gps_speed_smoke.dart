import '../app/lib/gps_speed.dart';

void main() {
  final now = DateTime.utc(2026, 10, 13);
  double? value(double speed, double accuracy, int age) => gpsSpeedKmh(
      speed: speed, accuracy: accuracy,
      timestamp: now.subtract(Duration(seconds: age)), now: now);
  void check(bool condition) {
    if (!condition) throw StateError('GPS speed check failed');
  }
  check(value(10, 5, 0) == 36);
  check(value(0, 5, 0) == 0);
  check(value(-1, 5, 0) == null);
  check(value(double.nan, 5, 0) == null);
  check(value(10, 31, 0) == null);
  check(value(10, -1, 0) == null);
  check(value(10, 5, 6) == null);
  check(value(10, 5, -3) == null);
  print('GPS speed: 8 checks passed');
}
