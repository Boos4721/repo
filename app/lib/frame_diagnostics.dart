String safeTxSummary(List<int> bytes, {required bool meter}) {
  if (meter) return 'TX 蓝宝读取（${bytes.length} 字节，匹配码已隐藏）';
  if (bytes.length < 6 || bytes[0] != 0x7e) return 'TX ${bytes.length} 字节（内容隐藏）';
  if (bytes[2] == 0x23) return 'TX 权限校验（密码载荷已隐藏）';
  if (![0x01, 0x02, 0x51].contains(bytes[2])) return 'TX ${bytes.length} 字节（未知载荷隐藏）';
  return 'TX ${bytes.map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ").toUpperCase()}';
}

String safeRxSummary(List<int> bytes, {required bool meter, required bool commandBusy}) {
  if (meter || commandBusy || bytes.length < 6 || bytes[0] != 0x7e || bytes[1] != 0xa1 ||
      ![0x11, 0x12, 0x61, 0x43].contains(bytes[2])) {
    return 'RX ${bytes.length} 字节（载荷隐藏）';
  }
  // Notifications may split credential echoes; never log arbitrary RX payload bytes.
  return 'RX ${bytes.length} 字节 · 帧头 ${bytes.take(6).map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ").toUpperCase()} · 载荷隐藏';
}
