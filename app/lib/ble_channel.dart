/// Bluetooth assigned UUIDs have equivalent 16, 32 and 128-bit representations.
String normalizeBleUuid(String value) {
  final hex = value.toLowerCase().replaceAll('-', '');
  if (!RegExp(r'^[0-9a-f]+$').hasMatch(hex))
    throw FormatException('Invalid BLE UUID', value);
  return switch (hex.length) {
    4 => '0000${hex}00001000800000805f9b34fb',
    8 => '${hex}00001000800000805f9b34fb',
    32 => hex,
    _ => throw FormatException('Invalid BLE UUID length', value),
  };
}

bool sameBleUuid(String a, String b) =>
    normalizeBleUuid(a) == normalizeBleUuid(b);

class BleCharacteristicInfo {
  final String uuid;
  final bool writable, notifiable;
  const BleCharacteristicInfo(
    this.uuid, {
    required this.writable,
    required this.notifiable,
  });
}

class BleServiceInfo {
  final String uuid;
  final List<BleCharacteristicInfo> characteristics;
  const BleServiceInfo(this.uuid, this.characteristics);
}

class BleChannelMatch {
  final int serviceIndex, writeIndex, notifyIndex;
  final bool standardService;
  const BleChannelMatch(
    this.serviceIndex,
    this.writeIndex,
    this.notifyIndex,
    this.standardService,
  );
}

/// Match only the selected ANT characteristic pair; never choose arbitrary writable services.
BleChannelMatch? matchBleChannel(
  List<BleServiceInfo> services,
  String writer,
  String reader,
) {
  for (final preferStandard in [true, false]) {
    for (var i = 0; i < services.length; i++) {
      final service = services[i];
      final standard = sameBleUuid(service.uuid, 'FFE0');
      if (standard != preferStandard) continue;
      final w = service.characteristics.indexWhere(
        (c) => sameBleUuid(c.uuid, writer) && c.writable,
      );
      final n = service.characteristics.indexWhere(
        (c) => sameBleUuid(c.uuid, reader) && c.notifiable,
      );
      if (w >= 0 && n >= 0) return BleChannelMatch(i, w, n, standard);
    }
  }
  return null;
}
