import 'package:device_info_plus/device_info_plus.dart';
import 'package:fingerprint/src/uuid_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidUUID {
  static const MethodChannel _channel = MethodChannel('fingerprint');

  static Future<String?> getSystemUUID() async {
    try {
      final id = await _channel.invokeMethod<String>('getPersistentDeviceId');
      if (id != null && id.isNotEmpty) return id;
    } catch (e) {
      debugPrint('Android persistent UUID channel error: $e');
    }

    // Fallback Dart: ANDROID_ID qua device_info_plus
    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final id = androidInfo.id;
      if (id.isNotEmpty && id != '9774d56d682e549c') return id;
    } catch (e) {
      debugPrint('Android ID fallback error: $e');
    }
    return null;
  }

  static Future<Map<String, String?>> getFingerprint() async {
    final uuid = await getSystemUUID();
    final ip = await UUIDUtils.getPrimaryIPv4();
    final uuidHashed = uuid != null ? UUIDUtils.hashString(uuid) : null;
    return {'uuid': uuid, 'uuid_hashed': uuidHashed, 'ip': ip};
  }
}
