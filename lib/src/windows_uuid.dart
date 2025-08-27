import 'dart:io';

class WindowsSystemUUID {
  static Future<String?> getSystemUUID() async {
    // Thử PowerShell trước
    final psResult = await _getUUIDWithPowerShell();
    if (psResult != null) return psResult;

    // Fallback với wmic
    final wmicResult = await _getUUIDWithWmic();
    if (wmicResult != null) return wmicResult;

    // Fallback cuối cùng với registry
    return await _getUUIDFromRegistry();
  }

  // Trả về dữ liệu chung gồm uuid và ip chính (IPv4)
  static Future<Map<String, String?>> getFingerprint() async {
    final uuid = await getSystemUUID();
    final ip = await getPrimaryIPv4();
    return {'uuid': uuid, 'ip': ip};
  }

  // Lấy IPv4 đầu tiên (không phải loopback)
  static Future<String?> getPrimaryIPv4() async {
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
      print('Get primary IPv4 error: $e');
    }
    return null;
  }

  static Future<String?> _getUUIDWithPowerShell() async {
    try {
      final result = await Process.run('powershell', [
        '-Command',
        'Get-WmiObject -Class Win32_ComputerSystemProduct | Select-Object -ExpandProperty UUID',
      ], runInShell: true);

      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        if (output.isNotEmpty && output.contains('-')) {
          return output;
        }
      }
    } catch (e) {
      print('PowerShell UUID error: $e');
    }
    return null;
  }

  static Future<String?> _getUUIDWithWmic() async {
    try {
      final result = await Process.run('wmic', [
        'path',
        'win32_computersystemproduct',
        'get',
        'UUID',
      ], runInShell: true);

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final lines = output.split('\n');
        for (String line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty &&
              trimmed != 'UUID' &&
              trimmed.contains('-')) {
            return trimmed;
          }
        }
      }
    } catch (e) {
      print('WMIC UUID error: $e');
    }
    return null;
  }

  static Future<String?> _getUUIDFromRegistry() async {
    try {
      final result = await Process.run('reg', [
        'query',
        'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion',
        '/v',
        'ProductId',
      ], runInShell: true);

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final lines = output.split('\n');
        for (String line in lines) {
          if (line.contains('ProductId')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 3) {
              return parts[2].trim();
            }
          }
        }
      }
    } catch (e) {
      print('Registry UUID error: $e');
    }
    return null;
  }
}
