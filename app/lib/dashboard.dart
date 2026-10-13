import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'bms_details.dart';
import 'device_protocol.dart';
import 'device_profile.dart';

/// Presentation only: never changes readings, connection state or control permissions.
class BatteryDashboard extends StatelessWidget {
  final Map<String, dynamic>? data;
  final Map<String, String> identity;
  final String name, connection, gpsDetail;
  final bool meter, stale, demo, gpsEnabled;
  final double? gpsSpeed;
  final ValueChanged<bool>? onGps;
  final VoidCallback? onConnect, onCells, onRecords, onControl, onDetails;
  const BatteryDashboard({super.key, required this.data, required this.identity,
    required this.name, required this.connection, required this.meter, required this.stale,
    required this.demo, required this.gpsEnabled, required this.gpsSpeed, required this.gpsDetail,
    required this.onGps, required this.onConnect, required this.onCells, required this.onRecords,
    required this.onControl, required this.onDetails});
  static const blue = Color(0xff078bed);
  String number(String key, [int places = 1]) => (data?[key] as num?)?.toStringAsFixed(places) ?? '--';
  Widget card(BuildContext context, Widget child, {EdgeInsets padding = const EdgeInsets.all(14)}) => Container(
    width: double.infinity, padding: padding, margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)), child: child);
  Widget info(BuildContext context, String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 78, child: Text(label, style: const TextStyle(color: Color(0xff798797), fontSize: 12))),
      Expanded(child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 13))),
    ]));
  String get state => switch (data?['state']) {
    0 => '无状态', 1 => '静止', 2 => '充电', 3 => '待机', 4 => '放电', 5 => '异常', null => '--', _ => '未知状态',
  };
  String mos(String key) => data?[key] == null ? '--' : data![key] == 1 ? '开启' : data![key] == 0 ? '关闭' : '状态 ${data![key]}';
  Widget stateRow(BuildContext context, String label, String value, bool? on) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xff6b7888)))),
      Container(width: 9, height: 9, margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(shape: BoxShape.circle,
          color: value.contains('异常') || value.contains('过温') ? const Color(0xffe56a74)
              : on == null ? const Color(0xffc1c9d0) : on ? const Color(0xff50bd76) : const Color(0xffa9b3bc))),
      Flexible(child: Text(value, maxLines: 2, style: const TextStyle(fontSize: 12))),
    ]));
  Widget smallMetric(BuildContext context, String label, String value, String unit, IconData icon, Color color) => Row(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 28, height: 28, decoration: BoxDecoration(color: color.withValues(alpha: .13),
        shape: BoxShape.circle), child: Icon(icon, color: color, size: 17)),
      const SizedBox(width: 7), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text.rich(TextSpan(text: value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: color),
          children: [TextSpan(text: ' $unit', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400))]),
          maxLines: 1)),
        const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 11, color: Color(0xff82909d))),
      ])),
    ]);
  Widget alarms(BuildContext context, String title, List<String> items) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    const Divider(height: 20),
    if (items.isEmpty) const Text('无已报告项目', style: TextStyle(fontSize: 12, color: Color(0xff8b99a4))),
    ...items.take(5).map((item) => Padding(padding: const EdgeInsets.only(bottom: 6),
      child: Text(item, style: const TextStyle(fontSize: 11, color: Color(0xff707c8a))))),
    if (items.length > 5) Text('另 ${items.length - 5} 项，详见设置', style: const TextStyle(fontSize: 11)),
  ]);
  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('总电压', number('voltage_v', 2), 'V', Icons.bolt, Theme.of(context).colorScheme.primary),
      ('电流', number('current_a', 1), 'A', Icons.swap_horiz, const Color(0xff32b7b7)),
      ('功率', number('power_w', 0), 'W', Icons.flash_on, const Color(0xff547ff2)),
      ('最高单体', number('max_cell_v', 3), 'V', Icons.arrow_upward, const Color(0xffea687e)),
      ('最低单体', number('min_cell_v', 3), 'V', Icons.arrow_downward, const Color(0xffeca849)),
      ('平均单体', number('average_v', 3), 'V', Icons.show_chart, const Color(0xff55b67c)),
      ('压差', data?['delta_v'] == null ? '--' : ((data!['delta_v'] as num) * 1000).toStringAsFixed(0),
        'mV', Icons.equalizer, const Color(0xffa26ee4)),
      (meter ? '模块循环次数' : '循环容量', number(meter ? 'cycle_count' : 'cycle_ah', meter ? 0 : 1),
        meter ? '次' : 'Ah', Icons.loop, const Color(0xff5a9bc7)),
    ];
    final sensors = <(String, num?)>[
      if (!meter) ('MOS', data?['mos_temperature_c'] as num?),
      if (!meter) ('均衡', data?['balance_temperature_c'] as num?),
      for (var i = 0; i < (data?['temperatures_c'] as List? ?? []).length; i++)
        ('T${i + 1}', (data!['temperatures_c'] as List)[i] as num),
    ];
    return Column(children: [
        if (demo || stale) card(context, Text(demo ? '模拟电池 · 非真实硬件数据' : '最后读数 · 当前数据未更新',
          style: const TextStyle(color: Color(0xffb97b19), fontSize: 12))),
        card(context, Column(children: [
          Row(children: [Expanded(child: Text(meter ? '蓝宝电量计' : '蚂蚁 BMS',
            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 15, fontWeight: FontWeight.w600))),
            TextButton(onPressed: onConnect, child: Text(connection))]),
          info(context, '设备名称', name),
          info(context, '运行时间', elapsedSeconds(data?['runtime_s'] as num?)),
          info(context, '硬件版本', meter ? (data?['hardware']?.toString() ?? '--') : (identity['硬件版本'] ?? '--')),
          info(context, '软件版本', meter ? (data?['firmware']?.toString() ?? '--') : (identity['软件版本'] ?? '--')),
          info(context, '电池类型', batteryChemistry(data?['battery_type'] as num?)),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: Column(children: [
              stateRow(context, '电池状态', state, data?['state'] == null ? null : true),
              if (!meter) stateRow(context, '充电 MOS', mos('charge_mos'), data?['charge_mos'] == null ? null : data!['charge_mos'] == 1),
              if (!meter) stateRow(context, '放电 MOS', mos('discharge_mos'), data?['discharge_mos'] == null ? null : data!['discharge_mos'] == 1),
              if (!meter) stateRow(context, '均衡状态', balanceText(data), data?['balance_state'] == null ? null : data!['balance_state'] != 0),
              if (meter) const Text('中继只读\n不提供 MOS / 均衡', style: TextStyle(fontSize: 11, color: Color(0xff8b99a4))),
            ])),
            const SizedBox(width: 14),
            Expanded(child: Column(children: [
              SizedBox(height: 116, width: double.infinity, child: Stack(children: [
                Positioned.fill(child: CustomPaint(painter: SocGaugePainter(data?['soc'] as num?, color: Theme.of(context).colorScheme.primary, track: Theme.of(context).colorScheme.outlineVariant))),
                Align(alignment: const Alignment(0, .05), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('SOC', style: TextStyle(color: Color(0xff8796a5), fontSize: 12)),
                  Text('${number('soc', 0)}%', style: TextStyle(fontSize: 30, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                ])),
              ])),
              Text('总容量 ${number('capacity_ah', 1)} Ah', style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 4), Text('剩余 ${number('remaining_ah', 1)} Ah', style: const TextStyle(fontSize: 11)),
            ])),
          ]),
        ])),
        card(context, LayoutBuilder(builder: (_, constraints) {
          final columns = constraints.maxWidth >= 500 ? 4 : constraints.maxWidth >= 300 ? 3 : 2;
          return Wrap(spacing: 12, runSpacing: 24, children: metrics.map((m) => SizedBox(
            width: (constraints.maxWidth - (columns - 1) * 12) / columns,
            child: smallMetric(context, m.$1, m.$2, m.$3, m.$4, m.$5))).toList());
        })),
        card(context, Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: alarms(context, '保护信息', decodeBmsBits(data?['protection_bits'] as String?))),
          const SizedBox(width: 16),
          Expanded(child: alarms(context, '告警信息', decodeBmsBits(data?['warning_bits'] as String?, warning: true))),
        ])),
        card(context, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('温度', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          if (sensors.isEmpty) const Text('设备未提供温度', style: TextStyle(fontSize: 12)),
          Wrap(spacing: 18, runSpacing: 10, children: sensors.map((sensor) => Column(children: [
            Text(sensor.$1, style: const TextStyle(color: Color(0xff82909d), fontSize: 12)),
            const SizedBox(height: 5), Text(temperatureText(sensor.$2), style: const TextStyle(fontSize: 14)),
            if (sensor.$2 == -40) const Text('疑似未接', style: TextStyle(fontSize: 9, color: Color(0xff9b8b78))),
          ])).toList()),
        ])),
        card(context, Column(children: [
          Row(children: [Icon(Icons.speed, color: Theme.of(context).colorScheme.primary, size: 20), const SizedBox(width: 8),
            const Expanded(child: Text('GPS 车速', style: TextStyle(fontSize: 13))),
            Text('${gpsSpeed?.toStringAsFixed(1) ?? "--"} km/h', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 18)),
            Switch(value: gpsEnabled, onChanged: onGps)]),
          Align(alignment: Alignment.centerLeft, child: Text(gpsDetail, style: const TextStyle(fontSize: 11, color: Color(0xff82909d)))),
        ])),
        card(context, Wrap(spacing: 8, runSpacing: 6, children: [
          TextButton.icon(onPressed: onCells, icon: const Icon(Icons.battery_full), label: const Text('单体电压')),
          TextButton.icon(onPressed: onRecords, icon: const Icon(Icons.show_chart), label: const Text('充放电记录')),
          TextButton.icon(onPressed: onControl, icon: const Icon(Icons.tune), label: const Text('BMS 控制')),
          TextButton.icon(onPressed: onDetails, icon: const Icon(Icons.info_outline), label: const Text('版本 / 参数')),
        ])),
      ]);
  }
}

class SocGaugePainter extends CustomPainter {
  final num? soc;
  final Color color, track;
  SocGaugePainter(this.soc, {this.color = BatteryDashboard.blue, this.track = const Color(0xffe5eaf0)});
  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width / 2 - 8, size.height * .58);
    final center = Offset(size.width / 2, size.height * .76);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 10..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, paint..color = track);
    if (soc != null) canvas.drawArc(rect, math.pi, math.pi * soc!.toDouble().clamp(0, 100) / 100,
        false, paint..color = color);
  }
  @override
  bool shouldRepaint(covariant SocGaugePainter old) => old.soc != soc || old.color != color || old.track != track;
}
