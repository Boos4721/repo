import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'battery_controller.dart';
import 'device_profile.dart';
import 'gps_controller.dart';
import 'device_protocol.dart';
import 'bms_details.dart';
import 'dashboard.dart';
import 'apt_controller.dart';
import 'app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appThemes.restore();
  runApp(const AntApp());
}

class AntApp extends StatelessWidget {
  const AntApp({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: appThemes,
    builder: (context, child) => MaterialApp(title: 'ANT BMS', debugShowCheckedModeBanner: false,
      theme: appThemes.theme(Brightness.light), darkTheme: appThemes.theme(Brightness.dark),
      themeMode: appThemes.mode, home: const BatteryHome()));
}

class BatteryHome extends StatefulWidget {
  const BatteryHome({super.key});
  @override
  State<BatteryHome> createState() => _BatteryHomeState();
}

class _BatteryHomeState extends State<BatteryHome> with WidgetsBindingObserver {
  final c = BatteryController();
  late final apt = AptController(c.ble);
  final gps = GpsController();
  int page = 0;
  String trendKey = 'current_a';
  String? selectedSession;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(changed);
    apt.addListener(changed);
    gps.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<String?> askSecret(String title, {String initial = '', String? hint}) async {
    var value = initial;
    return showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextFormField(initialValue: initial, obscureText: true,
        autocorrect: false, enableSuggestions: false,
        decoration: InputDecoration(helperText: hint),
        onChanged: (text) => value = text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, value), child: const Text('确认')),
      ]));
  }

  Future<void> authenticateBoard({int level = 3}) async {
    final generation = c.connectionGeneration;
    final password = await askSecret('校验 $level 级权限', hint: '输入已有 8 位 ASCII 密码；不保存，不尝试默认密码');
    if (!mounted || password == null || generation != c.connectionGeneration) return;
    try { await c.authenticate(password, level: level); }
    catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> controlBoard(int command, String label) async {
    final generation = c.connectionGeneration;
    if (command == 9 && (gps.speedKmh ?? 0) > 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('车辆移动中，禁止重启')));
      return;
    }
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('$label？'),
      content: Text(command == 9
          ? '请停车、关闭车辆动力并断开充电器。重启可能暂时中断供电、蓝牙连接和权限；电流近零不代表车辆已停稳。命令无应答也可能已执行。'
          : '操作对象：${c.deviceName}。均衡实际运行由固件及电池条件决定；设备接受命令不代表已开始能量转移。请确认电池状况正常。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认执行')),
      ]));
    if (!mounted || confirmed != true || generation != c.connectionGeneration) return;
    if (command == 9 && (gps.speedKmh ?? 0) > 2) return;
    try { await c.control(command); }
    catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> forgetSavedDevice(String id, String name) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('移除历史设备？'),
      content: Text('移除 $name，并删除该设备已保存的蓝宝配对码。不会删除充放电记录；当前连接不受影响。'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('移除'))]));
    if (confirmed == true && mounted) await c.forgetDevice(id);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    c.foreground(state == AppLifecycleState.resumed);
    // Permission dialogs briefly mark iOS inactive; do not cancel their request.
    if (state == AppLifecycleState.resumed) gps.foreground(true);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) gps.foreground(false);
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(changed);
    apt.removeListener(changed);
    apt.dispose();
    c.dispose();
    gps.removeListener(changed);
    gps.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get s => c.snapshot;
  String number(String key, int places) =>
      (s?[key] as num?)?.toStringAsFixed(places) ?? '--';
  Color get primary => Theme.of(context).colorScheme.primary;
  String get connection => switch (c.state) {
    LinkState.idle => '未连接',
    LinkState.scanning => '扫描中',
    LinkState.connecting => '连接中',
    LinkState.connected => '已连接',
    LinkState.reconnecting => '重连中',
    LinkState.lost => '设备失联',
    LinkState.demo => '模拟设备',
  };
  Widget box(Widget child, {EdgeInsets padding = const EdgeInsets.all(18)}) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(22),
        ),
        child: child,
      );
  Widget muted(String text) => Text(
    text,
    style: TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 12,
    ),
  );
  Widget heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 12),
    child: Text(
      text,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
    ),
  );
  Widget metric(String label, String value, String unit) => box(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        muted(label),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            text: value,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
            children: [
              TextSpan(
                text: ' $unit',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  void devices() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: ListenableBuilder(
            listenable: c,
            builder: (_, child) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '连接你的电池',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text('附近的 ANT 保护板 / 蓝宝电量计'),
                TextButton.icon(onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => page = 4);
                }, icon: const Icon(Icons.history), label: Text('历史设备（${c.history.devices.length}）')),
                if (c.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      c.error!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: c.state == LinkState.scanning
                      ? null
                      : () => c.scan(),
                  icon: const Icon(Icons.bluetooth_searching),
                  label: Text(
                    c.state == LinkState.scanning ? '正在扫描…' : '扫描附近设备',
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: ListView(
                    shrinkWrap: true,
                    children: c.devices.values
                        .map(
                          (d) => ListTile(
                            title: Text(d.name),
                            subtitle: Text('${deviceFamily(d.name) == DeviceFamily.lanbao ? "蓝宝电量计" : "ANT 保护板"} · ${d.id}\n信号 ${d.rssi} dBm'),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              Navigator.pop(ctx);
                              String? code;
                              if (deviceFamily(d.name) == DeviceFamily.lanbao) {
                                String? savedCode;
                                try { savedCode = await c.savedMeterCode(d.id); } catch (_) {}
                                if (!mounted) return;
                                code = await askSecret('蓝宝匹配码', initial: savedCode ?? '666666',
                                  hint: '6 位数字或 12 位十六进制；成功连接后按设备安全保存');
                                if (code == null || !mounted) return;
                              }
                              try {
                                await c.connect(d, meterCode: code);
                              } catch (error) {
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                              }
                            },
                          ),
                        )
                        .toList(),
                  ),
                ),
                if (c.devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂未发现设备，请靠近电池并开启蓝牙。'),
                  ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (c.state == LinkState.demo) {
                      c.disconnect();
                    } else {
                      c.demo();
                    }
                  },
                  icon: Icon(c.state == LinkState.demo ? Icons.link_off : Icons.science_outlined),
                  label: Text(c.state == LinkState.demo ? '断开模拟连接' : '体验模拟电池'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        'ANT BMS',
        style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onPrimary),
      ),
      backgroundColor: Theme.of(context).colorScheme.primary,
      systemOverlayStyle: Theme.of(context).brightness == Brightness.dark ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onPrimary),
      actions: [
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onPrimary),
          onPressed: devices,
          icon: const Icon(Icons.bluetooth, size: 18),
          label: Text(connection),
        ),
        const SizedBox(width: 6),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (c.startupError != null)
            box(
              Text(
                c.startupError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (s != null && c.stale && page != 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: box(
                Text(
                  '数据已过期 · 最后更新 ${c.updated?.toLocal().toString().substring(11, 19) ?? "--"}',
                ),
                padding: const EdgeInsets.all(12),
              ),
            ),
          ...[overview, cells, history, controls, device][page](),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: page,
      onDestinationSelected: (i) => setState(() => page = i),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: '实时',
        ),
        NavigationDestination(
          icon: Icon(Icons.layers_outlined),
          selectedIcon: Icon(Icons.layers),
          label: '单体',
        ),
        NavigationDestination(icon: Icon(Icons.show_chart), label: '记录'),
        NavigationDestination(icon: Icon(Icons.tune), label: '控制'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
      ],
    ),
  );
  List<Widget> overview() => [
    BatteryDashboard(data: s, identity: c.identity, name: c.deviceName, connection: connection,
      meter: c.isMeter, stale: c.stale, demo: c.state == LinkState.demo,
      gpsEnabled: gps.enabled, gpsSpeed: gps.speedKmh, gpsDetail: gps.detail,
      onGps: gps.busy ? null : (value) { if (value) { gps.start(); } else { gps.stop(); } },
      onConnect: devices, onCells: () => setState(() => page = 1),
      onRecords: () => setState(() => page = 2), onControl: () => setState(() => page = 3),
      onDetails: () => openSection('版本与参数', deviceDetails)),
  ];

  String mos(String key) => s == null
      ? '--'
      : s![key] == null
      ? '不支持'
      : s![key] == 1
      ? '开启'
      : s![key] == 0
      ? '关闭'
      : '状态 ${s![key]}';
  List<Widget> cells() {
    final data = s?['cells'] as List? ?? [];
    return [
      const Text(
        '每一串，都看得见',
        style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      muted('${data.length} 串 · 点击查看详情'),
      const SizedBox(height: 16),
      box(
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            mini(
              '最大压差',
              s == null
                  ? '--'
                  : '${((s!['delta_v'] as num) * 1000).round()} mV',
            ),
            mini(
              '最高 #${s?['max_cell_index'] ?? '--'}',
              '${number('max_cell_v', 3)} V',
            ),
            mini(
              '最低 #${s?['min_cell_index'] ?? '--'}',
              '${number('min_cell_v', 3)} V',
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      if (data.isEmpty) box(Text(c.isMeter ? '蓝宝不提供逐串电压；仅显示最高、最低及压差。' : '连接设备后显示单体电压。')),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 96,
        ),
        itemCount: data.length,
        itemBuilder: (ctx, i) {
          final cell = data[i] as Map;
          return Material(
            color: Theme.of(ctx).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '第 ${i + 1} 串',
                          style: const TextStyle(fontSize: 22),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${(cell['voltage_v'] as num).toStringAsFixed(3)} V',
                        ),
                        Text('原始状态标志：${cell['flags']}'),
                        const SizedBox(height: 8),
                        Text(cellBalancing(s, i) == null ? '主动均衡 / 未确认机型：不按位图推测均衡串号'
                            : cellBalancing(s, i)! ? '该串正在均衡' : '该串未报告均衡'),
                      ],
                    ),
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    muted(
                      '#${(i + 1).toString().padLeft(2, '0')} ${i + 1 == s!['max_cell_index']
                          ? '最高'
                          : i + 1 == s!['min_cell_index']
                          ? '最低'
                          : ''}',
                    ),
                    const Spacer(),
                    Text(
                      '${(cell['voltage_v'] as num).toStringAsFixed(3)} V',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value:
                          (cell['voltage_v'] as num).toDouble().clamp(0, 4.2) /
                          4.2,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ];
  }

  List<Widget> temperatureWidgets() {
    final sensors = s?['temperatures_c'] as List? ?? [];
    final readings = <({String label, num? value})>[
      (label: '均衡', value: s?['balance_temperature_c'] as num?),
      (label: 'MOS', value: s?['mos_temperature_c'] as num?),
      for (var i = 0; i < sensors.length; i++)
        (label: 'T${i + 1}', value: sensors[i] as num),
    ];
    return [
      heading('温度探头'),
      box(
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 320 ? 2 : 3;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 16,
              children: readings
                  .map(
                    (reading) => SizedBox(
                      width: width,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          muted(reading.label),
                          const SizedBox(height: 4),
                          Text(
                            temperatureText(reading.value),
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            temperatureStatus(reading.value),
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ),
    ];
  }

  Widget mini(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      muted(label),
      const SizedBox(height: 5),
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ],
  );
  List<Widget> history() {
    final sessions = c.samples
        .map((row) => row['session'])
        .whereType<String>()
        .toSet();
    final activeSession = sessions.contains(selectedSession)
        ? selectedSession
        : null;
    final filtered = c.samples
        .where(
          (row) => activeSession == null || row['session'] == activeSession,
        )
        .toList();
    final points = filtered
        .where(
          (row) =>
              row[trendKey] is num &&
              DateTime.tryParse(row['time'] as String) != null,
        )
        .toList();
    final values = points
        .map((row) => (row[trendKey] as num).toDouble())
        .toList();
    String sessionLabel(String id) {
      final row = c.samples.firstWhere((row) => row['session'] == id);
      final date = DateTime.tryParse(row['time'] as String)?.toLocal();
      final time = date == null
          ? id
          : '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      return '${row['source'] == 'demo' ? '模拟' : '电池'} · $time';
    }

    String axisTime(bool first) => points.isEmpty
        ? '--'
        : DateTime.parse(
            points[first ? 0 : points.length - 1]['time'] as String,
          ).toLocal().toString().substring(11, 19);
    return [
      const Text(
        '充放电记录',
        style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      muted('自动保存到本机 · 最近 7200 个采样点'),
      if (c.storageError != null) Text(c.storageError!),
      DropdownButton<String>(
        value: activeSession,
        hint: const Text('全部记录会话'),
        isExpanded: true,
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('全部记录会话')),
          ...sessions.map(
            (id) => DropdownMenuItem(value: id, child: Text(sessionLabel(id))),
          ),
        ],
        onChanged: (v) => setState(() => selectedSession = v),
      ),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'current_a', label: Text('电流')),
          ButtonSegment(value: 'voltage_v', label: Text('电压')),
          ButtonSegment(value: 'power_w', label: Text('功率')),
          ButtonSegment(value: 'soc', label: Text('电量')),
        ],
        selected: {trendKey},
        onSelectionChanged: (v) => setState(() => trendKey = v.first),
      ),
      heading('记录趋势'),
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            muted(
              {
                'current_a': '电流 / A',
                'voltage_v': '电压 / V',
                'power_w': '功率 / W',
                'soc': '电量 / %',
              }[trendKey]!,
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 170,
              child: values.length < 2
                  ? const Center(child: Text('开始记录后显示曲线'))
                  : CustomPaint(
                      size: const Size(double.infinity, 170),
                      painter: TrendPainter(
                        values,
                        primary,
                        Theme.of(context).colorScheme.outlineVariant,
                        times: points
                            .map(
                              (row) =>
                                  DateTime.parse(row['time'] as String)
                                      .millisecondsSinceEpoch,
                            )
                            .toList(),
                        sessions: points
                            .map((row) => row['session'] as String?)
                            .toList(),
                      ),
                    ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [muted(axisTime(true)), muted(axisTime(false))],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: c.recording
            ? c.toggleRecord
            : s == null || c.stale
            ? null
            : c.toggleRecord,
        icon: Icon(c.recording ? Icons.stop : Icons.fiber_manual_record),
        label: Text(c.recording ? '停止记录' : '开始记录'),
      ),
      OutlinedButton.icon(
        onPressed: c.samples.isEmpty
            ? null
            : () async {
                await SharePlus.instance.share(
                  ShareParams(
                    files: [
                      XFile.fromData(
                        Uint8List.fromList(
                          utf8.encode(c.csv(session: activeSession)),
                        ),
                        mimeType: 'text/csv',
                        name: 'ant-bms-record.csv',
                      ),
                    ],
                    fileNameOverrides: ['ant-bms-record.csv'],
                  ),
                );
              },
        icon: const Icon(Icons.ios_share),
        label: Text(activeSession == null ? '导出全部 CSV' : '导出当前会话 CSV'),
      ),
      muted('${filtered.length} 个采样点 · 导出与当前筛选一致'),
      TextButton.icon(
        onPressed: c.samples.isEmpty
            ? null
            : () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('清空本地记录？'),
                    content: const Text('建议先导出 CSV，清空后无法恢复。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  setState(() => selectedSession = null);
                  await c.clearRecords();
                }
              },
        icon: const Icon(Icons.delete_outline),
        label: const Text('清空记录'),
      ),
    ];
  }

  List<Widget> device() => [
    box(settingLink('APT 控制器', apt.status, Icons.bluetooth,
      () => openSection('APT 控制器', aptWidgets))),
    const Text(
      '设置',
      style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 16),
    box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.deviceName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          muted(c.deviceId ?? '未选择真实设备'),
          const SizedBox(height: 8),
          Text('$connection · ${permissionText(s?['permission'] as num?)}'),
        ],
      ),
    ),
    box(Column(children: [
      settingLink('历史设备', '${c.history.devices.length} 台', Icons.history,
        () => openSection('历史设备', () => [...historyDevices(), ...connectionSettings()])),
      settingLink('版本与只读参数', c.detailsUpdated == null ? '待读取' : '已读取', Icons.info_outline,
        () => openSection('版本与参数', () => [...deviceDetails(), ...batteryParameters()])),
      settingLink('权限与控制', permissionText(s?['permission'] as num?), Icons.lock_outline,
        () => setState(() => page = 3)),
      settingLink('离线快照', '${c.snapshots.rows.length} 个', Icons.camera_alt_outlined,
        () => openSection('快照', snapshotWidgets)),
      settingLink('开发者', '轮询 / 脱敏日志 / 匹配码', Icons.code,
        () => openSection('开发者', developerWidgets)),
      settingLink('连接诊断', c.diagnosticStage, Icons.bluetooth_searching,
        () => openSection('连接诊断', connectionDiagnostics)),
    ])),
    heading('外观'),
    box(Column(children: AppThemeChoice.values.map((choice) => RadioListTile<AppThemeChoice>(
      title: Text(AppThemes.labels[choice.index]), value: choice, groupValue: appThemes.choice,
      onChanged: (value) async { if (value != null) { await appThemes.select(value); if (mounted) setState(() {}); } },
    )).toList())),
    if (appThemes.error != null) muted(appThemes.error!),
    heading('关于应用'),
    box(const Text('ANT BMS · v0.10.0\n仅与设备通信；历史、记录和快照保存在本机。\n快照和模拟不发送控制命令。')),
  ];

  List<Widget> historyDevices() => [
    heading('历史设备'),
    box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(contentPadding: EdgeInsets.zero,
        title: const Text('启动时自动连接'),
        subtitle: const Text('连接上次成功收到实时数据的真实设备；模拟不参与'),
        value: c.history.autoConnect, onChanged: c.setStartupAutoConnect),
      if (c.historyError != null) Text(c.historyError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (c.history.devices.isEmpty) muted('连接成功后自动保存历史设备'),
      ConstrainedBox(constraints: const BoxConstraints(maxHeight: 320), child: ListView(
        shrinkWrap: true, children: c.history.devices.map((saved) => ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(saved.name),
          subtitle: Text('${saved.family == "lanbao" ? "蓝宝 · 使用已保存配对码" : "ANT · ${saved.channel}"}\n${saved.connectedAt.toLocal()}'),
          isThreeLine: true,
          onTap: () async {
            try { await c.connectSaved(saved); }
            catch (error) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
            }
          },
          trailing: IconButton(icon: const Icon(Icons.delete_outline), tooltip: '移除设备与配对码',
            onPressed: () => forgetSavedDevice(saved.id, saved.name)),
        )).toList())),
      muted('配对码不显示在列表或诊断日志中；手动断开后本次不自动重连，下次启动按开关设置连接'),
    ])),
  ];

  List<Widget> connectionSettings() => [
    heading('连接管理'),
    box(
      Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('通信通道'),
            subtitle: Text(c.isMeter ? '蓝宝固定 FFE2 写 / FFE1 通知' : '切换后需重新连接'),
            trailing: DropdownButton<Channel>(
              value: c.channel,
              items: const [
                DropdownMenuItem(value: Channel.standard, child: Text('默认')),
                DropdownMenuItem(
                  value: Channel.auxiliaryA,
                  child: Text('备用 A'),
                ),
                DropdownMenuItem(
                  value: Channel.auxiliaryB,
                  child: Text('备用 B'),
                ),
              ],
              onChanged: c.isMeter ? null : (v) async {
                if (v == null) return;
                if (v != Channel.standard) {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('使用备用通道？'),
                      content: Text(
                        v == Channel.auxiliaryA
                            ? '备用 A 与蓝牙屏接口共享，可能影响已连接的屏幕。'
                            : '备用 B 与充电器接口共享，可能影响充电器通信。',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('切换'),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                }
                await c.disconnect();
                c.channel = v;
                changed();
              },
            ),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('选择 / 扫描设备'),
            trailing: const Icon(Icons.chevron_right),
            onTap: devices,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(c.state == LinkState.demo ? '断开模拟连接' : '断开连接'),
            subtitle: c.state == LinkState.demo ? const Text('停止模拟并清除实时演示数据，保留历史记录') : null,
            onTap: c.state == LinkState.idle ? null : () => c.disconnect(),
          ),
        ],
      ),
    ),
  ];

  List<Widget> batteryParameters() => [
    heading('电池参数'),
    box(
      Column(
        children: [
          param('串数', c.isMeter ? '${s?['reported_cell_count'] ?? "--"}' : s == null ? '--' : '${(s!['cells'] as List).length}'),
          param('额定容量', '${number('capacity_ah', 1)} Ah'),
          param('SOH', '${number('soh', 0)} %'),
          param('电池类型', batteryChemistry(s?['battery_type'] as num?)),
          param('设备累计运行', s?['runtime_s'] == null ? '--' : '${s!['runtime_s']} 秒'),
          param('累计充电容量', '${number('total_charge_ah', 3)} Ah'),
          param('累计放电容量', '${number('total_discharge_ah', 3)} Ah'),
          param('累计充电时间', elapsedSeconds(s?['total_charge_s'] as num?)),
          param('累计放电时间', elapsedSeconds(s?['total_discharge_s'] as num?)),
          param('写入与控制', c.isMeter ? '中继只读' : '均衡 / 重启（需三级权限）'),
          if (c.isMeter) param('中继保护板名称', s?['relay_name']?.toString() ?? '--'),
          if (c.isMeter) param('中继保护板 MAC', s?['relay_mac']?.toString() ?? '--'),
          if (c.isMeter) param('模块固件', s?['firmware']?.toString() ?? '--'),
          if (c.isMeter) param('模块串数', s?['reported_cell_count']?.toString() ?? '--'),
          if (c.isMeter) muted('蓝宝字段与容量换算需真机核对；不提供 MOS、均衡或保护板控制'),
        ],
      ),
    ),
  ];

  List<Widget> deviceDetails() => [
    heading('设备版本与均衡参数 · 只读'),
    box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!c.isMeter) TextButton(
        onPressed: c.state == LinkState.connected && !c.stale && !c.commandBusy && !c.detailsBusy ? () => authenticateBoard(level: 1) : null,
        child: const Text('校验已有一级密码（用于只读参数）')),
      if (!c.isMeter) OutlinedButton.icon(
        onPressed: c.state == LinkState.connected && !c.stale && !c.commandBusy && !c.detailsBusy &&
            (s?['permission'] as num? ?? 0) >= 1 ? () async {
          try { await c.readDetails(); }
          catch (error) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
          }
        } : null,
        icon: const Icon(Icons.manage_search), label: Text(c.detailsBusy ? '读取中…' : '读取版本与均衡参数')),
      if (c.isMeter) muted('蓝宝版本来自模块表2；不读取或修改保护板参数'),
      if (!c.isMeter) ...['硬件版本', '软件版本', '电池编号'].map((name) => param(name, c.identity[name]?.isNotEmpty == true ? c.identity[name]! : '--')),
      if (!c.isMeter) ...balanceParameterNames.entries.map((entry) => param(entry.value,
          balanceParameterValue(entry.key, c.balanceParameters[entry.key]))),
      if (c.detailsUpdated != null) muted('最后读取：${c.detailsUpdated!.toLocal()}'),
      if (c.detailsResult != null) Text(c.detailsResult!),
      if (!c.isMeter) muted('至少一级权限；仅读取指定非密码块，未取得的值显示 --'),
    ])),
  ];

  List<Widget> controls() => [
    heading('APT 控制器'),
    box(Column(children: [
      param('连接状态', apt.status),
      param('转速 / 电压 / 电流', '-- / -- / --'),
      settingLink('连接与收包诊断', 'FFE0 / FFE1 · 接收原始通知', Icons.bluetooth,
        () => openSection('APT 控制器', aptWidgets)),
    ])),
    heading('均衡详情'),
    box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      param('均衡状态', balanceText(s)),
      if (activeBalance(s) != null) ...[
        param('主动均衡串号', '${activeBalance(s)!['cell']}'),
        param('主动均衡电流', '${activeBalance(s)!['current_a']} A'),
        param('均衡线阻', '${activeBalance(s)!['resistance_mohm']} mΩ'),
        param('均衡故障原始码', '${activeBalance(s)!['fault_raw']}'),
      ] else if (s?['bms_type'] == 33) muted('类型33需扩展机型证据，本版保留原始值，不猜测主动均衡'),
      if (s?['balance_raw'] != null) param('均衡原始值', '0x${(s!['balance_raw'] as num).toInt().toRadixString(16).padLeft(8, "0").toUpperCase()}'),
      muted(c.stale ? '最后读数，当前状态未确认' : '主动均衡解析只对已确认的类型1/2开放'),
    ])),
    heading('保护板控制'),
    box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      muted(c.state == LinkState.demo ? '模拟模式不发送控制命令'
          : c.isMeter ? '蓝宝中继不支持控制，请直连 ANT'
          : '需三级权限；无应答不自动重发，不更改保护阈值'),
      param('均衡状态', balanceText(s)),
      OutlinedButton.icon(
        onPressed: !c.isMeter && c.state == LinkState.connected && !c.stale && !c.commandBusy && !c.detailsBusy ? authenticateBoard : null,
        icon: const Icon(Icons.lock_outline), label: const Text('校验已有三级密码')),
      Wrap(spacing: 8, children: [
        OutlinedButton(onPressed: c.canControl ? () => controlBoard(13, '开启均衡') : null, child: const Text('开启均衡')),
        OutlinedButton(onPressed: c.canControl ? () => controlBoard(14, '关闭均衡') : null, child: const Text('关闭均衡')),
        OutlinedButton(onPressed: c.canControl ? () => controlBoard(9, '重启保护板') : null, child: const Text('重启保护板')),
      ]),
      if (c.commandResult != null) Text(c.commandResult!),
    ])),
  ];

  List<Widget> connectionDiagnostics() => [
    heading('连接诊断'),
    box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          param('蓝牙状态', c.ble.status.name),
          Text('连接阶段：${c.diagnosticStage}'),
          const SizedBox(height: 8),
          param('读取请求', '${c.requestsSent}'),
          param('通知 / 字节', '${c.notificationCount} / ${c.receivedBytes}'),
          param('有效帧 / 解析错误', '${c.validFrames} / ${c.parseErrors}'),
          if (c.lastFailure != null) Text('最近失败：${c.lastFailure}'),
          if (c.state == LinkState.demo) muted('当前为模拟连接，计数不表示真实蓝牙通信'),
          param(
            '最后更新',
            c.updated?.toLocal().toString().substring(11, 19) ?? '--',
          ),
          param('数据状态', c.stale ? '未更新 / 已过期' : '实时'),
          OutlinedButton.icon(
            onPressed: s == null || c.stale ? null : c.refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('立即刷新'),
          ),
          TextButton.icon(
            onPressed: c.deviceId != null && (c.state == LinkState.idle || c.state == LinkState.lost)
                ? c.retryConnection : null,
            icon: const Icon(Icons.bluetooth_connected),
            label: const Text('重新连接'),
          ),
          TextButton.icon(
            onPressed: () =>
                SharePlus.instance.share(ShareParams(text: c.diagnosticReport)),
            icon: const Icon(Icons.ios_share),
            label: const Text('分享诊断日志'),
          ),
          ...c.logs.reversed
              .take(8)
              .map(
                (line) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: muted(line),
                ),
              ),
        ],
      ),
    ),
  ];
  Widget settingLink(String title, String detail, IconData icon, VoidCallback action) => ListTile(
    contentPadding: EdgeInsets.zero, leading: Icon(icon, color: primary), title: Text(title),
    subtitle: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: const Icon(Icons.chevron_right), onTap: action);

  void openSection(String title, List<Widget> Function() children) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (ctx) => Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: ListenableBuilder(listenable: Listenable.merge([c, apt]), builder: (_, child) => ListView(
        padding: const EdgeInsets.all(16), children: children()))))));
  }

  Future<void> editSavedCode(String id) async {
    try {
      final old = await c.savedMeterCode(id);
      if (!mounted) return;
      final code = await askSecret('蓝宝匹配码', initial: old ?? '',
        hint: '保存到所选设备，下次连接生效；不改变当前连接');
      if (code == null || !mounted) return;
      await c.saveMeterCode(id, code);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存，下次连接生效')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存失败：请检查匹配码格式或所选设备')));
    }
  }

  List<Widget> aptWidgets() => [
    box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      param('状态', apt.status),
      param('设备', apt.name.isEmpty ? '--' : apt.name),
      param('服务 / 写入 / 通知', 'FFE0 / FFE1 / FFE1'),
      param('写入能力', apt.writeCapability),
      param('通知 / 字节', '${apt.packets.count} / ${apt.packets.bytes}'),
      param('最近收包', apt.packets.lastReceived?.toLocal().toString() ?? '--'),
      muted('仅连接、订阅通知，不发送查询或调参命令。通道相同不能确认设备型号，请手动选择你的 APT。'),
      if (apt.error != null) Text(apt.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      Wrap(spacing: 8, children: [
        FilledButton.icon(onPressed: apt.scanning || apt.connecting ? null : apt.scan,
          icon: const Icon(Icons.search), label: const Text('扫描 APT')),
        OutlinedButton(onPressed: apt.disconnect, child: const Text('断开 APT')),
      ]),
    ])),
    heading('附近设备'),
    box(Column(children: [
      if (apt.devices.isEmpty) muted(apt.scanning ? '扫描中…' : '先扫描，再选择控制器'),
      ...((apt.devices.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi))).map((device) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(device.name.isEmpty ? '未命名设备' : device.name),
        subtitle: Text('${device.rssi} dBm · ${device.id}'),
        trailing: const Icon(Icons.bluetooth),
        onTap: apt.connecting ? null : () async {
          if (device.id == c.deviceId && c.state != LinkState.idle && c.state != LinkState.lost) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('这台设备当前用于保护板连接，请选择 APT 控制器')));
            return;
          }
          await apt.connect(device);
        },
      ))),
    ])),
    heading('原始通知 · 最近 40 包，每包最多显示 256 字节'),
    box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      muted('通知尚未解析为控制器指标。无主动通知的设备可能一直等待首包。原始数据可能含设备标识，分享前请检查。'),
      Wrap(spacing: 8, children: [
        TextButton(onPressed: apt.clearPackets, child: const Text('清空收包')),
        TextButton(onPressed: apt.packets.rows.isEmpty ? null : () async {
          await Clipboard.setData(ClipboardData(text: apt.packets.rows.reversed.join('\n')));
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制原始通知')));
        }, child: const Text('复制原始通知')),
      ]),
      SelectableText(apt.packets.rows.isEmpty ? '尚未收到通知' : apt.packets.rows.join('\n\n'),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
    ])),
  ];

  List<Widget> developerWidgets() => [
    heading('轮询频率'),
    box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<int>(segments: const [
        ButtonSegment(value: 900, label: Text('900ms')),
        ButtonSegment(value: 600, label: Text('600ms')),
        ButtonSegment(value: 300, label: Text('300ms'))], selected: {c.history.pollMs},
        onSelectionChanged: (value) => c.setDeveloperOptions(pollMs: value.single)),
      const SizedBox(height: 10), muted('默认 600ms；300ms 更频繁，弱信号可能增加负担。仅前台轮询。'),
    ])),
    box(Column(children: [
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('帧级日志（脱敏）'),
        subtitle: const Text('TX 密码/匹配码隐藏；RX 仅记录帧头或摘要'),
        value: c.history.frameLogging, onChanged: (value) => c.setDeveloperOptions(frameLogging: value)),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('日志显示级别'),
        trailing: DropdownButton<int>(value: c.history.logLines, items: const [
          DropdownMenuItem(value: 20, child: Text('普通')),
          DropdownMenuItem(value: 80, child: Text('详细'))],
          onChanged: (value) { if (value != null) c.setDeveloperOptions(logLines: value); })),
      if (c.historyError != null) Text(c.historyError!),
    ])),
    heading('蓝宝匹配码'),
    box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!c.history.devices.any((saved) => saved.family == 'lanbao')) muted('先成功连接蓝宝，才能按设备管理匹配码'),
      ...c.history.devices.where((saved) => saved.family == 'lanbao').map((saved) => ListTile(
        contentPadding: EdgeInsets.zero, title: Text(saved.name),
        subtitle: const Text('匹配码按设备安全保存，不显示在日志中'),
        trailing: TextButton(onPressed: () => editSavedCode(saved.id), child: const Text('修改')))),
    ])),
    box(Column(children: [
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('清空日志'), trailing: const Icon(Icons.delete_outline), onTap: c.clearDiagnostics),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('复制诊断日志'), trailing: const Icon(Icons.copy), onTap: () async {
        await Clipboard.setData(ClipboardData(text: c.diagnosticReport));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('诊断日志已复制')));
      }),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('导出日志文件'), trailing: const Text('txt'), onTap: () => SharePlus.instance.share(
        ShareParams(files: [XFile.fromData(Uint8List.fromList(utf8.encode(c.diagnosticReport)),
          name: 'ant-bms-diagnostics.txt', mimeType: 'text/plain')], fileNameOverrides: ['ant-bms-diagnostics.txt']))),
      muted('日志含设备标识，分享前请检查。最多保留 200 条，不含配对码或权限密码。'),
    ])),
    ConstrainedBox(constraints: const BoxConstraints(maxHeight: 320), child: SingleChildScrollView(child: Container(
      width: double.infinity, padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xff0e191a), borderRadius: BorderRadius.circular(20)),
      child: SelectableText(c.logs.reversed.take(c.history.logLines).toList().reversed.join('\n'),
        style: const TextStyle(color: Color(0xff97dec2), fontFamily: 'monospace', fontSize: 11))))),
  ];

  List<Widget> snapshotWidgets() => [
    box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('离线快照', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8), muted('保留最近 20 个快照；只读查看，不替换实时数据、不自动连接、不发送控制命令。'),
      FilledButton.icon(onPressed: s != null && !c.stale && !c.snapshotSaving ? () async {
        try {
          await c.captureSnapshot();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(c.snapshotError ?? '快照已保存')));
        } catch (_) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('需要新鲜的实时数据才能保存')));
        }
      } : null, icon: const Icon(Icons.camera_alt_outlined), label: Text(c.snapshotSaving ? '保存中…' : '保存当前快照')),
      if (c.snapshotError != null) Text(c.snapshotError!),
    ])),
    ...c.snapshots.rows.map((row) => box(ListTile(contentPadding: EdgeInsets.zero,
      title: Text('${row['name']} · ${row['demo'] == true ? "模拟" : "设备"}'),
      subtitle: Text(DateTime.parse(row['time'] as String).toLocal().toString()),
      trailing: const Icon(Icons.chevron_right), onTap: () => previewSnapshot(row)))),
  ];

  void previewSnapshot(Map<String, dynamic> row) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (ctx) => Scaffold(
      appBar: AppBar(title: const Text('离线快照 · 只读'), actions: [IconButton(icon: const Icon(Icons.ios_share),
        onPressed: () => SharePlus.instance.share(ShareParams(files: [
          XFile.fromData(Uint8List.fromList(utf8.encode(jsonEncode(row))), name: 'ant-bms-snapshot.json', mimeType: 'application/json')],
          fileNameOverrides: ['ant-bms-snapshot.json'])))]),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(12), children: [
        const Text('离线保存值，不是当前状态。导出包含设备标识，分享前请检查。'),
        const SizedBox(height: 12),
        BatteryDashboard(data: Map<String, dynamic>.from(row['data'] as Map),
          identity: Map<String, String>.from(row['identity'] as Map), name: row['name'] as String,
          connection: '离线快照', meter: row['family'] == 'lanbao', stale: true, demo: row['demo'] == true,
          gpsEnabled: false, gpsSpeed: null, gpsDetail: '快照不包含 GPS 定位', onGps: null,
          onConnect: null, onCells: null, onRecords: null, onControl: null, onDetails: null),
      ])))));
  }

  Widget param(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Flexible(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );
}

