import 'dart:io';

import 'package:fingerprint/src/uuid_utils.dart';
import 'package:flutter/material.dart';

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
    final uuidHashed = uuid != null ? UUIDUtils.hashString(uuid) : null;
    return {'uuid': uuid, 'uuid_hashed': uuidHashed, 'ip': ip};
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
      debugPrint('Get primary IPv4 error: $e');
    }
    return null;
  }

  // Validate UUID: kiểm tra định dạng và so khớp giữa nhiều nguồn
  static Future<Map<String, dynamic>> validateUUID() async {
    final sources = <String, String?>{};

    try {
      sources['powershell'] = await _getUUIDWithPowerShell();
    } catch (_) {}

    try {
      sources['wmic'] = await _getUUIDWithWmic();
    } catch (_) {}

    try {
      sources['registry'] = await _getUUIDFromRegistry();
    } catch (_) {}

    // UUID ưu tiên theo thứ tự
    final preferred =
        sources['powershell'] ?? sources['wmic'] ?? sources['registry'];
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
      debugPrint('PowerShell UUID error: $e');
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
      debugPrint('WMIC UUID error: $e');
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
        // ProductId không phải UUID chuẩn, dùng làm tham chiếu phụ
        final lines = output.split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.contains('REG_SZ')) {
            final parts = trimmed.split('REG_SZ');
            if (parts.length > 1) {
              final value = parts[1].trim();
              return value; // Có thể không phải UUID, chỉ để tham chiếu
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Registry UUID error: $e');
    }
    return null;
  }
}
