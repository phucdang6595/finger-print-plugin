import 'dart:async';
import 'dart:io';

import 'package:fingerprint/src/uuid_utils.dart';
import 'package:fingerprint/src/windows_registry.dart';
import 'package:flutter/foundation.dart';

class WindowsSystemUUID {
  /// SMBIOS UUID giả / không dùng được trên nhiều máy (OEM lỗi, VM, v.v.)
  static const _invalidUuids = {
    '00000000-0000-0000-0000-000000000000',
    'ffffffff-ffff-ffff-ffff-ffffffffffff',
  };

  /// Thứ tự lấy UUID (đã tối ưu cho Win 10/11 Pro quản lý bằng GPO/EDR):
  ///
  /// 1. **MachineGuid qua Win32 API (FFI)** — nhanh, luôn có, không spawn tiến
  ///    trình con nên không dính EDR/AV chặn PowerShell/WMIC; duy nhất theo mỗi
  ///    bản cài Windows và ổn định qua reboot/update. Đây là nguồn tin cậy nhất.
  /// 2. **MachineGuid qua `reg.exe`** — fallback nếu FFI vì lý do nào đó lỗi.
  /// 3. **SMBIOS UUID qua CIM** — chỉ dùng làm phương án phụ, vì SMBIOS UUID hay
  ///    TRÙNG trên các fleet cài từ cùng một image doanh nghiệp / VM.
  /// 4. **SMBIOS UUID qua WMI** — cho máy cũ hơn.
  /// 5. **UUID local theo user profile** — last resort (ổn định qua các lần chạy
  ///    nhờ lưu file).
  ///
  /// `wmic` đã bị gỡ khỏi Windows 11 24H2+ nên KHÔNG còn nằm trên đường đi chính
  /// (chỉ giữ lại trong [validateUUID] để chẩn đoán).
  static Future<String?> getSystemUUID() async {
    // 1) MachineGuid qua FFI.
    final ffiRaw = WindowsRegistry.readMachineGuid();
    if (ffiRaw != null) {
      final ffiGuid = _normalizeUuid(ffiRaw);
      if (ffiGuid != null) return ffiGuid;
    }

    // 2) MachineGuid qua reg.exe.
    final machineGuid = await _getMachineGuidFromRegistry();
    if (machineGuid != null) return machineGuid;

    // 3) SMBIOS UUID (CIM).
    final cimResult = await _getUUIDWithCim();
    if (cimResult != null) return cimResult;

    // 4) SMBIOS UUID (WMI).
    final psResult = await _getUUIDWithPowerShell();
    if (psResult != null) return psResult;

    // 5) Last resort.
    return UUIDUtils.getOrCreateLocalDeviceId();
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

  // Validate UUID: kiểm tra định dạng và so khớp giữa nhiều nguồn.
  // Dùng để chẩn đoán: log map `sources` để biết máy nào đang thiếu nguồn nào.
  static Future<Map<String, dynamic>> validateUUID() async {
    final sources = <String, String?>{};

    try {
      final raw = WindowsRegistry.readMachineGuid();
      sources['machine_guid_ffi'] = raw == null ? null : _normalizeUuid(raw);
    } catch (_) {}

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

    // Ưu tiên MachineGuid (duy nhất per-install & ổn định) trước SMBIOS.
    final preferred = sources['machine_guid_ffi'] ??
        sources['machine_guid'] ??
        sources['cim'] ??
        sources['powershell'] ??
        sources['wmic'];
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
    final output = await UUIDUtils.runProcessForStdout(
      'powershell',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        command,
      ],
      timeout: const Duration(seconds: 6),
    );
    if (output == null) {
      debugPrint('$label UUID: no output (blocked/timeout/non-zero exit)');
      return null;
    }
    return _normalizeUuid(output);
  }

  static Future<String?> _getUUIDWithWmic() async {
    final output = await UUIDUtils.runProcessForStdout(
      'wmic',
      ['path', 'win32_computersystemproduct', 'get', 'UUID'],
      timeout: const Duration(seconds: 6),
    );
    if (output == null) return null;
    final lines = output.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      final normalized = _normalizeUuid(line);
      if (normalized != null) return normalized;
    }
    return null;
  }

  /// MachineGuid từ Cryptography qua `reg.exe` — fallback cho bản FFI.
  static Future<String?> _getMachineGuidFromRegistry() async {
    final output = await UUIDUtils.runProcessForStdout(
      'reg',
      [
        'query',
        r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography',
        '/v',
        'MachineGuid',
      ],
      timeout: const Duration(seconds: 4),
    );
    if (output == null) return null;
    final lines = output.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.contains('REG_SZ')) continue;
      final parts = trimmed.split('REG_SZ');
      if (parts.length > 1) {
        final normalized = _normalizeUuid(parts[1]);
        if (normalized != null) return normalized;
      }
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
