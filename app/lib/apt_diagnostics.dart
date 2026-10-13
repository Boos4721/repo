class AptPackets {
  final List<String> rows = [];
  int count = 0, bytes = 0;
  DateTime? lastReceived;
  void accept(List<int> packet) {
    if (packet.isEmpty) return;
    count++;
    bytes += packet.length;
    lastReceived = DateTime.now();
    final hex = packet.take(256).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ').toUpperCase();
    rows.insert(0, '${lastReceived!.toIso8601String()} RX ${packet.length}B $hex${packet.length > 256 ? ' …（截断）' : ''}');
    if (rows.length > 40) rows.removeLast();
  }
  void clear() { rows.clear(); count = bytes = 0; lastReceived = null; }
}
