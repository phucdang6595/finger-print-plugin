# Changelog

## 1.1.0

### ⚠️ Breaking

- `FingerPrintUUID.getUUID()` nay trả về `Map<String, dynamic>` (trước là
  `Map<String, String?>`) với cấu trúc hybrid mới. Khóa `uuid` **giờ bằng
  `install_id`** (định danh duy nhất theo máy), KHÔNG còn là UUID phần cứng như
  trước. UUID phần cứng chuyển sang khóa `hardware_id`. Backend cần chuyển khóa
  định danh sang `install_id` và dùng `hardware_id` để nối/khử trùng.

### Added — Chống trùng fingerprint (fleet clone)

- Thêm **`install_id`**: UUID v4 (CSPRNG) sinh một lần trên mỗi máy ở lần chạy
  đầu và lưu "dính" → về mặt toán học không trùng, kể cả khi cả fleet dùng chung
  MachineGuid/SMBIOS UUID (máy ghost image không chạy `sysprep`).
  - Windows: lưu ở `HKCU\Software\fingerprint\install_id` (Win32 FFI) **và** file.
  - macOS/Linux: lưu file trong Application Support / `.config`.
  - Mobile: dùng luôn id native (Keychain/Widevine) vì đã duy nhất + bền.
- `getUUID()` trả kèm `hardware_id` và `signals` (hardware_uuid, host_name…) để
  backend nối lại cùng một máy vật lý qua reinstall và phát hiện fleet clone.
- `getFingerprintWithLocation()` trả thêm `public_ip`, `install_id`,
  `hardware_id`, `signals`.

### Fixed — Độ tin cậy lấy fingerprint trên Windows/macOS

- Windows: đọc **MachineGuid trực tiếp qua Win32 API (dart:ffi)**, không spawn
  `reg.exe`/PowerShell/wmic — tránh bị EDR/AV/GPO chặn và tránh treo trên máy
  Win 10/11 Pro được quản lý. MachineGuid (ổn định & duy nhất per-install) nay
  được ưu tiên trước SMBIOS UUID (vốn hay trùng). Bỏ `wmic` khỏi đường đi chính
  (đã bị gỡ trên Windows 11 24H2+).
- Thêm timeout **có kill tiến trình con thật sự** cho mọi lệnh ngoài (Windows
  powershell/reg, macOS `ioreg`/`system_profiler`) — tránh rò process và treo
  vô hạn.
- `getFingerprintWithLocation()` chỉ gọi mạng geolocation **một lần** thay vì
  hai lần.

### Dependencies

- Thêm `ffi: ^2.1.0` (đọc/ghi registry Windows qua FFI).

## 0.0.1

* Initial release.
