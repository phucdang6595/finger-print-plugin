import 'dart:io';

import 'package:fingerprint/src/uuid_utils.dart';

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
    final uuidHashed = uuid != null ? UUIDUtils.hashString(uuid) : null;
    return {'uuid': uuid, 'uuid_hashed': uuidHashed, 'ip': ip};
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

  // Validate UUID cho macOS: kiểm tra định dạng và đối chiếu từ nhiều lệnh
  static Future<Map<String, dynamic>> validateUUID() async {
    final sources = <String, String?>{};

    try {
      sources['ioreg'] = await _uuidFromIOReg();
    } catch (_) {}

    try {
      sources['system_profiler'] = await _uuidFromSystemProfiler();
    } catch (_) {}

    // UUID ưu tiên theo ioreg trước, sau đó system_profiler
    final preferred = sources['ioreg'] ?? sources['system_profiler'];
    final formatValid = UUIDUtils.isValidUUIDFormat(preferred);

    // So khớp các nguồn không null
    final nonNullValues = sources.values.whereType<String>().toList();
    bool sourcesMatch = true;
    if (nonNullValues.isNotEmpty) {
      final first = nonNullValues.first;
      sourcesMatch = nonNullValues.every(
        (v) => v.trim().toLowerCase() == first.trim().toLowerCase(),
      );
    }

    return {
      'uuid': preferred,
      'uuid_hashed': preferred != null ? UUIDUtils.hashString(preferred) : null,
      'format_valid': formatValid,
      'sources_match': sourcesMatch,
      'sources': sources,
      'is_valid': formatValid && sourcesMatch,
    };
  }

  static Future<String?> _uuidFromIOReg() async {
    final result = await Process.run('ioreg', [
      '-d2',
      '-c',
      'IOPlatformExpertDevice',
    ], runInShell: true);
    if (result.exitCode == 0) {
      final output = result.stdout.toString();
      final lines = output.split('\n');
      for (final line in lines) {
        if (line.contains('IOPlatformUUID')) {
          final regex = RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"');
          final match = regex.firstMatch(line);
          if (match != null) return match.group(1);
        }
      }
    }
    return null;
  }

  static Future<String?> _uuidFromSystemProfiler() async {
    final result = await Process.run('system_profiler', ['SPHardwareDataType']);
    if (result.exitCode == 0) {
      final output = result.stdout.toString();
      final lines = output.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('Hardware UUID:')) {
          return trimmed.split(':').last.trim();
        }
      }
    }
    return null;
  }
}
