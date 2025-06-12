import 'dart:io';

import 'package:fingerprint/src/windows_uuid.dart';

import 'linux_uuid.dart';
import 'macos_uuid.dart';

class FingerPrintUUID {
  static Future<String?> getUUID() async {
    if (Platform.isWindows) {
      return await WindowsSystemUUID.getSystemUUID();
    }
    if (Platform.isMacOS) {
      return await MacOSUUID.getSystemUUID();
    }
    if (Platform.isLinux) {
      return await LinuxUUID.getSystemUUID();
    }

    return null;
  }
}
