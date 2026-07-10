import 'dart:async';
import 'dart:io';

import 'package:fingerprint/src/uuid_utils.dart';
import 'package:flutter/foundation.dart';

class WindowsSystemUUID {
  /// SMBIOS UUID giả / không dùng được trên nhiều máy (OEM lỗi, VM, v.v.)
  static const _invalidUuids = {
    '00000000-0000-0000-0000-000000000000',
    'ffffffff-ffff-ffff-ffff-ffffffffffff',
  };

  static Future<String?> getSystemUUID() async {
    // 1. Get-CimInstance (Windows 10/11 hiện đại; thay Get-WmiObject)
    final cimResult = await _getUUIDWithCim();
    if (cimResult != null) return cimResult;

    // 2. Get-WmiObject (máy cũ hơn)
    final psResult = await _getUUIDWithPowerShell();
    if (psResult != null) return psResult;

    // 3. wmic — đã bị gỡ trên nhiều bản Windows 11 24H2+
    final wmicResult = await _getUUIDWithWmic();
    if (wmicResult != null) return wmicResult;

    // 4. MachineGuid — ổn định, không cần admin, luôn có trên Windows
    return await _getMachineGuidFromRegistry();
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
      sources['cim'] = await _getUUIDWithCim();
    } catch (_) {}

    try {
      sources['powershell'] = await _getUUIDWithPowerShell();
    } catch (_) {}

    try {
      sources['wmic'] = await _getUUIDWithWmic();
    } catch (_) {}

    try {
      sources['machine_guid'] = await _getMachineGuidFromRegistry();
    } catch (_) {}

    // UUID ưu tiên theo thứ tự (SMBIOS trước, MachineGuid sau)
    final preferred = sources['cim'] ??
        sources['powershell'] ??
        sources['wmic'] ??
        sources['machine_guid'];
    final formatValid = UUIDUtils.isValidUUIDFormat(preferred);

    // So khớp các nguồn SMBIOS (không so MachineGuid vì khác nguồn)
    final smbiosValues = [
      sources['cim'],
      sources['powershell'],
      sources['wmic'],
    ].whereType<String>().toList();
    bool sourcesMatch = true;
    if (smbiosValues.isNotEmpty) {
      final first = smbiosValues.first;
      sourcesMatch = smbiosValues.every(
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

  static Future<String?> _getUUIDWithCim() async {
    return _runPowerShellAndParse(
      '(Get-CimInstance -ClassName Win32_ComputerSystemProduct).UUID',
      'CIM',
    );
  }

  static Future<String?> _getUUIDWithPowerShell() async {
    return _runPowerShellAndParse(
      '(Get-WmiObject -Class Win32_ComputerSystemProduct).UUID',
      'WMI',
    );
  }

  static Future<String?> _runPowerShellAndParse(
    String command,
    String label,
  ) async {
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          command,
        ],
      ).timeout(const Duration(seconds: 15));

      if (result.exitCode == 0) {
        return _normalizeUuid(result.stdout.toString());
      }
      debugPrint('$label UUID stderr: ${result.stderr}');
    } catch (e) {
      debugPrint('$label UUID error: $e');
    }
    return null;
  }

  static Future<String?> _getUUIDWithWmic() async {
    try {
      final result = await Process.run(
        'wmic',
        [
          'path',
          'win32_computersystemproduct',
          'get',
          'UUID',
        ],
      ).timeout(const Duration(seconds: 15));

      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split(RegExp(r'\r?\n'));
        for (final line in lines) {
          final normalized = _normalizeUuid(line);
          if (normalized != null) return normalized;
        }
      }
    } catch (e) {
      debugPrint('WMIC UUID error: $e');
    }
    return null;
  }

  /// MachineGuid từ Cryptography — ID máy Windows ổn định nhất khi SMBIOS lỗi.
  static Future<String?> _getMachineGuidFromRegistry() async {
    try {
      final result = await Process.run(
        'reg',
        [
          'query',
          r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography',
          '/v',
          'MachineGuid',
        ],
      ).timeout(const Duration(seconds: 10));

      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split(RegExp(r'\r?\n'));
        for (final line in lines) {
          final trimmed = line.trim();
          if (!trimmed.contains('REG_SZ')) continue;
          final parts = trimmed.split('REG_SZ');
          if (parts.length > 1) {
            return _normalizeUuid(parts[1]);
          }
        }
      }
    } catch (e) {
      debugPrint('MachineGuid registry error: $e');
    }
    return null;
  }

  /// Chuẩn hóa + loại UUID giả / không hợp lệ.
  static String? _normalizeUuid(String raw) {
    var value = raw.trim();
    // Bỏ BOM / null / header WMIC
    value = value.replaceAll('\uFEFF', '').replaceAll('\u0000', '');
    if (value.isEmpty || value.toUpperCase() == 'UUID') return null;

    // Lấy dòng đầu nếu PowerShell in nhiều dòng
    value = value.split(RegExp(r'\r?\n')).first.trim();

    if (!UUIDUtils.isValidUUIDFormat(value)) return null;
    if (_invalidUuids.contains(value.toLowerCase())) return null;
    return value;
  }
}
