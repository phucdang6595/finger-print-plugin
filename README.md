# Fingerprint Plugin

Plugin Flutter để lấy thông tin fingerprint của thiết bị và **location từ IP public**.

## 🆔 Định danh thiết bị & chống trùng fingerprint

Nhiều máy (đặc biệt Windows fleet cài từ cùng một ghost image / VM template)
dùng chung MachineGuid hoặc SMBIOS UUID → nếu định danh chỉ dựa vào ID phần cứng
sẽ bị **trùng fingerprint**. Từ 1.1.0 plugin dùng mô hình **hybrid**:

| Khóa | Ý nghĩa | Dùng để |
|------|---------|---------|
| `install_id` (= `uuid`) | UUID random sinh **một lần trên mỗi máy** ở lần chạy đầu (sau khi clone), lưu "dính" | **Khóa định danh chính** — không bao giờ trùng |
| `hardware_id` | MachineGuid / SMBIOS UUID / IOPlatformUUID… | **Nối lại** cùng một máy vật lý qua reinstall & **phát hiện** fleet clone |
| `signals` | hardware_uuid, host_name… | Tín hiệu phụ để đối chiếu |

**`install_id` lưu ở đâu:**

- Windows: registry `HKCU\Software\fingerprint\install_id` (đọc/ghi qua Win32 FFI) **và** file `%LOCALAPPDATA%\fingerprint\device_id`.
- macOS/Linux: file trong `Application Support` / `~/.config`.
- Android/iOS: dùng luôn id native (Keychain / Widevine) — đã duy nhất & bền qua reinstall.

**Backend nên khử trùng như sau:**

1. **Khóa chính = `install_id`** → không bao giờ gộp nhầm 2 máy khác nhau.
2. **Nối máy qua reinstall**: `install_id` mới nhưng `hardware_id` khớp một máy đã biết ⇒ cùng máy vật lý.
3. **Vô hiệu hóa fleet clone**: nếu **một `hardware_id` gắn với nhiều `install_id`** (vượt ngưỡng) ⇒ đánh dấu `hardware_id` đó "bị clone", chỉ tin `install_id`.

> Đánh đổi: `install_id` sẽ mới khi cài lại OS / xoá sạch dữ liệu user — khi đó
> backend dựa vào `hardware_id` để nhận lại máy.

## 🌍 Tính năng Location

### Lấy thông tin location từ IP public

```dart
import 'package:fingerprint/fingerprint.dart';

// Lấy location từ IP public
final location = await FingerPrintUUID.getLocationFromIP();

// Lấy location chi tiết với coordinates
final detailedLocation = await FingerPrintUUID.getDetailedLocation();

// Lấy fingerprint kết hợp với location
final fingerprintWithLocation = await FingerPrintUUID.getFingerprintWithLocation();

// Kiểm tra VPN/Proxy
final isVPN = await FingerPrintUUID.isVPNOrProxy();
```

**Thông tin location được cung cấp:**

- **Country**: Quốc gia (VD: VN, US, JP)
- **Region/State**: Tỉnh/Bang
- **City**: Thành phố
- **Postal Code**: Mã bưu điện
- **Timezone**: Múi giờ
- **ISP/Organization**: Nhà cung cấp internet
- **Coordinates**: Tọa độ (latitude, longitude)

**Ví dụ output:**

```json
{
  "ip": "203.205.254.157",
  "city": "Ho Chi Minh City",
  "region": "Ho Chi Minh",
  "country": "VN",
  "timezone": "Asia/Ho_Chi_Minh",
  "org": "Viettel Corporation",
  "postal": "70000",
  "loc": "10.8231,106.6297",
  "latitude": 10.8231,
  "longitude": 106.6297,
  "coordinates": {
    "lat": 10.8231,
    "lng": 106.6297
  }
}
```

## 🔒 Tính năng chống Fake IP

### Phát hiện VPN/Proxy

```dart
final isVPN = await FingerPrintUUID.isVPNOrProxy();
if (isVPN) {
  print('⚠️ VPN/Proxy detected! Location may be inaccurate.');
}
```

**Cách thức phát hiện:**

- Kiểm tra ISP/Organization name
- Phát hiện các từ khóa VPN/Proxy phổ biến
- Cảnh báo khi location có thể không chính xác

## 📱 Sử dụng

### Cơ bản

```dart
// Lấy fingerprint cơ bản
final basic = await FingerPrintUUID.getUUID();
// Returns:
// {
//   "uuid": "b2f1c8a0-…",        // = install_id — KHÓA định danh (không trùng)
//   "install_id": "b2f1c8a0-…",  // UUID random lưu-dính, duy nhất mỗi máy
//   "uuid_hashed": "1a2b3c4d",
//   "hardware_id": "4c4c4544-…", // MachineGuid/SMBIOS… CÓ THỂ trùng máy clone
//   "ip": "192.168.1.10",        // IPv4 nội bộ
//   "signals": {
//     "hardware_uuid": "4c4c4544-…",
//     "hardware_uuid_hashed": "…",
//     "host_name": "DESKTOP-ABC"
//   }
// }
```

