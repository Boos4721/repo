import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'gps_speed.dart';

class GpsController extends ChangeNotifier {
  StreamSubscription<Position>? _subscription;
  Timer? _timer;
  Position? _position;
  bool enabled = false;
  bool busy = false;
  bool _foreground = true;
  bool _disposed = false;
  int _generation = 0;
  String status = 'GPS 未开启';

  double? get speedKmh {
    final p = _position;
    if (!enabled || !_foreground || p == null) return null;
    return gpsSpeedKmh(speed: p.speed, accuracy: p.accuracy,
        timestamp: p.timestamp, now: DateTime.now());
  }

  String get detail {
    if (speedKmh != null) return '手机定位 · 精度 ±${_position!.accuracy.toStringAsFixed(0)} m';
    if (_position != null && enabled && _foreground) return '定位信号弱或已过期';
    return status;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start({bool requestPermission = true}) async {
    if (_disposed || busy || !_foreground) return;
    final generation = ++_generation;
    busy = true;
    enabled = true;
    status = '检查定位权限…';
    _position = null;
    _notify();
    try {
      await _subscription?.cancel();
      _subscription = null;
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('请在系统设置开启定位服务');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw StateError(permission == LocationPermission.deniedForever
            ? '定位权限已被禁用，请在系统设置允许定位'
            : '未获得定位权限，请允许精确定位后重试');
      }
      if (_disposed || generation != _generation || !_foreground) return;
      final LocationSettings settings = Platform.isIOS
          ? AppleSettings(accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0, pauseLocationUpdatesAutomatically: false,
              allowBackgroundLocationUpdates: false)
          : AndroidSettings(accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0, intervalDuration: const Duration(seconds: 1));
      status = '等待 GPS 信号，请到室外';
      _subscription = Geolocator.getPositionStream(locationSettings: settings)
          .listen((position) {
        if (_disposed || generation != _generation) return;
        _position = position;
        _notify();
      }, onError: (Object error) {
        if (_disposed || generation != _generation) return;
        stop(message: '定位中断，请检查定位服务并重试');
      }, onDone: () {
        if (!_disposed && generation == _generation) {
          stop(message: '定位已停止，请重试');
        }
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
    } catch (error) {
      if (!_disposed && generation == _generation) {
        enabled = false;
        status = error is StateError ? error.message.toString() : '无法启动定位，请重试';
      }
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  void stop({String message = 'GPS 未开启', bool keepEnabled = false}) {
    ++_generation;
    busy = false;
    enabled = keepEnabled;
    _subscription?.cancel();
    _subscription = null;
    _timer?.cancel();
    _timer = null;
    _position = null;
    status = message;
    _notify();
  }

  void foreground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    if (!value) {
      stop(message: 'GPS 已暂停', keepEnabled: enabled);
    } else if (enabled) {
      start(requestPermission: false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
