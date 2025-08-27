import 'dart:io';

import 'package:fingerprint/src/windows_uuid.dart';

import 'linux_uuid.dart';
import 'macos_uuid.dart';

class FingerPrintUUID {
  // Trả về dữ liệu chung gồm uuid và ip chính (IPv4)
  static Future<Map<String, String?>> getUUID() async {
    if (Platform.isWindows) {
      return await WindowsSystemUUID.getFingerprint();
    }

    if (Platform.isMacOS) {
      return await MacOSUUID.getFingerprint();
    }

    if (Platform.isLinux) {
      final uuid = await LinuxUUID.getSystemUUID();
      final ip = await _getPrimaryIPv4();
      return {'uuid': uuid, 'ip': ip};
    }

    return {'uuid': null, 'ip': null};
  }

  static Future<String?> _getPrimaryIPv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      // ignore
    }
    return null;
  }
}