> ⚠️ **Đổi contract từ 1.1.0**: `uuid` giờ bằng `install_id` (không còn là UUID
> phần cứng). UUID phần cứng chuyển sang `hardware_id`. Xem mục **🆔 Định danh
> thiết bị & chống trùng fingerprint** ở trên.

### Với Location

```dart
// Lấy fingerprint + location
final withLocation = await FingerPrintUUID.getFingerprintWithLocation();
// Returns:
// {
//   "uuid": "b2f1c8a0-…",        // = install_id
//   "install_id": "b2f1c8a0-…",
//   "hardware_id": "4c4c4544-…",
//   "ip": "192.168.1.10",        // IPv4 nội bộ
//   "public_ip": "203.0.113.7",  // IP public
//   "location": { ... },
//   "is_vpn": false,
//   "signals": { ... }
// }
```

### Location chi tiết

```dart
// Lấy location với coordinates
final location = await FingerPrintUUID.getDetailedLocation();
if (location != null) {
  print('Country: ${location['country']}');
  print('City: ${location['city']}');
  print('Coordinates: ${location['latitude']}, ${location['longitude']}');
}
```

## ⚠️ Lưu ý quan trọng

### 1. **Độ chính xác của Location**

- Location dựa trên IP public, không phải GPS
- Độ chính xác: Thành phố/Tỉnh, không phải địa chỉ cụ thể
- Có thể không chính xác nếu dùng VPN/Proxy

### 2. **Privacy & Compliance**

- Cần thông báo cho user về việc thu thập location
- Tuân thủ GDPR, CCPA về data collection
- Cung cấp opt-out mechanism

### 3. **Rate Limiting**

- IP geolocation API có giới hạn request
- Nên cache kết quả để tránh spam API
- Implement error handling cho network issues

### 4. **VPN/Proxy Detection**

- Không thể phát hiện 100% VPN/Proxy
- Chỉ cảnh báo, không chặn hoàn toàn
- User vẫn có thể bypass

## 🛠️ Cài đặt

Thêm dependency vào `pubspec.yaml`:

```yaml
dependencies:
  fingerprint: ^1.0.0
```

## 📋 Ví dụ hoàn chỉnh

```dart
import 'package:flutter/material.dart';
import 'package:fingerprint/fingerprint.dart';

class LocationDemo extends StatefulWidget {
  @override
  _LocationDemoState createState() => _LocationDemoState();
}

class _LocationDemoState extends State<LocationDemo> {
  Map<String, dynamic>? location;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  Future<void> _getLocation() async {
    setState(() => isLoading = true);
    
    try {
      final result = await FingerPrintUUID.getDetailedLocation();
      final isVPN = await FingerPrintUUID.isVPNOrProxy();
      
      setState(() {
        location = result;
        isLoading = false;
      });
      
      if (isVPN) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ VPN detected! Location may be inaccurate.')),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      print('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Location Demo')),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : location != null
              ? Column(
                  children: [
                    Text('Country: ${location!['country']}'),
                    Text('City: ${location!['city']}'),
                    Text('ISP: ${location!['org']}'),
                    if (location!['coordinates'] != null)
                      Text('Coordinates: ${location!['latitude']}, ${location!['longitude']}'),
                  ],
                )
              : Text('Location not available'),
    );
  }
}
```

## 🌐 Hỗ trợ Platform

Định danh thiết bị (`getUUID`) hỗ trợ cả 5 nền tảng; Location (dựa trên IP
public) chạy ở nơi có kết nối mạng.

| Platform | Fingerprint / `getUUID` | Nguồn `hardware_id` | Location (IP) |
|----------|:-----------------------:|---------------------|:-------------:|
| Windows  | ✅ | MachineGuid (FFI) → SMBIOS UUID | ✅ |
| macOS    | ✅ | IOPlatformUUID (`ioreg`) → `system_profiler` | ✅ |
| Linux    | ✅ | `product_uuid` → `machine-id` | ✅ |
| Android  | ✅ | Widevine → ANDROID_ID (native) | ✅ |
| iOS      | ✅ | `identifierForVendor` + Keychain (native) | ✅ |
| Web      | ❌ | — | — |

## 📊 API Services

Plugin sử dụng các service sau để lấy IP public:

- `api.ipify.org`
- `ipinfo.io/ip`
- `icanhazip.com`
- `ident.me`

Và `ipinfo.io` để lấy thông tin geolocation.

## License

MIT License - xem file [LICENSE](LICENSE) để biết thêm chi tiết.
