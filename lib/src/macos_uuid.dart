import 'dart:io';

import 'package:fingerprint/src/uuid_utils.dart';
import 'package:flutter/foundation.dart';

class MacOSUUID {
  static Future<String?> getSystemUUID() async {
    final ioreg = await _uuidFromIOReg();
    if (ioreg != null) return ioreg;

    final profiler = await _uuidFromSystemProfiler();
    if (profiler != null) return profiler;

    // Last resort khi sandbox / quyền chặn hardware UUID
    return UUIDUtils.getOrCreateLocalDeviceId();
  }

  // Trả về dữ liệu chung gồm uuid và ip chính (IPv4)
  static Future<Map<String, String?>> getFingerprint() async {
    final uuid = await getSystemUUID();
    final ip = await UUIDUtils.getPrimaryIPv4();
    final uuidHashed = uuid != null ? UUIDUtils.hashString(uuid) : null;
    return {'uuid': uuid, 'uuid_hashed': uuidHashed, 'ip': ip};
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

    // So khớp các nguồn hardware (không so local fallback)
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
    try {
      final result = await Process.run('ioreg', [
        '-d2',
        '-c',
        'IOPlatformExpertDevice',
      ]);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final lines = output.split('\n');
        for (final line in lines) {
          if (line.contains('IOPlatformUUID')) {
            final regex = RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"');
            final match = regex.firstMatch(line);
            final value = match?.group(1);
            if (UUIDUtils.isUsableUuid(value)) return value;
          }
        }
      } else {
        debugPrint('macos ioreg error: ${result.stderr}');
      }
    } catch (e) {
      debugPrint('macos ioreg error: $e');
    }
    return null;
  }

  static Future<String?> _uuidFromSystemProfiler() async {
    try {
      final result = await Process.run('system_profiler', [
        'SPHardwareDataType',
      ]);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final lines = output.split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('Hardware UUID:')) {
            final value = trimmed.split(':').last.trim();
            if (UUIDUtils.isUsableUuid(value)) return value;
          }
        }
      }
    } catch (e) {
      debugPrint('macos system_profiler error: $e');
    }
    return null;
  }
}
