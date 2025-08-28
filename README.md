# Fingerprint Plugin

Plugin Flutter để lấy thông tin fingerprint của thiết bị và **location từ IP public**.

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
// Returns: {"uuid": "system-uuid", "ip": "local-ip"}
```

### Với Location

```dart
// Lấy fingerprint + location
final withLocation = await FingerPrintUUID.getFingerprintWithLocation();
// Returns: {
//   "uuid": "system-uuid",
//   "ip": "local-ip", 
//   "public_ip": "public-ip",
//   "location": { ... }
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

- ✅ Windows
- ✅ macOS  
- ✅ Linux
- ❌ iOS (không hỗ trợ)
- ❌ Android (không hỗ trợ)

## 📊 API Services

Plugin sử dụng các service sau để lấy IP public:

- `api.ipify.org`
- `ipinfo.io/ip`
- `icanhazip.com`
- `ident.me`

Và `ipinfo.io` để lấy thông tin geolocation.

## License

MIT License - xem file [LICENSE](LICENSE) để biết thêm chi tiết.
