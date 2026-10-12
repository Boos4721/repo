// Dictionaries derived from maibms BitDict.kt (MIT); see NOTICE.md.
const protectionNames = <int, String>{
  0: '设置电芯类型',
  1: '单体过压保护',
  2: '单体2级过压',
  3: '总压过压保护',
  4: '单体欠压保护',
  5: '单体2级欠压',
  6: '总压欠压保护',
  7: '单体压差保护',
  8: '电池高温充电',
  9: '电池高温放电',
  10: 'MOS高温保护',
  11: '电池低温充电',
  12: '电池低温放电',
  13: '充电过流保护',
  14: '放电过流保护',
  15: '放电二级过流',
  16: '短路保护',
  17: '控制放电开关1',
  18: '控制放电开关2',
  19: '控制放电开关3',
  20: '控制放电开关4',
  21: '控制充电开关1',
  22: '控制充电开关2',
  23: '控制充电开关3',
  24: '控制充电开关4',
  25: '均衡线掉串',
  26: '电流异常',
  27: '放电MOS异常',
  28: '充电MOS异常',
  29: '内部通信异常',
  30: '预充失败',
  31: 'BMS初始化',
  32: '自检1',
  33: '自检2',
  34: '充电通信检测',
  35: 'GPS丢失保护',
  36: '防打火工作',
  37: '自检3',
  38: '请升级固件',
  39: '继电器预充失败',
  40: '继电器粘连',
  41: '放电保险异常',
  42: '充电保险异常',
  43: '模组失联',
  44: '可用时间到达',
  45: '预放MOS异常',
  46: '预充MOS异常',
  47: '负载锁定开启',
  48: '采集接收模式',
  50: '采集Boot模式',
};
const warningNames = <int, String>{
  0: '单体过压告警',
  1: '总压过压告警',
  2: '单体欠压告警',
  3: '总压欠压告警',
  4: '单体压差告警',
  5: '电池充电高温',
  6: '电池放电高温',
  7: '电池充电低温',
  8: '电池放电低温',
  9: 'MOS高温告警',
  10: '充电过流告警',
  11: '放电过流告警',
  12: 'SOC一级告警',
  13: 'SOC二级告警',
  14: '单体效验异常',
  15: '总压效验异常',
  16: '预充失败',
  17: '电池充满',
  18: '电池充电中',
  19: '电池放电中',
  20: 'CAN充电连接',
  21: '485充电连接',
  22: '充电连接CUR',
  23: '充电MOS开',
  24: '放电MOS开',
  25: '均衡开',
  26: '待机中',
  27: '均衡极限',
  28: '均衡压差',
  29: '均衡自动',
  30: '均衡过温',
  31: '电压保护',
  32: '温度保护',
  33: '系统错误',
  34: 'GPS通信丢失',
  35: '均衡检测',
  36: '电加热开启',
  37: '强制输出中',
  38: '蓝牙关闭',
  39: '继电器预充中',
  40: 'MOS预充中',
  41: '充电继电器开',
  42: '放电继电器开',
  43: '时钟异常',
  44: '强制开启充电',
  45: '调试模式',
  46: '可用时间到达',
  47: '可用即将到达',
  48: '防打火中',
  49: '即将低压关机',
  50: '蚂蚁充电连接',
  51: '均衡等待',
  52: '测试模式',
  53: '内部通信不稳定',
};
const warningStateBits = {17,18,19,20,21,22,23,24,25,26,27,28,29,30,35,36,37,39,40,41,42,45,48,50,51,52};

List<String> decodeBmsBits(String? hex, {bool warning = false, bool states = false}) {
  if (hex == null) return ['设备未提供'];
  final bits = BigInt.tryParse(hex, radix: 16);
  if (bits == null) return ['位域格式无效'];
  final dict = warning ? warningNames : protectionNames;
  final result = <String>[];
  for (var i = 0; i < 64; i++) {
    if ((bits & (BigInt.one << i)) == BigInt.zero) continue;
    if (warning && warningStateBits.contains(i) != states) continue;
    result.add('bit$i · ${dict[i] ?? "未知位（保留）"}');
  }
  return result;
}

String batteryChemistry(num? value) => switch(value?.toInt()) {
  0xfaf1 => '三元锂', 0xfaf2 => '磷酸铁锂', 0xfaf3 => '钛酸锂',
  0xfaf6 => '钠电', 0xfaf7 => '磷酸锰铁锂', null => '设备未提供',
  _ => '未知编码 0x${value!.toInt().toRadixString(16).toUpperCase()}',
};

String elapsedSeconds(num? value) {
  if (value == null) return '--';
  final seconds = value.toInt();
  if (seconds < 0) return '无效时间';
  return '${seconds ~/ 86400}天 ${seconds % 86400 ~/ 3600}小时 ${seconds % 3600 ~/ 60}分钟';
}

String parameterAscii(List<int> bytes) => String.fromCharCodes(bytes
    .takeWhile((b) => b != 0).where((b) => b >= 32 && b <= 126)).trim();

Map<String, num>? activeBalance(Map<String, dynamic>? snapshot) {
  final type = snapshot?['bms_type'];
  final raw = snapshot?['balance_raw'];
  if (![1, 2].contains(type) || raw is! int) return null;
  var current = raw >> 8 & 255;
  if (current >= 128) current -= 256;
  return {'cell': raw >> 24 & 255, 'resistance_mohm': (raw >> 16 & 255) / 100,
    'current_a': current / (type == 2 ? 10 : 100), 'fault_raw': raw & 255};
}

const balanceParameterNames = <int, String>{
  140: '均衡极限电压', 142: '充电均衡起控电压', 144: '均衡启动压差',
  146: '均衡结束压差', 148: '均衡电流（原始值）', 150: '均衡充电电流',
};

String balanceParameterValue(int address, int? value) {
  if (value == null) return '--';
  if (address <= 146) return '${(value / 1000).toStringAsFixed(3)} V';
  if (address == 150) return '${(value / 10).toStringAsFixed(1)} A';
  return '$value';
}

