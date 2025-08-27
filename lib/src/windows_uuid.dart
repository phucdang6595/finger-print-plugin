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
