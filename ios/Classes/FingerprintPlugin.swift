import Flutter
import UIKit
import Security

public class FingerprintPlugin: NSObject, FlutterPlugin {
  private static let keychainService = "com.fingerprint.device_id"
  private static let keychainAccount = "device_id"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "fingerprint", binaryMessenger: registrar.messenger())
    let instance = FingerprintPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "getPersistentDeviceId":
      result(Self.persistentDeviceId())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// IDFV lưu Keychain — giữ nguyên sau reinstall app.
  private static func persistentDeviceId() -> String {
    if let existing = readKeychain(), !existing.isEmpty {
      return existing
    }

    let idfv = UIDevice.current.identifierForVendor?.uuidString
    let value = (idfv?.isEmpty == false) ? idfv! : UUID().uuidString
    writeKeychain(value)
    return value
  }

  private static func readKeychain() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  private static func writeKeychain(_ value: String) {
    let data = Data(value.utf8)

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
    ]
    SecItemDelete(query as CFDictionary)

    var add = query
    add[kSecValueData as String] = data
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(add as CFDictionary, nil)
  }
}
