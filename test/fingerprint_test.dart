import 'package:flutter_test/flutter_test.dart';
import 'package:fingerprint/fingerprint.dart';

void main() {
  group('FingerPrintUUID Tests', () {
    test('getUUID should return basic fingerprint', () async {
      final result = await FingerPrintUUID.getUUID();

      expect(result, isA<Map<String, String?>>());
      expect(result.containsKey('uuid'), isTrue);
      expect(result.containsKey('ip'), isTrue);
    });

    test('getLocationFromIP should return location data', () async {
      final result = await FingerPrintUUID.getLocationFromIP();

      // Location có thể null nếu không có internet
      if (result != null) {
        expect(result, isA<Map<String, dynamic>>());
        expect(result.containsKey('ip'), isTrue);
        expect(result.containsKey('country'), isTrue);
        expect(result.containsKey('city'), isTrue);
      }
    });

    test(
      'getFingerprintWithLocation should combine device and location info',
      () async {
        final result = await FingerPrintUUID.getFingerprintWithLocation();

        expect(result, isA<Map<String, dynamic>>());
        expect(result.containsKey('uuid'), isTrue);
        expect(result.containsKey('ip'), isTrue);
        expect(result.containsKey('public_ip'), isTrue);
        expect(result.containsKey('location'), isTrue);
      },
    );

    test('getDetailedLocation should include coordinates', () async {
      final result = await FingerPrintUUID.getDetailedLocation();

      if (result != null) {
        expect(result.containsKey('latitude'), isTrue);
        expect(result.containsKey('longitude'), isTrue);
        expect(result.containsKey('coordinates'), isTrue);

        // Coordinates phải là số
        if (result['latitude'] != null) {
          expect(result['latitude'], isA<double>());
        }
        if (result['longitude'] != null) {
          expect(result['longitude'], isA<double>());
        }
      }
    });

    test('isVPNOrProxy should return boolean', () async {
      final result = await FingerPrintUUID.isVPNOrProxy();

      expect(result, isA<bool>());
    });

    test('Location data structure should be correct', () async {
      final location = await FingerPrintUUID.getLocationFromIP();

      if (location != null) {
        // Kiểm tra các field bắt buộc
        expect(location.containsKey('ip'), isTrue);
        expect(location.containsKey('country'), isTrue);
        expect(location.containsKey('region'), isTrue);
        expect(location.containsKey('city'), isTrue);
        expect(location.containsKey('timezone'), isTrue);
        expect(location.containsKey('org'), isTrue);

        // IP phải là string
        expect(location['ip'], isA<String>());

        // Country code phải có 2 ký tự
        if (location['country'] != null) {
          expect(location['country'].length, equals(2));
        }
      }
    });

    test('Public IP should be different from local IP', () async {
      final basic = await FingerPrintUUID.getUUID();
      final withLocation = await FingerPrintUUID.getFingerprintWithLocation();

      final localIP = basic['ip'];
      final publicIP = withLocation['public_ip'];

      if (localIP != null && publicIP != null) {
        // Public IP không nên giống local IP
        expect(publicIP, isNot(equals(localIP)));

        // Public IP không nên là private IP
        expect(publicIP.startsWith('192.168.'), isFalse);
        expect(publicIP.startsWith('10.'), isFalse);
        expect(publicIP.startsWith('172.'), isFalse);
      }
    });
  });
}
