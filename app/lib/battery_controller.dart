import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import 'core.dart';
import 'record_archive.dart';

import 'package:device_info_plus/device_info_plus.dart';

enum LinkState {
  idle,
  scanning,
  connecting,
  connected,
  reconnecting,
  lost,
  demo,
}

enum Channel { standard, auxiliaryA, auxiliaryB }

class BatteryController extends ChangeNotifier {
  final FlutterReactiveBle ble = FlutterReactiveBle();
  AntCore? core;
  String? startupError;
  BatteryController() {
    ready = _restore();
    _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_disposed && _foreground) notifyListeners();
    });
    try {
      core = AntCore();
    } catch (e) {
      startupError = 'Rust 核心未加载，请先构建本机库。$e';
    }
  }
  late final Future<void> ready;
  RecordArchive? _archive;
  Timer? _heartbeat, _saveTimer;
  bool _disposed = false;
  String? storageError, sessionId;
  final List<String> logs = [];
  void log(String message) {
    logs.add('${DateTime.now().toIso8601String()} $message');
    if (logs.length > 200) logs.removeAt(0);
  }

  Future<void> _restore() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _archive = RecordArchive(File('${dir.path}/records-v1.json'));
      final restored = await _archive!.load();
      samples.addAll(restored.rows);
      storageError = restored.warning;
      if (restored.warning != null) log(restored.warning!);
      log('本地记录已载入：${samples.length} 点');
    } catch (e) {
      storageError = '本地记录读取失败：$e';
      log(storageError!);
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> persist() async {
    await ready;
    if (_archive == null) return;
    try {
      await _archive!.save(samples);
    } catch (e) {
      storageError = '本地记录保存失败：$e';
      log(storageError!);
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> clearRecords() async {
    await ready;
    recording = false;
    samples.clear();
    sessionId = null;
    await persist();
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    if (state == LinkState.demo && core != null) {
      _accept(core!.demo());
    } else if (state == LinkState.connected) {
      await _send();
    }
  }

  LinkState state = LinkState.idle;
  Channel channel = Channel.standard;
  Map<String, dynamic>? snapshot;
  DateTime? updated;
  String? deviceId;
  String deviceName = '尚未选择电池';
  String? error;
  final Map<String, DiscoveredDevice> devices = {};
  final List<Map<String, dynamic>> samples = [];
  bool recording = false, _writing = false, _foreground = true;
  int _epoch = 0, _retries = 0;
  Timer? _scanTimer, _poll, _reconnectTimer;
  StreamSubscription<DiscoveredDevice>? _scan;
  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<List<int>>? _notifications;
  QualifiedCharacteristic? _write;
  DateTime? _requestAt;
  bool get stale =>
      updated == null ||
      DateTime.now().difference(updated!).inSeconds >= 5 ||
      !(state == LinkState.connected || state == LinkState.demo);
  static Uuid uuid(String short) =>
      Uuid.parse('0000$short-0000-1000-8000-00805f9b34fb');
  Future<void> scan() async {
    await disconnect();
    final scanEpoch = ++_epoch;
    error = null;
    if (Platform.isAndroid) {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      final permissions = sdk >= 31
          ? <Permission>[Permission.bluetoothScan, Permission.bluetoothConnect]
          : <Permission>[Permission.locationWhenInUse];
      final result = await permissions.request();
      if (scanEpoch != _epoch || _disposed) return;
      if (result.values.any((status) => !status.isGranted)) {
        error = sdk >= 31 ? '需要允许“附近的设备”权限。' : 'Android 11 及以下扫描蓝牙需要定位权限。';
        log(error!);
        notifyListeners();
        return;
      }
    }
    if (scanEpoch != _epoch) return;
    devices.clear();
    log('开始扫描 ANT 设备');
    state = LinkState.scanning;
    notifyListeners();
    _scan = ble
        .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency)
        .listen(
          (d) {
            if (scanEpoch == _epoch && d.name.toUpperCase().startsWith('ANT')) {
              devices[d.id] = d;
              notifyListeners();
            }
          },
          onError: (Object e) {
            if (scanEpoch != _epoch) return;
            error = '扫描失败：$e';
            state = LinkState.idle;
            notifyListeners();
          },
        );
    _scanTimer = Timer(const Duration(seconds: 10), () {
      _scan?.cancel();
      if (scanEpoch == _epoch && state == LinkState.scanning) {
        state = LinkState.idle;
        notifyListeners();
      }
    });
  }

  Future<void> connect(DiscoveredDevice d) async {
    await disconnect();
    if (_disposed) return;
    snapshot = null;
    updated = null;
    deviceId = d.id;
    deviceName = d.name.isEmpty ? 'ANT BMS' : d.name;
    _retries = 0;
    await _connect();
  }

  Future<void> _connect() async {
    if (core == null) {
      error = startupError;
      notifyListeners();
      return;
    }
    final id = deviceId;
    if (id == null) return;
    final epoch = ++_epoch;
    core!.reset();
    log('连接 $id · 通道 ${channel.name} · 尝试 ${_retries + 1}');
    state = _retries > 0 ? LinkState.reconnecting : LinkState.connecting;
    notifyListeners();
    _connection = ble
        .connectToDevice(id: id, connectionTimeout: const Duration(seconds: 12))
        .listen(
          (event) async {
            if (epoch != _epoch) return;
            if (event.connectionState == DeviceConnectionState.connected) {
              try {
                await _subscribe(id, epoch);
              } catch (e) {
                if (epoch == _epoch) _failed('蓝牙通道失败：$e');
              }
            }
            if (event.connectionState == DeviceConnectionState.disconnected) {
              _failed('连接中断');
            }
          },
          onError: (Object e) {
            if (epoch == _epoch) _failed('连接失败：$e');
          },
        );
  }

  Future<void> _subscribe(String id, int epoch) async {
    final services = await ble.discoverServices(id);
    if (epoch != _epoch) return;
    final pair = switch (channel) {
      Channel.standard => ('FFE1', 'FFE1'),
      Channel.auxiliaryA => ('FFF3', 'FFF4'),
      Channel.auxiliaryB => ('FFF5', 'FFF6'),
    };
    final service = services
        .where((s) => s.serviceId == uuid('FFE0'))
        .firstOrNull;
    if (service == null) throw StateError('未找到 FFE0 服务');
    final writer = service.characteristics
        .where((c) => c.characteristicId == uuid(pair.$1))
        .firstOrNull;
    final reader = service.characteristics
        .where((c) => c.characteristicId == uuid(pair.$2))
        .firstOrNull;
    if (writer == null ||
        reader == null ||
        (!writer.isWritableWithoutResponse && !writer.isWritableWithResponse) ||
        (!reader.isNotifiable && !reader.isIndicatable))
      throw StateError('设备不支持当前通道');
    _write = QualifiedCharacteristic(
      deviceId: id,
      serviceId: service.serviceId,
      characteristicId: writer.characteristicId,
    );
    _writeWithResponse = writer.isWritableWithResponse;
    final read = QualifiedCharacteristic(
      deviceId: id,
      serviceId: service.serviceId,
      characteristicId: reader.characteristicId,
    );
    _notifications = ble
        .subscribeToCharacteristic(read)
        .listen(
          (bytes) {
            if (epoch == _epoch) _accept(bytes);
          },
          onError: (Object e) {
            if (epoch == _epoch) _failed('订阅失败：$e');
          },
        );
    // GATT registration is async. Repeat the short read probe until a valid response arrives.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (epoch != _epoch) return;
    _requestAt = DateTime.now();
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_foreground && epoch == _epoch) {
        _send();
        if (_requestAt != null &&
            DateTime.now().difference(_requestAt!).inSeconds >= 5) {
          _failed('5 秒内未收到有效实时应答');
        }
      }
    });
    await _send();
  }

  bool _writeWithResponse = false;
  Future<void> _send() async {
    if (_writing || _write == null || core == null) return;
    _writing = true;
    final epoch = _epoch;
    final characteristic = _write!;
    try {
      final bytes = core!.request();
      if (_writeWithResponse) {
        await ble.writeCharacteristicWithResponse(characteristic, value: bytes);
      } else {
        await ble.writeCharacteristicWithoutResponse(
          characteristic,
          value: bytes,
        );
      }
    } catch (e) {
      if (epoch == _epoch) _failed('读取请求发送失败：$e');
    } finally {
      if (epoch == _epoch) _writing = false;
    }
  }

  void _accept(List<int> bytes) {
    if (!_foreground) return;
    final result = core!.feed(bytes);
    for (final raw in result['events'] as List) {
      final event = raw as Map;
      if (event['type'] == 'snapshot' && event['address'] == 0xa1) {
        snapshot = Map<String, dynamic>.from(event['data'] as Map);
        updated = DateTime.now();
        _requestAt = updated;
        _retries = 0;
        error = null;
        if (state != LinkState.demo) state = LinkState.connected;
        if (recording) {
          samples.add({
            'session': sessionId,
            'soc': snapshot!['soc'],
            'delta_mv': (snapshot!['delta_v'] as num) * 1000,
            'time': updated!.toIso8601String(),
            'source': state == LinkState.demo
                ? 'demo'
                : (deviceId ?? 'unknown'),
            'voltage_v': snapshot!['voltage_v'],
            'current_a': snapshot!['current_a'],
            'power_w': snapshot!['power_w'],
          });
          if (samples.length > 7200) samples.removeAt(0);
          _saveTimer ??= Timer(const Duration(seconds: 3), () {
            _saveTimer = null;
            persist();
          });
        }
      } else if (event['type'] == 'error') {
        error = event['message'].toString();
      }
    }
    notifyListeners();
  }

  void _failed(String message) {
    if ((_reconnectTimer?.isActive ?? false) ||
        state == LinkState.lost ||
        state == LinkState.idle)
      return;
    ++_epoch;
    _poll?.cancel();
    _connection?.cancel();
    _notifications?.cancel();
    _write = null;
    _writing = false;
    _requestAt = null;
    core?.reset();
    error = message;
    log(message);
    if (_foreground && deviceId != null && _retries < 3) {
      _retries++;
      state = LinkState.reconnecting;
      _reconnectTimer = Timer(Duration(seconds: 1 << _retries), () {
        _connect();
      });
    } else {
      state = LinkState.lost;
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    ++_epoch;
    _scanTimer?.cancel();
    _poll?.cancel();
    _reconnectTimer?.cancel();
    await _scan?.cancel();
    await _notifications?.cancel();
    await _connection?.cancel();
    _write = null;
    _writing = false;
    _requestAt = null;
    core?.reset();
    state = LinkState.idle;
    recording = false;
    await persist();
    if (!_disposed) notifyListeners();
  }

  Future<void> demo() async {
    await disconnect();
    if (_disposed) return;
    error = null;
    if (core == null) {
      error = startupError;
      notifyListeners();
      return;
    }
    deviceName = 'ANT@BLE24CBUB-5P4P · 演示';
    deviceId = null;
    snapshot = null;
    updated = null;
    state = LinkState.demo;
    _accept(core!.demo());
    _poll = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_foreground) _accept(core!.demo());
    });
  }

  Future<void> toggleRecord() async {
    await ready;
    if (_disposed) return;
    if (!recording && (snapshot == null || stale)) return;
    recording = !recording;
    if (recording) sessionId = DateTime.now().microsecondsSinceEpoch.toString();
    log(recording ? '开始记录会话 $sessionId' : '停止记录');
    await persist();
    if (!_disposed) notifyListeners();
  }

  void foreground(bool value) {
    _foreground = value;
    if (!value) persist();
    if (value && state == LinkState.lost && deviceId != null) {
      _retries = 0;
      _connect();
    }
    if (value &&
        (state == LinkState.connected ||
            state == LinkState.connecting ||
            state == LinkState.reconnecting))
      _requestAt = DateTime.now();
  }

  String csv({String? session}) => exportRecordCsv(
    samples.where((row) => session == null || row['session'] == session),
  );

  @override
  void dispose() {
    _disposed = true;
    _heartbeat?.cancel();
    _saveTimer?.cancel();
    persist();
    ++_epoch;
    _scanTimer?.cancel();
    _poll?.cancel();
    _reconnectTimer?.cancel();
    _scan?.cancel();
    _notifications?.cancel();
    _connection?.cancel();
    core?.dispose();
    super.dispose();
  }
}
