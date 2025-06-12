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
}
