import 'dart:io';
import 'dart:convert';

import 'package:fingerprint/src/windows_uuid.dart';
import 'package:fingerprint/src/linux_uuid.dart';
import 'package:fingerprint/src/macos_uuid.dart';
import 'package:fingerprint/src/android_uuid.dart';
import 'package:fingerprint/src/ios_uuid.dart';
import 'package:fingerprint/src/uuid_utils.dart';
import 'package:flutter/material.dart';

class FingerPrintUUID {
  /// Trả về fingerprint dạng HYBRID (chống trùng cho fleet clone):
  ///
  ///  - `uuid` / `install_id`: **neo duy nhất** — nên dùng làm khóa định danh.
  ///    Trên máy để bàn là UUID random lưu-dính (sinh sau khi clone → không
  ///    trùng); trên mobile là id native (đã duy nhất + bền qua reinstall).
  ///  - `hardware_id`: ID phần cứng/OS (MachineGuid/SMBIOS/IOPlatformUUID/…).
  ///    CÓ THỂ TRÙNG trên fleet clone — gửi kèm để backend NỐI lại cùng một máy
  ///    vật lý qua reinstall và PHÁT HIỆN fleet bị clone.
  ///  - `signals`: các tín hiệu phụ hỗ trợ backend đối chiếu.
  ///  - `ip`: IPv4 nội bộ.
  static Future<Map<String, dynamic>> getUUID() async {
    // Tín hiệu phần cứng/OS theo nền tảng (base['uuid'] = hardware id, có thể null/trùng).
    Map<String, String?> base = const {'uuid': null, 'uuid_hashed': null, 'ip': null};
    if (Platform.isWindows) {
      base = await WindowsSystemUUID.getFingerprint();
    } else if (Platform.isMacOS) {
      base = await MacOSUUID.getFingerprint();
    } else if (Platform.isLinux) {
      base = await LinuxUUID.getFingerprint();
    } else if (Platform.isAndroid) {
      base = await AndroidUUID.getFingerprint();
    } else if (Platform.isIOS) {
      base = await IOSUUID.getFingerprint();
    }

    final hardwareId = base['uuid'];

    // install_id: neo DUY NHẤT.
    // Mobile: id phần cứng native đã duy nhất + bền → dùng luôn.
    // Desktop (hoặc mobile không có id native): UUID random lưu-dính.
    final String installId;
    if ((Platform.isAndroid || Platform.isIOS) &&
        UUIDUtils.isUsableUuid(hardwareId)) {
      installId = hardwareId!;
    } else {
      installId = await UUIDUtils.getOrCreateInstallId();
    }

    return <String, dynamic>{
      // Khóa định danh nên dùng (không trùng):
      'uuid': installId,
      'uuid_hashed': UUIDUtils.hashString(installId),
      'install_id': installId,
      // Tín hiệu phần cứng để backend nối máy / phát hiện clone:
      'hardware_id': hardwareId,
      'ip': base['ip'],
      'signals': <String, String?>{
        'hardware_uuid': hardwareId,
        'hardware_uuid_hashed': base['uuid_hashed'],
        'host_name': _safeHostname(),
      },
    };
  }

  // Lấy thông tin location từ IP public
  static Future<Map<String, dynamic>?> getLocationFromIP() async {
    try {
      // Lấy IP public
      final publicIP = await _getPublicIP();
      if (publicIP == null) return null;

      // Lấy thông tin location từ IP
      final location = await _getIPGeolocation(publicIP);
      return location;
    } catch (e) {
      debugPrint('Error getting location: $e');
      return null;
    }
  }

  // Lấy fingerprint với location
  static Future<Map<String, dynamic>> getFingerprintWithLocation() async {
    final basicFingerprint = await getUUID();
    // Lấy location MỘT lần rồi suy ra is_vpn từ cùng kết quả (tránh gọi mạng 2 lần).
    final location = await getDetailedLocation();
    final org = location?['org'] as String?;

    return <String, dynamic>{
      // uuid, uuid_hashed, install_id, hardware_id, ip, signals
      ...basicFingerprint,
      'public_ip': location?['ip'], // IP public (khác 'ip' là IPv4 nội bộ)
      'location': location,
      'is_vpn': _isVpnOrg(org),
    };
  }

