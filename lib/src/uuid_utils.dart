import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';

class UUIDUtils {
  static const _invalidUuids = {
    '00000000-0000-0000-0000-000000000000',
    'ffffffff-ffff-ffff-ffff-ffffffffffff',
  };

  static void openSystemSettings() async {
    if (Platform.isMacOS) {
      await Process.run('open', [
        'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles',
      ]);
    } else if (Platform.isWindows) {
      await Process.run('start', [
        'ms-settings:privacy-customdevices',
      ], runInShell: true);
    } else if (Platform.isLinux) {
      // Tùy distro, chỉ mở control center cơ bản
      await Process.run('gnome-control-center', []);
    }
  }

  static Future<Map<String, String>> getSystemInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isWindows) {
      final info = await deviceInfo.windowsInfo;
      return {'computerName': info.computerName};
    } else if (Platform.isMacOS) {
      final info = await deviceInfo.macOsInfo;
      return {
        'computerName': info.computerName,
        'model': info.model,
        'modelName': info.modelName,
      };
    } else if (Platform.isLinux) {
      final info = await deviceInfo.linuxInfo;
      return {'computerName': info.name};
    } else if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      return {
        'computerName': info.model,
        'model': info.model,
        'brand': info.brand,
        'device': info.device,
        'manufacturer': info.manufacturer,
        'version': info.version.release,
        'sdkInt': info.version.sdkInt.toString(),
      };
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      return {
        'computerName': info.name,
        'model': info.model,
        'systemName': info.systemName,
        'systemVersion': info.systemVersion,
        'localizedModel': info.localizedModel,
        'identifierForVendor': info.identifierForVendor ?? '',
      };
    }
    throw UnsupportedError('Unsupported platform');
  }

  // Hash chuỗi (ví dụ: UUID) bằng FNV-1a 32-bit
  static String hashString(String input) {
    final bytes = utf8.encode(input);
    int h1 = 0x811C9DC5; // seed
    for (final b in bytes) {
      h1 ^= b;
      h1 = (h1 * 0x01000193) & 0xFFFFFFFF; // FNV-1a 32-bit
    }
    // Trả về hex 8 ký tự, đủ gọn để dùng như khóa rút gọn
    return h1.toRadixString(16).padLeft(8, '0');
  }

  // Kiểm tra định dạng UUID chuẩn (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
  static bool isValidUUIDFormat(String? uuid) {
    if (uuid == null) return false;
    final regex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return regex.hasMatch(uuid.trim());
  }

  static bool isUsableUuid(String? uuid) {
    if (!isValidUUIDFormat(uuid)) return false;
    return !_invalidUuids.contains(uuid!.trim().toLowerCase());
  }

  /// Sinh UUID v4.
  static String generateUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  /// Chuẩn hóa machine-id (32 hex không gạch) thành UUID format.
  static String? machineIdToUuid(String raw) {
    final hex = raw.trim().toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    if (hex.length != 32) return null;
    if (hex == '0' * 32 || hex == 'f' * 32) return null;
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  /// Đọc hoặc tạo UUID local (last resort khi hardware/OS ID không có).
  static Future<String> getOrCreateLocalDeviceId() async {
    final file = await _localDeviceIdFile();
    try {
      if (await file.exists()) {
        final existing = (await file.readAsString()).trim();
        if (isUsableUuid(existing)) return existing;
      }
    } catch (_) {}

    final created = generateUuid();
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(created);
    } catch (_) {}
    return created;
  }

  static Future<File> _localDeviceIdFile() async {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '.';
      return File('$home/Library/Application Support/fingerprint/device_id');
    }
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '.';
      return File('$home/.config/fingerprint/device_id');
    }
    if (Platform.isWindows) {
      final appData =
          Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'] ??
          '.';
      return File('$appData\\fingerprint\\device_id');
    }
    return File('${Directory.systemTemp.path}/fingerprint_device_id');
  }

  // Lấy IP chính (IPv4) của thiết bị
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
      // ignore
    }
    return null;
  }
}
