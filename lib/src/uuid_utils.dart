import 'dart:io';

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
}