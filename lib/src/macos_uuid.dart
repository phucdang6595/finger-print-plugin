import 'dart:io';

class MacOSUUID {
  static Future<String?> getSystemUUID() async {
    final result = await Process.run('ioreg', [
      '-d2',
      '-c',
      'IOPlatformExpertDevice',
    ], runInShell: true);

    if (result.exitCode == 0) {
      final output = result.stdout.toString();
      final lines = output.split('\n');

      for (String line in lines) {
        if (line.contains('IOPlatformUUID')) {
          final regex = RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"');
          final match = regex.firstMatch(line);
          if (match != null) {
            return match.group(1);
          }
        }
      }
    } else {
      print('macos uuid error: ${result.stderr}');
      return null;
    }

    return null;
  }

  // Trả về dữ liệu chung gồm uuid và ip chính (IPv4)
  static Future<Map<String, String?>> getFingerprint() async {
    final uuid = await getSystemUUID();
    final ip = await _getPrimaryIPv4();
    return {'uuid': uuid, 'ip': ip};
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
