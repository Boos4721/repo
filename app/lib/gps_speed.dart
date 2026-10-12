/// Keep invalid, inaccurate and stale readings distinct from stationary speed.
double? gpsSpeedKmh({
  required double speed,
  required double accuracy,
  required DateTime timestamp,
  required DateTime now,
}) {
  final age = now.difference(timestamp);
  if (!speed.isFinite || speed < 0 || !accuracy.isFinite || accuracy < 0 ||
      accuracy > 30 || age > const Duration(seconds: 5) ||
      age < const Duration(seconds: -2)) return null;
  return speed * 3.6;
}
