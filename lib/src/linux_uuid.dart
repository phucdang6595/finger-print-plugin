import 'dart:io';

import 'package:fingerprint/src/uuid_utils.dart';
import 'package:flutter/foundation.dart';

class LinuxUUID {
  static Future<String?> getSystemUUID() async {
    final dmi = await _readProductUuid();
    if (dmi != null) return dmi;

    final machineId = await _readMachineId('/etc/machine-id');
    if (machineId != null) return machineId;

    final dbusId = await _readMachineId('/var/lib/dbus/machine-id');
    if (dbusId != null) return dbusId;

    // Last resort: UUID local theo user
    return UUIDUtils.getOrCreateLocalDeviceId();
  }

  static Future<Map<String, String?>> getFingerprint() async {
    final uuid = await getSystemUUID();
    final ip = await UUIDUtils.getPrimaryIPv4();
    final uuidHashed = uuid != null ? UUIDUtils.hashString(uuid) : null;
    return {'uuid': uuid, 'uuid_hashed': uuidHashed, 'ip': ip};
  }

  static Future<String?> _readProductUuid() async {
    try {
      final file = File('/sys/class/dmi/id/product_uuid');
      if (!await file.exists()) return null;
      final uuid = (await file.readAsString()).trim();
      if (UUIDUtils.isUsableUuid(uuid)) return uuid;
    } catch (e) {
      debugPrint('linux product_uuid error: $e');
    }
    return null;
  }

  static Future<String?> _readMachineId(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return UUIDUtils.machineIdToUuid(await file.readAsString());
    } catch (e) {
      debugPrint('linux machine-id ($path) error: $e');
    }
    return null;
  }
}
