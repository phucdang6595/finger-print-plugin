import 'dart:io';

class WindowsSystemUUID {
  static Future<String?> getSystemUUID() async {
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
        if (trimmed.isNotEmpty && trimmed != 'UUID' && trimmed.contains('-')) {
          return trimmed;
        }
      }
    } else {
      print('window uuid error: ${result.stderr}');
      return null;
    }

    return null;
  }
}
