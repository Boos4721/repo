import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'ble_channel.dart';
import 'apt_diagnostics.dart';

/// Independent APT connection. This implementation never writes a characteristic.
class AptController extends ChangeNotifier {
  AptController(this.ble);
  final FlutterReactiveBle ble;
  final devices = <String, DiscoveredDevice>{};
  final packets = AptPackets();
  StreamSubscription<DiscoveredDevice>? _scan;
  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<List<int>>? _notifications;
  Timer? _scanTimeout, _deadline;
  int _epoch = 0;
  bool _disposed = false, scanning = false, connecting = false, subscribed = false;
  String status = '未连接 APT', name = '', deviceId = '', writeCapability = '--';
  String? error;
  void _changed() { if (!_disposed) notifyListeners(); }
  bool _current(int epoch) => !_disposed && epoch == _epoch;
  Future<void> stopScan() async {
    _scanTimeout?.cancel();
    final scan = _scan; _scan = null;
    scanning = false;
    await scan?.cancel();
  }
  Future<void> scan() async {
    await disconnect();
    final epoch = _epoch;
    devices.clear(); error = null;
    try {
      if (Platform.isAndroid) {
        final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
        final result = await (sdk >= 31
            ? [Permission.bluetoothScan, Permission.bluetoothConnect]
            : [Permission.locationWhenInUse]).request();
        if (!_current(epoch)) return;
        if (result.values.any((p) => !p.isGranted)) throw StateError('请允许蓝牙扫描权限；Android 11 还需要定位权限');
      }
      if (!_current(epoch)) return;
      scanning = true; status = '扫描附近设备（请手动选择 APT）'; _changed();
      // UUIDs are not necessarily advertised, so do not filter by FFE0 or name.
      _scan = ble.scanForDevices(withServices: [], scanMode: ScanMode.lowLatency).listen((device) {
        if (!_current(epoch)) return;
        devices[device.id] = device; _changed();
      }, onError: (Object e) { if (_current(epoch)) _fail('扫描失败：$e'); });
      _scanTimeout = Timer(const Duration(seconds: 10), () async {
        if (!_current(epoch)) return;
        await stopScan();
        if (_current(epoch)) { status = '扫描结束 · ${devices.length} 台设备'; _changed(); }
      });
    } catch (e) { if (_current(epoch)) _fail('$e'); }
  }
  Future<void> connect(DiscoveredDevice device) async {
    await disconnect();
    final epoch = _epoch;
    deviceId = device.id; name = device.name.isEmpty ? '未命名设备' : device.name;
    packets.clear(); error = null; connecting = true;
    status = '正在连接 $name'; _changed();
    _deadline = Timer(const Duration(seconds: 25), () {
      if (_current(epoch) && !subscribed) _fail('连接或服务发现超时，请靠近控制器后重试');
    });
    _connection = ble.connectToDevice(id: device.id, connectionTimeout: const Duration(seconds: 12)).listen((update) async {
      if (!_current(epoch)) return;
      if (update.connectionState == DeviceConnectionState.connected) {
        status = '蓝牙已连接 · 正在发现 FFE0 / FFE1'; _changed();
        try { await _subscribe(epoch); }
        catch (e) { if (_current(epoch)) _fail('APT 通道订阅失败：$e'); }
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        _fail('APT 蓝牙连接已断开');
      }
    }, onError: (Object e) { if (_current(epoch)) _fail('连接失败：$e'); });
  }
  Future<void> _subscribe(int epoch) async {
    await ble.discoverAllServices(deviceId).timeout(const Duration(seconds: 8));
    if (!_current(epoch)) return;
    final services = await ble.getDiscoveredServices(deviceId).timeout(const Duration(seconds: 8));
    if (!_current(epoch)) return;
    for (final service in services) {
      if (!sameBleUuid(service.id.toString(), 'FFE0')) continue;
      for (final characteristic in service.characteristics) {
        if (!sameBleUuid(characteristic.id.toString(), 'FFE1')) continue;
        if (!characteristic.isNotifiable && !characteristic.isIndicatable) {
          throw StateError('FFE1 不支持通知或指示');
        }
        writeCapability = '有应答 ${characteristic.isWritableWithResponse} / 无应答 ${characteristic.isWritableWithoutResponse}（未发送）';
        _notifications = characteristic.subscribe().listen((bytes) {
          if (!_current(epoch)) return;
          packets.accept(bytes);
          status = 'APT 已连接 · 收到原始数据（尚未解析）'; _changed();
        }, onError: (Object e) { if (_current(epoch)) _fail('通知失败：$e'); },
          onDone: () { if (_current(epoch)) _fail('APT 通知订阅已结束'); });
        _deadline?.cancel(); connecting = false; subscribed = true;
        status = 'APT 蓝牙已连接 · 通知订阅已启动，等待首包'; _changed();
        return;
      }
    }
    throw StateError('设备未提供指定的 FFE0 / FFE1 通道，请选择正确的 APT 控制器');
  }
  void _fail(String message) {
    if (_disposed) return;
    error = message;
    final ended = _epoch + 1;
    disconnect().then((_) { if (_current(ended)) { status = message; _changed(); } });
  }
  Future<void> disconnect() async {
    _epoch++; _deadline?.cancel();
    subscribed = connecting = false; status = '未连接 APT'; writeCapability = '--';
    final notifications = _notifications; _notifications = null;
    final connection = _connection; _connection = null;
    await stopScan();
    await notifications?.cancel(); await connection?.cancel(); _changed();
  }
  void clearPackets() { packets.clear(); _changed(); }
  @override
  void dispose() {
    _disposed = true; _epoch++;
    _scanTimeout?.cancel(); _deadline?.cancel();
    _scan?.cancel(); _notifications?.cancel(); _connection?.cancel();
    super.dispose();
  }
}
