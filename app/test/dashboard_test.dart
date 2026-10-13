import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ant_bms/dashboard.dart';

Widget dashboard({bool meter = false, Map<String, dynamic>? data}) => MaterialApp(home: Scaffold(
  body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(12), child: BatteryDashboard(
    data: data, identity: const {}, name: meter ? 'BlueBabeQC6528' : 'ANT@TEST-BOARD',
    connection: '测试', meter: meter, stale: data == null, demo: false,
    gpsEnabled: false, gpsSpeed: null, gpsDetail: 'GPS 未开启', onGps: null,
    onConnect: null, onCells: null, onRecords: null, onControl: null, onDetails: null)))));

void main() {
  for (final width in [320.0, 375.0, 768.0]) {
    testWidgets('dashboard fits $width logical pixels', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(dashboard(data: {
        'soc': 55, 'voltage_v': 78.07, 'current_a': 0, 'power_w': 7,
        'remaining_ah': 94.7, 'capacity_ah': 170, 'state': 3, 'charge_mos': 1, 'discharge_mos': 1,
        'balance_state': 0, 'max_cell_v': 3.727, 'min_cell_v': 3.720, 'average_v': 3.723,
        'delta_v': .007, 'cycle_ah': 3267.9, 'battery_type': 0xfaf1,
        'temperatures_c': [25, -40], 'mos_temperature_c': 24, 'balance_temperature_c': 25,
        'protection_bits': '0000000000000000', 'warning_bits': '0000000001800000',
      }));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('55%'), findsOneWidget);
      expect(find.text('总容量 170.0 Ah'), findsOneWidget);
      expect(find.text('充电 MOS'), findsOneWidget);
    });
  }
  testWidgets('meter does not fabricate MOS or balancing', (tester) async {
    await tester.pumpWidget(dashboard(meter: true, data: {'soc': 55, 'capacity_ah': 170,
      'remaining_ah': 94.7, 'temperatures_c': [25]}));
    expect(tester.takeException(), isNull);
    expect(find.text('充电 MOS'), findsNothing);
    expect(find.text('均衡状态'), findsNothing);
    expect(find.text('剩余 94.7 Ah'), findsOneWidget);
  });
  testWidgets('no data stays unknown and preview actions are disabled', (tester) async {
    await tester.pumpWidget(dashboard());
    expect(tester.takeException(), isNull);
    expect(find.text('--%'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(find.text('设备未提供'), findsWidgets);
  });
}
