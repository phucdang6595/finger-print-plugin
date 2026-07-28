import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:fingerprint/src/windows_registry.dart';

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

  // Registry HKCU nơi lưu install_id trên Windows.
  static const String _winInstallIdSubKey = r'Software\fingerprint';
  static const String _winInstallIdValueName = 'install_id';

  /// **install_id** — neo định danh DUY NHẤT cho mỗi máy.
  ///
  /// Đây là chìa khóa xử lý trùng fingerprint: một UUID v4 (CSPRNG) được sinh
  /// **một lần** ở lần chạy đầu trên từng máy (tức là SAU khi máy đã được clone/
  /// ghost image), rồi lưu "dính" nên về mặt toán học không thể trùng giữa các
  /// máy — kể cả khi cả fleet dùng chung MachineGuid/SMBIOS UUID.
  ///
  /// Lưu ở nhiều nơi để bền qua việc xoá cache app:
  ///  - Windows: registry `HKCU\Software\fingerprint\install_id` **và** file.
  ///  - macOS/Linux: file trong thư mục app-support/config của user.
  ///
  /// Lưu ý: id gắn theo profile user (không cần quyền admin). Nếu cài lại OS
  /// hoặc xoá sạch dữ liệu user thì id sẽ mới — khi đó backend dựa vào
  /// `hardware_id` gửi kèm để nối lại cùng một máy vật lý.
  static Future<String> getOrCreateInstallId() async {
    // 1) Windows: ưu tiên đọc từ registry HKCU (bền hơn file khi dọn cache).
    if (Platform.isWindows) {
      final fromReg = WindowsRegistry.readCurrentUserString(
        _winInstallIdSubKey,
        _winInstallIdValueName,
      );
      if (isUsableUuid(fromReg)) return fromReg!.trim();
    }

    // 2) Mọi nền: đọc từ file.
    final file = await _localDeviceIdFile();
    String? fromFile;
    try {
      if (await file.exists()) {
        final existing = (await file.readAsString()).trim();
        if (isUsableUuid(existing)) fromFile = existing;
      }
    } catch (_) {
      // best-effort: đọc file lỗi thì coi như chưa có, sẽ sinh mới bên dưới.
    }

    final id = fromFile ?? generateUuid();

    // 3) Ghi lại (best-effort) để đồng bộ giữa registry & file cho lần sau.
    if (Platform.isWindows) {
      try {
        WindowsRegistry.writeCurrentUserString(
          _winInstallIdSubKey,
          _winInstallIdValueName,
          id,
        );
      } catch (_) {
        // best-effort: không ghi được registry thì vẫn còn file.
      }
    }
    if (fromFile == null) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(id);
      } catch (_) {
        // best-effort: ghi file lỗi thì id vẫn trả về (chỉ là không lưu bền).
      }
    }
    return id;
  }

  /// Alias tương thích ngược: last resort khi hardware/OS ID không có.
  /// Nay dùng chung cơ chế lưu-dính với [getOrCreateInstallId].
  static Future<String> getOrCreateLocalDeviceId() => getOrCreateInstallId();

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

  /// Chạy tiến trình con với timeout THẬT SỰ.
  ///
  /// Khác với `Process.run(...).timeout(...)` (chỉ làm Future ném lỗi nhưng
  /// để tiến trình con chạy mồ côi), hàm này dùng [Process.start] và **kill**
  /// tiến trình con khi quá hạn, tránh rò process trên các máy bị EDR/AV làm
  /// chậm việc spawn `powershell`/`wmic`.
  ///
  /// Trả về stdout đã decode nếu tiến trình kết thúc với exitCode 0; trả về
  /// `null` trong mọi trường hợp khác: executable không tồn tại/không chạy
  /// được (vd `wmic` đã bị gỡ trên Win 11 24H2+), exitCode != 0, hoặc quá hạn.
  static Future<String?> runProcessForStdout(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 5),
    bool runInShell = false,
  }) async {
    Process? process;
    try {
      process = await Process.start(
        executable,
        arguments,
        runInShell: runInShell,
      );

      // Drain stdout/stderr song song để pipe buffer không đầy gây deadlock.
      // catchError để stream lỗi (vd khi bị kill) không thành unhandled error.
      final outFuture = process.stdout
          .transform(systemEncoding.decoder)
          .join()
          .catchError((_) => '');
      final errFuture = process.stderr
          .transform(systemEncoding.decoder)
          .join()
          .catchError((_) => '');

      final exitCode = await process.exitCode.timeout(timeout);
      final output = await outFuture;
      await errFuture;

      return exitCode == 0 ? output : null;
    } on TimeoutException {
      process?.kill(ProcessSignal.sigkill);
      return null;
    } on ProcessException {
      return null;
    } catch (_) {
      process?.kill(ProcessSignal.sigkill);
      return null;
    }
  }
}