class TrendPainter extends CustomPainter {
  final List<double> values;
  final Color color, grid;
  final List<int> times;
  final List<String?> sessions;
  TrendPainter(
    this.values,
    this.color,
    this.grid, {
    required this.times,
    required this.sessions,
  });
  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final rawLo = values.reduce(min), rawHi = values.reduce(max);
    final pad = rawHi == rawLo ? 0.5 : (rawHi - rawLo) * 0.1;
    final lo = rawLo - pad, hi = rawHi + pad, range = hi - lo;
    final start = times.reduce(min),
        end = times.reduce(max),
        span = max(1, end - start);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final ratio = end == start
          ? i / (values.length - 1)
          : (times[i] - start) / span;
      final x = ratio.clamp(0, 1) * size.width,
          y = size.height - 12 - (values[i] - lo) / range * (size.height - 24);
      if (i == 0 || sessions[i] != sessions[i - 1]) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      if ((i == 0 || sessions[i] != sessions[i - 1]) &&
          (i == values.length - 1 || sessions[i] != sessions[i + 1])) {
        canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = color);
      }
    }
    for (var i = 0; i < 3; i++) {
      final y = 12 + i * (size.height - 24) / 2;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = grid
          ..strokeWidth = 1,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: (hi - i * range / 2).toStringAsFixed(1),
          style: TextStyle(color: color, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, max(0, y - 12)));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant TrendPainter old) => true;
}
