import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'battery_controller.dart';
import 'device_profile.dart';
import 'gps_controller.dart';
import 'device_protocol.dart';

void main() => runApp(const AntApp());

class AntApp extends StatelessWidget {
  const AntApp({super.key});
  ThemeData theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff087e78),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xfff4f7f7)
          : const Color(0xff101819),
      fontFamily: '.SF Pro Text',
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ANT BMS',
    debugShowCheckedModeBanner: false,
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    home: const BatteryHome(),
  );
}

class BatteryHome extends StatefulWidget {
  const BatteryHome({super.key});
  @override
  State<BatteryHome> createState() => _BatteryHomeState();
}

class _BatteryHomeState extends State<BatteryHome> with WidgetsBindingObserver {
  final c = BatteryController();
  final gps = GpsController();
  int page = 0;
  String trendKey = 'current_a';
  String? selectedSession;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(changed);
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

  Future<void> authenticateBoard() async {
    final generation = c.connectionGeneration;
    final password = await askSecret('校验三级权限', hint: '输入已有 8 位 ASCII 密码；不保存，不尝试默认密码');
    if (!mounted || password == null || generation != c.connectionGeneration) return;
    try { await c.authenticate(password); }
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
                                code = await askSecret('蓝宝匹配码', initial: '666666',
                                  hint: '6 位数字或 12 位十六进制；只在本次运行内使用');
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
      title: const Text(
        'ANT BMS',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      actions: [
        TextButton.icon(
          onPressed: devices,
          icon: const Icon(Icons.bluetooth, size: 18),
          label: Text(connection),
        ),
        const SizedBox(width: 6),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
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
          if (s != null && c.stale)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: box(
                Text(
                  '数据已过期 · 最后更新 ${c.updated?.toLocal().toString().substring(11, 19) ?? "--"}',
                ),
                padding: const EdgeInsets.all(12),
              ),
            ),
          ...[overview, cells, history, device][page](),
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
          label: '总览',
        ),
        NavigationDestination(
          icon: Icon(Icons.layers_outlined),
          selectedIcon: Icon(Icons.layers),
          label: '单体',
        ),
        NavigationDestination(icon: Icon(Icons.show_chart), label: '记录'),
        NavigationDestination(icon: Icon(Icons.tune), label: '设备'),
      ],
    ),
  );
  List<Widget> overview() {
    final temps = s == null
        ? <num>[]
        : [
            ...List<num>.from(s!['temperatures_c']),
            if (s!['mos_temperature_c'] != null) s!['mos_temperature_c'] as num,
            if (s!['balance_temperature_c'] != null) s!['balance_temperature_c'] as num,
          ];
    final stateText = s == null
        ? '等待数据'
        : switch (s!['state']) {
            1 => '静止',
            2 => '充电',
            3 => '待机',
            4 => '放电',
            5 => '异常',
            _ => '未知状态',
          };
    return [
      box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.speed),
          const SizedBox(width: 8),
          const Expanded(child: Text('GPS 车速')),
          Switch(value: gps.enabled, onChanged: gps.busy ? null : (value) {
            if (value) { gps.start(); } else { gps.stop(); }
          }),
        ]),
        Text('${gps.speedKmh?.toStringAsFixed(1) ?? '--'} km/h',
            style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w600)),
        muted(gps.detail),
        muted('独立于 BMS / 控制器 · 仅前台定位 · 不保存位置'),
      ])),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            Expanded(child: muted(c.deviceName)),
            muted(
              c.state == LinkState.demo
                  ? '模拟数据'
                  : s == null
                  ? '尚无数据'
                  : c.isMeter ? '蓝宝中继 · 只读' : '${(s!['cells'] as List).length} 串',
            ),
          ],
        ),
      ),
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                muted('剩余电量'),
                Chip(label: Text(stateText), side: BorderSide.none),
              ],
            ),
            Text.rich(
              TextSpan(
                text: number('soc', 0),
                style: const TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -2,
                ),
                children: const [
                  TextSpan(
                    text: ' %',
                    style: TextStyle(
                      fontSize: 23,
                      letterSpacing: 0,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: s == null
                  ? 0
                  : (s!['soc'] as num).toDouble().clamp(0, 100) / 100,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 16),
            muted(
              '剩余 ${number('remaining_ah', 1)} / ${number('capacity_ah', 1)} Ah',
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children:
              [
                    ('总电压', number('voltage_v', 2), 'V'),
                    ('电流 · 带符号', number('current_a', 1), 'A'),
                    ('设备功率', number('power_w', 0), 'W'),
                    (
                      '最高原始温度',
                      temps.isEmpty ? '--' : temps.reduce(max).toString(),
                      '°C',
                    ),
                  ]
                  .map(
                    (m) => SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: metric(m.$1, m.$2, m.$3),
                    ),
                  )
                  .toList(),
        ),
      ),
      heading('电池状态'),
      box(
        Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('单体压差'),
                Text(
                  '${s == null ? '--' : ((s!['delta_v'] as num) * 1000).toStringAsFixed(0)} mV',
                  style: TextStyle(color: primary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const Divider(height: 28),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                Text('充电 MOS ${mos('charge_mos')}'),
                Text('放电 MOS ${mos('discharge_mos')}'),
                Text(
                  '均衡 ${balanceText(s)}',
                ),
              ],
            ),
          ],
        ),
      ),
      ...temperatureWidgets(),
      heading('BMS 预计剩余时间'),
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            param('充电剩余', remainingTime(s?['charge_remaining_min'] as num?)),
            param('放电剩余', remainingTime(s?['discharge_remaining_min'] as num?)),
            muted('由保护板返回，仅供参考；负载变化会影响估算。'),
          ],
        ),
      ),
      heading('保护与告警'),
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('保护位：${s?['protection_bits'] ?? '--'}'),
            const SizedBox(height: 8),
            Text('告警位：${s?['warning_bits'] ?? '--'}'),
            const SizedBox(height: 8),
            muted('保留原始位域，未知位不会被隐藏。'),
          ],
        ),
      ),
      if (s == null)
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: FilledButton.icon(
            onPressed: devices,
            icon: const Icon(Icons.bluetooth),
            label: const Text('连接电池 / 体验演示'),
          ),
        ),
    ];
  }

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
    const Text(
      '我的设备',
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
    heading('电池参数'),
    box(
      Column(
        children: [
          param('串数', c.isMeter ? '${s?['reported_cell_count'] ?? "--"}' : s == null ? '--' : '${(s!['cells'] as List).length}'),
          param('额定容量', '${number('capacity_ah', 1)} Ah'),
          param('SOH', '${number('soh', 0)} %'),
          param('设备累计运行', s?['runtime_s'] == null ? '--' : '${s!['runtime_s']} 秒'),
          param('写入与控制', c.isMeter ? '中继只读' : '均衡 / 重启（需三级权限）'),
          if (c.isMeter) param('中继保护板名称', s?['relay_name']?.toString() ?? '--'),
          if (c.isMeter) param('中继保护板 MAC', s?['relay_mac']?.toString() ?? '--'),
          if (c.isMeter) param('模块固件', s?['firmware']?.toString() ?? '--'),
          if (c.isMeter) param('模块串数', s?['reported_cell_count']?.toString() ?? '--'),
          if (c.isMeter) muted('蓝宝字段与容量换算需真机核对；不提供 MOS、均衡或保护板控制'),
        ],
      ),
    ),
    heading('保护板控制'),
    box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      muted(c.state == LinkState.demo ? '模拟模式不发送控制命令'
          : c.isMeter ? '蓝宝中继不支持控制，请直连 ANT'
          : '需三级权限；无应答不自动重发，不更改保护阈值'),
      param('均衡状态', balanceText(s)),
      OutlinedButton.icon(
        onPressed: !c.isMeter && c.state == LinkState.connected && !c.stale && !c.commandBusy ? authenticateBoard : null,
        icon: const Icon(Icons.lock_outline), label: const Text('校验已有三级密码')),
      Wrap(spacing: 8, children: [
        OutlinedButton(onPressed: c.canControl ? () => controlBoard(13, '开启均衡') : null, child: const Text('开启均衡')),
        OutlinedButton(onPressed: c.canControl ? () => controlBoard(14, '关闭均衡') : null, child: const Text('关闭均衡')),
        OutlinedButton(onPressed: c.canControl ? () => controlBoard(9, '重启保护板') : null, child: const Text('重启保护板')),
      ]),
      if (c.commandResult != null) Text(c.commandResult!),
    ])),
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
    heading('关于应用'),
    box(const Text('ANT BMS · v0.5.0\n电池监控、GPS 车速与充放电记录')),
  ];
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
