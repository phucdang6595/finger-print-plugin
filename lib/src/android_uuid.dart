import 'package:device_info_plus/device_info_plus.dart';
import 'package:fingerprint/src/uuid_utils.dart';

class AndroidUUID {
  static Future<String?> getSystemUUID() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    return androidInfo.id; // androidId
  }

  // Trả về dữ liệu chung gồm uuid và ip chính (IPv4)
  static Future<Map<String, String?>> getFingerprint() async {
    final uuid = await getSystemUUID();
    final ip = await UUIDUtils.getPrimaryIPv4();
    final uuidHashed = uuid != null ? UUIDUtils.hashString(uuid) : null;
    return {'uuid': uuid, 'uuid_hashed': uuidHashed, 'ip': ip};
  }
}
