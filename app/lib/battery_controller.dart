import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import 'core.dart';
import 'ble_channel.dart';
import 'record_archive.dart';
import 'device_protocol.dart';
import 'bms_details.dart';
import 'device_history.dart';
import 'snapshot_store.dart';
import 'frame_diagnostics.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
    _autoConnectAtStartup();
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
  final history = DeviceHistory();
  final snapshots = SnapshotStore();
  bool snapshotSaving = false;
  String? snapshotError;

  Future<void> captureSnapshot() async {
    await ready;
    if (snapshot == null || stale || snapshotSaving) throw StateError('需要新鲜的实时或模拟数据');
    snapshotSaving = true;
    notifyListeners();
    try {
      snapshots.capture(name: deviceName, deviceId: deviceId, family: family.name,
          demo: state == LinkState.demo, data: snapshot!, identity: identity);
      await snapshots.save();
      snapshotError = null;
      log('离线快照已保存（不包含配对码或密码）');
    } catch (_) { snapshotError = '快照保存失败，请重试'; }
    finally { snapshotSaving = false; if (!_disposed) notifyListeners(); }
  }

  void clearDiagnostics() { logs.clear(); if (!_disposed) notifyListeners(); }

  Future<void> setDeveloperOptions({int? pollMs, bool? frameLogging, int? logLines}) async {
    if (pollMs != null && ![300, 600, 900].contains(pollMs) ||
        logLines != null && ![20, 80].contains(logLines)) throw ArgumentError('Invalid developer option');
    await ready;
    try {
      await _historyTask(() async {
        if (pollMs != null) history.pollMs = pollMs;
        if (frameLogging != null) history.frameLogging = frameLogging;
        if (logLines != null) history.logLines = logLines;
        await history.save();
      });
      historyError = null;
    } catch (_) { historyError = '开发者设置保存失败，本次仍按当前设置运行'; }
    if (pollMs != null && (_poll?.isActive ?? false) && _write != null && state != LinkState.demo) {
      _poll?.cancel();
      _startPolling(_epoch);
    }
    log('轮询 ${history.pollMs}ms · 脱敏帧日志 ${history.frameLogging ? "开" : "关"}');
    if (!_disposed) notifyListeners();
  }

  Future<void> saveMeterCode(String id, String code) async {
    final normalized = code.replaceAll(' ', '').trim().toUpperCase();
    LanbaoProtocol().setMatchCode(normalized);
    await ready;
    await _historyTask(() async {
      if (history.find(id)?.family != 'lanbao') throw StateError('请先选择历史蓝宝设备');
      await _secrets.write(key: _codeKey(id), value: normalized);
    });
    // Explicit user edit affects next connection, not the currently active reader.
    log('蓝宝匹配码已安全更新，下次连接生效');
    if (!_disposed) notifyListeners();
  }
  final _secrets = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device));
  String? historyError, _pendingMeterCode;
  bool _rememberedForSession = false;
  Future<void> _historyTail = Future.value();
  Future<void> _historyTask(Future<void> Function() action) {
    final result = _historyTail.catchError((Object _) {}).then((_) => action());
    _historyTail = result;
    return result;
  }
  String _codeKey(String id) => 'ant_bms_lanbao_$id';
  Future<String?> savedMeterCode(String id) => _secrets.read(key: _codeKey(id));

  Future<void> _autoConnectAtStartup() async {
    try {
      await ready;
      final saved = history.find(history.autoId);
      if (_disposed || _epoch != 0 || !_foreground || !history.autoConnect || saved == null) return;
      diagnosticStage = '等待蓝牙就绪，自动连接历史设备';
      notifyListeners();
      if (ble.status != BleStatus.ready) {
        await ble.statusStream.firstWhere((status) => status == BleStatus.ready)
            .timeout(const Duration(seconds: 20));
      }
      if (_disposed || _epoch != 0 || !_foreground || !history.autoConnect || history.autoId != saved.id) return;
      await connectSaved(saved);
    } catch (_) {
      if (!_disposed && state == LinkState.idle && _epoch == 0) {
        diagnosticStage = '自动连接未启动，请检查蓝牙或从历史设备手动连接';
        log(diagnosticStage);
        notifyListeners();
      }
    }
  }

  Future<void> connectSaved(SavedDevice saved) async {
    await ready;
    final found = history.find(saved.id);
    if (found == null) throw StateError('该设备已从历史记录移除');
    final generation = _epoch;
    String? code;
    if (found.family == 'lanbao') {
      code = await savedMeterCode(found.id);
      if (code == null) throw StateError('配对码不可用，请重新扫描并输入蓝宝配对码');
    }
    if (_disposed || generation != _epoch || history.find(found.id) == null) return;
    await _selectDevice(found.id, found.name,
        found.family == 'lanbao' ? DeviceFamily.lanbao : DeviceFamily.ant,
        meterCode: code, savedChannel: found.channel);
  }

  Future<void> setStartupAutoConnect(bool value) async {
    await ready;
    try {
      await _historyTask(() async { history.autoConnect = value; await history.save(); });
      historyError = null;
    } catch (_) { historyError = '自动连接设置保存失败，请重试'; }
    if (!_disposed) notifyListeners();
  }

  Future<void> forgetDevice(String id) async {
    await ready;
    try {
      await _historyTask(() async {
        if (history.find(id)?.family == 'lanbao') await _secrets.delete(key: _codeKey(id));
        history.forget(id);
        await history.save();
      });
      historyError = null;
    } catch (_) { historyError = '移除历史设备或配对码失败，请重试'; }
    if (!_disposed) notifyListeners();
  }

  Future<void> _rememberConnected() async {
    final id = deviceId;
    if (id == null || state != LinkState.connected || _rememberedForSession) return;
    _rememberedForSession = true;
    final saved = SavedDevice(id, deviceName, family.name,
        isMeter ? 'standard' : channel.name, DateTime.now());
    final code = isMeter ? _pendingMeterCode : null;
    try {
      await _historyTask(() async {
        if (code != null) await _secrets.write(key: _codeKey(id), value: code);
        history.remember(saved);
        await history.save();
      });
      historyError = null;
      log('有效连接已保存到历史设备（配对码不进入日志）');
    } catch (_) { historyError = '连接成功，但历史设备或配对码保存失败'; }
    if (!_disposed) notifyListeners();
  }
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
      history.file = File('${dir.path}/devices-v1.json');
      try { await history.load(); }
      catch (_) { historyError = '历史设备读取失败，未自动连接；损坏文件已保留'; }
      snapshots.file = File('${dir.path}/snapshots-v1.json');
      try { await snapshots.load(); }
      catch (_) { snapshotError = '快照读取失败，损坏文件已保留'; }
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
  DeviceFamily family = DeviceFamily.ant;
  bool get isMeter => family == DeviceFamily.lanbao;
  final meter = LanbaoProtocol();
  final Map<String, dynamic> _meterMetadata = {};
  bool commandBusy = false;
  bool detailsBusy = false;
  final Map<String, String> identity = {};
  final Map<int, int> balanceParameters = {};
  DateTime? detailsUpdated;
  String? detailsResult;
  Completer<List<int>>? _detailsReply;
  int? _detailAddress;
  int _detailLength = 0;
  String? commandResult;
  Completer<int>? _commandReply;
  int? _expectedFunction, _expectedRegister;
  bool get canControl => _foreground && !isMeter && !stale && !commandBusy && !detailsBusy &&
      state == LinkState.connected && (snapshot?['permission'] as num? ?? 0) >= 3;

  void setMeterMatchCode(String code) {
    if (state != LinkState.idle && state != LinkState.lost) {
      throw StateError('请断开设备后修改匹配码');
    }
    meter.setMatchCode(code);
  }

  Future<int> _transact(List<int> frame, int function, int register) async {
    if (isMeter || state != LinkState.connected || stale || _write == null || commandBusy || detailsBusy) {
      throw StateError('需要新鲜数据与真实 ANT 直连，且无其他命令执行中');
    }
    commandBusy = true;
    commandResult = '等待设备应答…';
    final reply = Completer<int>();
    _commandReply = reply;
    _expectedFunction = function;
    _expectedRegister = register;
    final epoch = _epoch;
    notifyListeners();
    try {
      // Wait for any in-flight read before sending a single, never retried command.
      final deadline = DateTime.now().add(const Duration(seconds: 4));
      while (_writing && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      if (_writing || epoch != _epoch || _write == null || !_foreground) throw StateError('连接已变化或读取忙');
      if (history.frameLogging) log(safeTxSummary(frame, meter: false));
      await _write!.write(frame, withResponse: _writeWithResponse)
          .timeout(const Duration(seconds: 3));
      return await reply.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      // A delayed reply must not be misattributed to a subsequent identical command.
      if (epoch == _epoch) await disconnect();
      rethrow;
    } finally {
      _commandReply = null;
      _expectedFunction = _expectedRegister = null;
      commandBusy = false;
      _requestAt = DateTime.now();
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> authenticate(String password, {int level = 3}) async {
    final frame = antUserPermission(password, level: level);
    try {
      final returnedLevel = await _transact(frame, 0x43, 330 + (level - 1) * 8);
      if (returnedLevel < 0) throw StateError('连接已中断');
      if (snapshot != null) snapshot!['permission'] = returnedLevel;
      commandResult = returnedLevel >= level ? '设备返回 $returnedLevel 级权限' : '校验未达到 $level 级权限（返回 $returnedLevel 级）';
      log(commandResult!); // Password and credential frame never enter logs.
    } catch (_) {
      commandResult = '权限校验未确认，请重新连接后重试';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> readDetails() async {
    if (!_foreground || isMeter || state != LinkState.connected || stale || commandBusy || detailsBusy ||
        (snapshot?['permission'] as num? ?? 0) < 1) {
      throw StateError('真实 ANT 直连且至少一级权限才能读取设备信息');
    }
    detailsBusy = true;
    detailsResult = '读取设备版本与均衡参数…';
    final epoch = _epoch;
    notifyListeners();
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 4));
      while (_writing && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      if (_writing) throw StateError('读取通道忙');
      for (final block in [(620, 16, '硬件版本'), (636, 16, '软件版本'),
          (262, 32, '电池编号'), (140, 12, '均衡参数')]) {
        if (epoch != _epoch || _write == null || !_foreground) throw StateError('连接已变化');
        final reply = Completer<List<int>>();
        _detailsReply = reply;
        _detailAddress = block.$1;
        _detailLength = block.$2;
        final frame = antReadParameter(block.$1, block.$2);
        if (history.frameLogging) log(safeTxSummary(frame, meter: false));
        await _write!.write(frame, withResponse: _writeWithResponse)
            .timeout(const Duration(seconds: 3));
        final data = await reply.future.timeout(const Duration(seconds: 2));
        if (epoch != _epoch || data.length != block.$2) throw StateError('未取得完整参数块');
        if (block.$1 == 140) {
          for (var i = 0; i < data.length; i += 2) {
            balanceParameters[140 + i] = data[i] | data[i + 1] << 8;
          }
        } else {
          identity[block.$3] = parameterAscii(data);
        }
        detailsUpdated = DateTime.now();
        log('读取 ${block.$3} 完成（${data.length} 字节）');
        _detailsReply = null;
        _detailAddress = null;
      }
      detailsResult = '已读取版本 / 编号 / 均衡参数（只读）';
    } catch (_) {
      detailsResult = '读取未完成，已取得的字段保留；请核对权限与固件。';
      // Isolate late replies from a subsequent read of the same block.
      if (epoch == _epoch) await disconnect();
    } finally {
      _detailsReply = null;
      _detailAddress = null;
      detailsBusy = false;
      _requestAt = DateTime.now();
      if (state == LinkState.connected) await refresh();
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> control(int command) async {
    if (!canControl) throw StateError('直连保护板并获得三级权限后才能控制');
    if (command == 9 && ((snapshot?['current_a'] as num? ?? 999).abs() > 0.5 ||
        ![1, 3].contains(snapshot?['state']))) {
      throw StateError('仅允许无充放电负载时重启');
    }
    final frame = antCommand(command);
    try {
      log('控制请求：$command（不自动重发）');
      final code = await _transact(frame, 0x61, command);
      const results = {0: '无确认结果', 1: '设备已接受', 2: '失败', 3: '权限不足',
        4: '地址超限', 5: '电池类型错误', 6: '电池信息错误', 7: '固件不匹配'};
      commandResult = '命令 $command：${results[code] ?? "未知结果 $code"}';
      if (code == 1 && command != 9) {
        commandResult = '$commandResult；实际均衡状态以实时回读为准';
        await refresh();
      }
      if (code == 1 && command == 9) {
        commandResult = '$commandResult；连接可能中断，请重新连接核对运行时间';
      }
    } catch (_) {
      commandResult = '命令结果未确认：可能已执行，勿连续重发；请重新连接核对';
    }
    log(commandResult!);
    if (!_disposed) notifyListeners();
  }
  String diagnosticStage = '未连接';
  String? lastFailure;
  int requestsSent = 0, notificationCount = 0, receivedBytes = 0,
      validFrames = 0, parseErrors = 0;
  DateTime? lastNotification;

  void _resetDiagnostics() {
    requestsSent = notificationCount = receivedBytes = validFrames = parseErrors = 0;
    lastNotification = null;
    lastFailure = null;
  }

  String get diagnosticReport => [
    'ANT BMS 连接诊断',
    '时间：${DateTime.now().toIso8601String()}',
    '设备：$deviceName · ${deviceId ?? "无真实设备"}',
    '状态：${state.name} · 阶段：$diagnosticStage · 蓝牙：${ble.status.name}',
    '通道：${channel.name} · 重试：$_retries/3',
    '读取请求：$requestsSent · 通知：$notificationCount · 字节：$receivedBytes',
    '有效帧：$validFrames · 解析错误：$parseErrors',
    '最后通知：${lastNotification?.toIso8601String() ?? "--"}',
    '最后有效数据：${updated?.toIso8601String() ?? "--"}',
    '最近失败：${lastFailure ?? "无"}',
    '--- 日志（可能包含设备标识，分享前请检查）---',
    ...logs,
  ].join('\n');

  Future<void> retryConnection() async {
    final id = deviceId;
    if (id == null || state == LinkState.demo) return;
    await disconnect();
    if (_disposed) return;
    _retries = 0;
    error = null;
    _resetDiagnostics();
    await _connect();
  }
  final Map<String, DiscoveredDevice> devices = {};
  final List<Map<String, dynamic>> samples = [];
  bool recording = false, _writing = false, _foreground = true;
  int _epoch = 0, _retries = 0;
  int get connectionGeneration => _epoch;
  Timer? _scanTimer, _poll, _reconnectTimer;
  StreamSubscription<DiscoveredDevice>? _scan;
  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<List<int>>? _notifications;
  Characteristic? _write;
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
        diagnosticStage = '蓝牙扫描权限不足';
        lastFailure = error;
        log(error!);
        notifyListeners();
        return;
      }
    }
    if (scanEpoch != _epoch) return;
    devices.clear();
    diagnosticStage = '扫描附近设备';
    log('开始扫描 ANT 设备');
    state = LinkState.scanning;
    notifyListeners();
    _scan = ble
        .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency)
        .listen(
          (d) {
            if (scanEpoch == _epoch && deviceFamily(d.name) != null) {
              devices[d.id] = d;
              notifyListeners();
            }
          },
          onError: (Object e) {
            if (scanEpoch != _epoch) return;
            error = '扫描失败：$e';
            lastFailure = error;
            diagnosticStage = '扫描失败';
            log(error!);
            state = LinkState.idle;
            notifyListeners();
          },
        );
    _scanTimer = Timer(const Duration(seconds: 10), () {
      _scan?.cancel();
      if (scanEpoch == _epoch && state == LinkState.scanning) {
        diagnosticStage = '扫描完成：${devices.length} 台 ANT 设备';
        log(diagnosticStage);
        if (devices.isEmpty) error = '未发现 ANT 设备：请确认蓝牙已开启、电池可发现，且未被其他 App 占用。';
        state = LinkState.idle;
        notifyListeners();
      }
    });
  }

  Future<void> connect(DiscoveredDevice d, {String? meterCode}) async {
    await ready;
    await _selectDevice(d.id, d.name.isEmpty ? 'ANT BMS' : d.name,
        deviceFamily(d.name) ?? DeviceFamily.ant, meterCode: meterCode);
  }

  Future<void> _selectDevice(String id, String name, DeviceFamily selectedFamily,
      {String? meterCode, String? savedChannel}) async {
    await disconnect();
    if (_disposed) return;
    identity.clear();
    balanceParameters.clear();
    detailsUpdated = null;
    detailsResult = null;
    snapshot = null;
    updated = null;
    deviceId = id;
    deviceName = name;
    family = selectedFamily;
    if (savedChannel != null) channel = Channel.values.firstWhere((c) => c.name == savedChannel, orElse: () => Channel.standard);
    _pendingMeterCode = meterCode?.replaceAll(' ', '').trim().toUpperCase();
    if (isMeter) {
      if (_pendingMeterCode == null) throw StateError('需要蓝宝配对码');
      meter.setMatchCode(_pendingMeterCode!);
    }
    _retries = 0;
    _resetDiagnostics();
    await _connect();
  }

  Future<void> _connect() async {
    if (!isMeter && core == null) {
      error = startupError;
      diagnosticStage = '协议核心不可用';
      lastFailure = error;
      notifyListeners();
      return;
    }
    final id = deviceId;
    if (id == null) return;
    final epoch = ++_epoch;
    core?.reset();
    meter.reset();
    diagnosticStage = '建立蓝牙连接';
    log('连接 $id · 通道 ${channel.name} · 尝试 ${_retries + 1}');
    state = _retries > 0 ? LinkState.reconnecting : LinkState.connecting;
    notifyListeners();
    _connection = ble
        .connectToDevice(id: id, connectionTimeout: const Duration(seconds: 12))
        .listen(
          (event) async {
            if (epoch != _epoch) return;
            if (event.connectionState == DeviceConnectionState.connected) {
              diagnosticStage = '发现服务与特征';
              log('蓝牙链路已连接，等待协议数据');
              try {
                await _subscribe(id, epoch);
              } catch (e) {
                if (epoch == _epoch)
                  _failed('蓝牙通道失败：${e is StateError ? e.message : e}');
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
    final pair = isMeter ? ('FFE2', 'FFE1') : switch (channel) {
      Channel.standard => ('FFE1', 'FFE1'),
      Channel.auxiliaryA => ('FFF3', 'FFF4'),
      Channel.auxiliaryB => ('FFF5', 'FFF6'),
    };
    List<Service> services = [];
    BleChannelMatch? match;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (epoch != _epoch || _disposed) return;
      await ble.discoverAllServices(id).timeout(const Duration(seconds: 8));
      if (epoch != _epoch || _disposed) return;
      services = await ble
          .getDiscoveredServices(id)
          .timeout(const Duration(seconds: 8));
      if (epoch != _epoch || _disposed) return;
      log('服务发现 ${attempt + 1}/3：${services.length} 个服务');
      for (final service in services) {
        log(
          '服务 ${service.id} · ${service.characteristics.map((c) => '${c.id}[W=${c.isWritableWithResponse}/${c.isWritableWithoutResponse},N=${c.isNotifiable}/${c.isIndicatable}]').join(', ')}',
        );
      }
      match = matchBleChannel(
        services
            .map(
              (service) => BleServiceInfo(
                service.id.toString(),
                service.characteristics
                    .map(
                      (c) => BleCharacteristicInfo(
                        c.id.toString(),
                        writable:
                            c.isWritableWithResponse ||
                            c.isWritableWithoutResponse,
                        notifiable: c.isNotifiable || c.isIndicatable,
                      ),
                    )
                    .toList(),
              ),
            )
            .toList(),
        pair.$1,
        pair.$2,
      );
      if (isMeter && match != null && !match.standardService) match = null;
      if (match != null) break;
      if (attempt < 2)
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
    }
    if (match == null)
      throw StateError(
        '未找到可用的 ANT 数据通道；实际服务：${services.map((s) => s.id).join(', ')}。请靠近电池重试，或分享诊断日志。',
      );
    final service = services[match.serviceIndex];
    final writer = service.characteristics[match.writeIndex];
    final reader = service.characteristics[match.notifyIndex];
    if (!match.standardService)
      log('FFE0 未匹配，使用实际服务 ${service.id} 中的已知 ANT 特征对');
    _write = writer;
    diagnosticStage = '订阅通知 / 等待有效应答';
    // Match maibms iOS: prefer writeWithoutResponse when the characteristic supports it.
    _writeWithResponse = !writer.isWritableWithoutResponse;
    log('通道就绪：服务 ${service.id} / 写入 ${writer.id} / 通知 ${reader.id}');
    log('写入模式：${_writeWithResponse ? "带应答" : "无应答"}');
    _notifications = reader.subscribe().listen(
      (bytes) {
        if (epoch != _epoch || _disposed) return;
        notificationCount++;
        receivedBytes += bytes.length;
        lastNotification = DateTime.now();
        if (history.frameLogging) log(safeRxSummary(bytes, meter: isMeter, commandBusy: commandBusy));
        if (snapshot == null) log('收到蓝牙通知：${bytes.length} 字节');
        _accept(bytes);
      },
      onError: (Object e) {
        if (epoch == _epoch) _failed('订阅失败：$e');
      },
    );
    // GATT registration is async. Repeat the short read probe until a valid response arrives.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (epoch != _epoch) return;
    _requestAt = DateTime.now();
    _startPolling(epoch);
    await _send();
  }

  void _startPolling(int epoch) {
    _poll = Timer.periodic(Duration(milliseconds: history.pollMs), (_) {
      if (_foreground && epoch == _epoch) {
        _send();
        final responseTimeout = state == LinkState.connected ? 5 : 10;
        if (!commandBusy && !detailsBusy && _requestAt != null &&
            DateTime.now().difference(_requestAt!).inSeconds >= responseTimeout) {
          _failed('$responseTimeout 秒内未收到有效实时应答（请求 $requestsSent，通知 $notificationCount，有效帧 $validFrames）');
        }
      }
    });
  }

  bool _writeWithResponse = false;
  Future<void> _send() async {
    if (_writing || commandBusy || detailsBusy || _write == null || (!isMeter && core == null)) return;
    _writing = true;
    final epoch = _epoch;
    final characteristic = _write!;
    try {
      final bytes = isMeter ? meter.request() : core!.request();
      if (history.frameLogging) log(safeTxSummary(bytes, meter: isMeter));
      await characteristic
          .write(bytes, withResponse: _writeWithResponse)
          .timeout(const Duration(seconds: 3));
      if (epoch == _epoch) requestsSent++;
    } catch (e) {
      if (epoch == _epoch) _failed('读取请求发送失败：$e');
    } finally {
      if (epoch == _epoch) _writing = false;
    }
  }

  void _accept(List<int> bytes) {
    if (!_foreground) return;
    Map<String, dynamic> result;
    if (isMeter) {
      final readings = meter.feed(bytes);
      parseErrors = meter.invalidFrames;
      final events = <Map<String, dynamic>>[];
      for (final reading in readings) {
        if (reading['table'] == 2) {
          _meterMetadata.addAll(reading);
          if (snapshot != null) snapshot!.addAll(reading);
          // Metadata must not keep stale realtime data looking fresh.
        } else {
          events.add({'type': 'snapshot', 'address': 0xa1,
            'data': <String, dynamic>{...?snapshot, ..._meterMetadata, ...reading}});
        }
      }
      result = {'events': events};
    } else {
      result = core!.feed(bytes);
    }
    for (final raw in result['events'] as List) {
      final event = raw as Map;
      if (event['type'] == 'snapshot' && event['address'] == 0xa1) {
        validFrames++;
        if (state != LinkState.connected && state != LinkState.demo) {
          log('收到首个有效实时帧，连接确认成功');
        }
        diagnosticStage = state == LinkState.demo ? '模拟数据（非真实蓝牙）'
            : isMeter ? '蓝宝中继实时数据就绪' : 'ANT 实时数据就绪';
        snapshot = Map<String, dynamic>.from(event['data'] as Map);
        updated = DateTime.now();
        _requestAt = updated;
        _retries = 0;
        error = null;
        if (state != LinkState.demo) state = LinkState.connected;
        if (state == LinkState.connected) _rememberConnected();
        if (recording) {
          samples.add({
            'session': sessionId,
            'soc': snapshot!['soc'],
            'delta_mv': (snapshot!['delta_v'] as num) * 1000,
            'time': updated!.toIso8601String(),
            'source': state == LinkState.demo ? 'demo' : deviceId ?? 'unknown',
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
      } else if (event['type'] == 'segment') {
        final segment = event['data'] as Map;
        final data = List<int>.from(segment['data'] as List);
        if (segment['address'] == 0xa1 && segment['function'] == 0x12 &&
            segment['register'] == _detailAddress && data.length == _detailLength &&
            _detailsReply != null && !_detailsReply!.isCompleted) {
          _detailsReply!.complete(data);
        }
        if (segment['address'] == 0xa1 && segment['function'] == _expectedFunction &&
            segment['register'] == _expectedRegister && data.length >= 2 &&
            _commandReply != null && !_commandReply!.isCompleted) {
          _commandReply!.complete(data[0] | data[1] << 8);
        }
      } else if (event['type'] == 'error') {
        parseErrors++;
        error = event['message'].toString();
        if (parseErrors <= 5 || parseErrors % 20 == 0) log('解析错误 #$parseErrors：$error');
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
    if (_commandReply != null && !_commandReply!.isCompleted) _commandReply!.complete(-1);
    if (_detailsReply != null && !_detailsReply!.isCompleted) _detailsReply!.complete([]);
    _poll?.cancel();
    _connection?.cancel();
    _notifications?.cancel();
    _write = null;
    _writing = false;
    _requestAt = null;
    core?.reset();
    error = message;
    lastFailure = message;
    log(message);
    if (_foreground && deviceId != null && _retries < 3) {
      _retries++;
      state = LinkState.reconnecting;
      diagnosticStage = '等待重连（第 $_retries/3 次，${1 << _retries} 秒）';
      log(diagnosticStage);
      _reconnectTimer = Timer(Duration(seconds: 1 << _retries), () {
        _connect();
      });
    } else {
      state = LinkState.lost;
      diagnosticStage = '连接失败，请检查后手动重试';
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    final wasDemo = state == LinkState.demo;
    _rememberedForSession = false;
    log('断开连接 / 停止扫描与重连');
    ++_epoch;
    if (_commandReply != null && !_commandReply!.isCompleted) _commandReply!.complete(-1);
    if (_detailsReply != null && !_detailsReply!.isCompleted) _detailsReply!.complete([]);
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
    diagnosticStage = '已断开';
    error = null;
    snapshot = null;
    updated = null;
    meter.reset();
    _meterMetadata.clear();
    if (wasDemo) {
      deviceId = null;
      deviceName = '尚未选择电池';
    }
    recording = false;
    await persist();
    if (!_disposed) notifyListeners();
  }

  Future<void> demo() async {
    await disconnect();
    if (_disposed) return;
    identity.clear();
    balanceParameters.clear();
    detailsUpdated = null;
    detailsResult = null;
    error = null;
    if (core == null) { error = startupError; notifyListeners(); return; }
    family = DeviceFamily.ant;
    deviceName = '模拟电池';
    deviceId = null;
    _resetDiagnostics();
    log('启动模拟电池：与真实设备无关');
    state = LinkState.demo;
    final epoch = _epoch;
    _accept(core!.demo());
    _poll = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_disposed && _foreground && epoch == _epoch && state == LinkState.demo) {
        _accept(core!.demo());
      }
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
