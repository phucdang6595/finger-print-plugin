import 'dart:io';

class LinuxUUID {
  static Future<String?> getSystemUUID() async {
    final result = await Process.run('cat', [
      '/sys/class/dmi/id/product_uuid',
    ], runInShell: true);

    if (result.exitCode == 0) {
      final uuid = result.stdout.toString().trim();
      if (uuid.isNotEmpty && uuid != '00000000-0000-0000-0000-000000000000') {
        return uuid;
      }
    } else {
      print('linux uuid error: ${result.stderr}');
      return null;
    }

    return null;
  }
}
