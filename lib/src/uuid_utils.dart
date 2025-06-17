import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class UUIDUtils{
  static void openSystemSettings() async {
    if (Platform.isMacOS) {
      await Process.run('open', ['x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles']);
    } else if (Platform.isWindows) {
      await Process.run('start', ['ms-settings:privacy-customdevices'], runInShell: true);
    } else if (Platform.isLinux) {
      // Tùy distro, chỉ mở control center cơ bản
      await Process.run('gnome-control-center', []);
    }
  }

  static Future<void> getSystemInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isWindows) {
      final info = await deviceInfo.windowsInfo;
      return {
        'computerName': info.computerName,

      }
    } else if (Platform.isMacOS) {
      final info = await deviceInfo.macOsInfo;
      return {
        'computerName': info.computerName,
        'model': info.model,
        'modelName': info.modelName,
      }
    } else if (Platform.isLinux) {
      final info = await deviceInfo.linuxInfo;
    }
  }
}