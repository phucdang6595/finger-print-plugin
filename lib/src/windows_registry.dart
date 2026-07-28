import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Đọc/ghi registry Windows trực tiếp qua Win32 API (advapi32) bằng `dart:ffi`,
/// KHÔNG spawn `reg.exe`. Nhờ vậy tránh được toàn bộ sự phụ thuộc vào
/// PowerShell/WMIC/reg (vốn hay bị EDR/AV chặn hoặc làm chậm trên các máy
/// Win 10/11 Pro được quản lý bằng GPO/Intune).
///
/// LƯU Ý: chỉ được gọi khi `Platform.isWindows == true`.
class WindowsRegistry {
  // Hằng số Win32.
  static const int _hkeyLocalMachine = 0x80000002;
  static const int _hkeyCurrentUser = 0x80000001;
  static const int _keyRead = 0x20019;
  static const int _keyWrite = 0x20006;
  static const int _keyWow6464Key = 0x0100;
  static const int _regSz = 1;
  static const int _errorSuccess = 0;

  /// `HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid` — ID máy Windows duy
  /// nhất theo mỗi bản cài, ổn định qua reboot/OS-update, đọc được bằng quyền
  /// user thường. Cờ `KEY_WOW64_64KEY` tránh bị chuyển hướng sang `WOW6432Node`.
  static String? readMachineGuid() => _readString(
        _hkeyLocalMachine,
        r'SOFTWARE\Microsoft\Cryptography',
        'MachineGuid',
        _keyWow6464Key,
      );

  /// Đọc một giá trị REG_SZ dưới `HKCU\<subKey>`. Trả `null` nếu không có.
  static String? readCurrentUserString(String subKey, String valueName) =>
      _readString(_hkeyCurrentUser, subKey, valueName, 0);

  /// Ghi một giá trị REG_SZ vào `HKCU\<subKey>` (tạo key nếu chưa có).
  /// Trả `true` nếu ghi thành công. HKCU ghi được bằng quyền user thường.
  static bool writeCurrentUserString(
    String subKey,
    String valueName,
    String value,
  ) {
    final DynamicLibrary advapi32;
    try {
      advapi32 = DynamicLibrary.open('advapi32.dll');
    } catch (_) {
      return false;
    }

    final regCreateKeyEx = advapi32.lookupFunction<
        Int32 Function(IntPtr, Pointer<Utf16>, Uint32, Pointer<Utf16>, Uint32,
            Uint32, Pointer<Void>, Pointer<IntPtr>, Pointer<Uint32>),
        int Function(int, Pointer<Utf16>, int, Pointer<Utf16>, int, int,
            Pointer<Void>, Pointer<IntPtr>, Pointer<Uint32>)>('RegCreateKeyExW');
    final regSetValueEx = advapi32.lookupFunction<
        Int32 Function(
            IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<Uint8>, Uint32),
        int Function(int, Pointer<Utf16>, int, int, Pointer<Uint8>,
            int)>('RegSetValueExW');
    final regCloseKey = advapi32
        .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'RegCloseKey');

    final subKeyPtr = subKey.toNativeUtf16();
    final valueNamePtr = valueName.toNativeUtf16();
    final dataPtr = value.toNativeUtf16(); // UTF-16, đã null-terminated
    final phkResult = calloc<IntPtr>();

    try {
      final created = regCreateKeyEx(
        _hkeyCurrentUser,
        subKeyPtr,
        0,
        nullptr,
        0, // REG_OPTION_NON_VOLATILE
        _keyWrite,
        nullptr,
        phkResult,
        nullptr,
      );
      if (created != _errorSuccess) return false;

      final hKey = phkResult.value;
      try {
        // cbData: số byte, gồm cả null-terminator UTF-16 (2 byte/ký tự).
        final cbData = (value.length + 1) * 2;
        final set = regSetValueEx(
          hKey,
          valueNamePtr,
          0,
          _regSz,
          dataPtr.cast<Uint8>(),
          cbData,
        );
        return set == _errorSuccess;
      } finally {
        regCloseKey(hKey);
      }
    } catch (_) {
      return false;
    } finally {
      malloc.free(subKeyPtr);
      malloc.free(valueNamePtr);
      malloc.free(dataPtr);
      calloc.free(phkResult);
    }
  }

  static String? _readString(
    int rootKey,
    String subKey,
    String valueName,
    int extraSam,
  ) {
    final DynamicLibrary advapi32;
    try {
      advapi32 = DynamicLibrary.open('advapi32.dll');
    } catch (_) {
      return null;
    }

    final regOpenKeyEx = advapi32.lookupFunction<
        Int32 Function(
            IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<IntPtr>),
        int Function(
            int, Pointer<Utf16>, int, int, Pointer<IntPtr>)>('RegOpenKeyExW');
    final regQueryValueEx = advapi32.lookupFunction<
        Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>,
            Pointer<Uint8>, Pointer<Uint32>),
        int Function(int, Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>,
            Pointer<Uint8>, Pointer<Uint32>)>('RegQueryValueExW');
    final regCloseKey = advapi32
        .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'RegCloseKey');

    final subKeyPtr = subKey.toNativeUtf16();
    final valueNamePtr = valueName.toNativeUtf16();
    final phkResult = calloc<IntPtr>();
    const int bufferBytes = 512; // dư sức cho GUID 37 ký tự UTF-16 + null
    final data = calloc<Uint8>(bufferBytes);
    final dataSize = calloc<Uint32>()..value = bufferBytes;

    try {
      final opened = regOpenKeyEx(
        rootKey,
        subKeyPtr,
        0,
        _keyRead | extraSam,
        phkResult,
      );
      if (opened != _errorSuccess) return null;

      final hKey = phkResult.value;
      try {
        final queried = regQueryValueEx(
          hKey,
          valueNamePtr,
          nullptr,
          nullptr,
          data,
          dataSize,
        );
        if (queried != _errorSuccess) return null;

        // Buffer đã calloc zero-init nên chuỗi UTF-16 chắc chắn có
        // null-terminator -> toDartString() an toàn, không đọc lố.
        final value = data.cast<Utf16>().toDartString().trim();
        return value.isEmpty ? null : value;
      } finally {
        regCloseKey(hKey);
      }
    } catch (_) {
      return null;
    } finally {
      malloc.free(subKeyPtr);
      malloc.free(valueNamePtr);
      calloc.free(phkResult);
      calloc.free(data);
      calloc.free(dataSize);
    }
  }
}
