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
  // Trả về dữ liệu chung gồm uuid và ip chính (IPv4)
  static Future<Map<String, String?>> getUUID() async {
    if (Platform.isWindows) {
      return await WindowsSystemUUID.getFingerprint();
    }

    if (Platform.isMacOS) {
      return await MacOSUUID.getFingerprint();
    }

    if (Platform.isLinux) {
      final uuid = await LinuxUUID.getSystemUUID();
      final ip = await UUIDUtils.getPrimaryIPv4();
      return {'uuid': uuid, 'ip': ip};
    }

    if (Platform.isAndroid) {
      return await AndroidUUID.getFingerprint();
    }

    if (Platform.isIOS) {
      return await IOSUUID.getFingerprint();
    }

    return {'uuid': null, 'ip': null};
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

    final result = <String, dynamic>{
      'uuid': basicFingerprint['uuid'],
      'ip': basicFingerprint['ip'],
      'location': await getDetailedLocation(),
      'is_vpn': await isVPNOrProxy(),
    };

    return result;
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
      if (location == null) return false;

      final org = location['org'] as String?;
      if (org != null) {
        final vpnKeywords = [
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
    } catch (e) {
      debugPrint('Error checking VPN/Proxy: $e');
    }
    return false;
  }
}