  // Lấy IP public từ external service
  static Future<String?> _getPublicIP() async {
    try {
      // Thử nhiều service để đảm bảo độ tin cậy
      final services = [
        'https://api.ipify.org',
        'https://ipinfo.io/ip',
        'https://icanhazip.com',
        'https://ident.me',
      ];

      for (final service in services) {
        try {
          final client = HttpClient();
          final request = await client.getUrl(Uri.parse(service));
          final response = await request.close();

          if (response.statusCode == 200) {
            final ip = await response.transform(utf8.decoder).join();
            client.close();
            return ip.trim();
          }
          client.close();
        } catch (e) {
          // Thử service tiếp theo
          continue;
        }
      }
    } catch (e) {
      debugPrint('Error getting public IP: $e');
    }
    return null;
  }

  // Lấy thông tin location từ IP
  static Future<Map<String, dynamic>?> _getIPGeolocation(String ip) async {
    try {
      // Sử dụng ipinfo.io API (free tier)
      final url = 'https://ipinfo.io/$ip/json';
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode == 200) {
        final data = await response.transform(utf8.decoder).join();
        final jsonData = json.decode(data) as Map<String, dynamic>;
        client.close();

        return {
          'ip': jsonData['ip'],
          'city': jsonData['city'],
          'region': jsonData['region'],
          'country': jsonData['country'],
          'timezone': jsonData['timezone'],
          'org': jsonData['org'],
          'postal': jsonData['postal'],
          'loc': jsonData['loc'], // latitude,longitude
        };
      }
      client.close();
    } catch (e) {
      debugPrint('Error getting geolocation: $e');
    }
    return null;
  }

  // Lấy location chi tiết hơn với coordinates
  static Future<Map<String, dynamic>?> getDetailedLocation() async {
    try {
      final location = await getLocationFromIP();
      if (location == null) return null;

      // Parse coordinates nếu có
      final locString = location['loc'] as String?;
      if (locString != null && locString.contains(',')) {
        final coords = locString.split(',');
        if (coords.length == 2) {
          final lat = double.tryParse(coords[0]);
          final lng = double.tryParse(coords[1]);

          if (lat != null && lng != null) {
            location['latitude'] = lat;
            location['longitude'] = lng;

            // Thêm thông tin bổ sung
            location['coordinates'] = {'lat': lat, 'lng': lng};
          }
        }
      }

      return location;
    } catch (e) {
      debugPrint('Error getting detailed location: $e');
      return null;
    }
  }

  // Kiểm tra xem IP có phải là VPN/Proxy không
  static Future<bool> isVPNOrProxy() async {
    try {
      final location = await getLocationFromIP();
      return _isVpnOrg(location?['org'] as String?);
    } catch (e) {
      debugPrint('Error checking VPN/Proxy: $e');
      return false;
    }
  }

  // Tên host của máy (best-effort, dùng làm tín hiệu phụ để backend đối chiếu).
  static String? _safeHostname() {
    try {
      final name = Platform.localHostname.trim();
      return name.isEmpty ? null : name;
    } catch (_) {
      return null;
    }
  }

  // Heuristic đơn giản: khớp từ khóa trong tên ISP/organization.
  static bool _isVpnOrg(String? org) {
    if (org == null) return false;
    const vpnKeywords = [
      'vpn',
      'proxy',
      'tor',
      'nord',
      'express',
      'surfshark',
      'cyberghost',
      'private',
      'anonymous',
      'hide',
      'mask',
    ];
    final lowerOrg = org.toLowerCase();
    return vpnKeywords.any((keyword) => lowerOrg.contains(keyword));
  }
}
