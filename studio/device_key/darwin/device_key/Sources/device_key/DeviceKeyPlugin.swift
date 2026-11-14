// Device keys on macOS and iOS (ADR 0050): a P-256 key made inside the Secure
// Enclave by CryptoKit, usable only after LocalAuthentication checks the person.
//
// The Secure Enclave hands out the key only as `dataRepresentation`, a blob
// wrapped by this device's enclave: no other device can use it and the private
// key never leaves the enclave. The blob is kept in UserDefaults, not in the
// keychain: a permanent keychain key needs the `keychain-access-groups`
// entitlement, which needs a provisioning profile (an ad-hoc signed build gets
// errSecMissingEntitlement, -34018). The wire is the same either way: the
// public key as the 65-byte X9.63 point, the signature ECDSA P-256 SHA-256 in
// ASN.1 DER (`alg: es256`).

import CryptoKit
import Foundation
import LocalAuthentication
import Security

#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

public class DeviceKeyPlugin: NSObject, FlutterPlugin {
  private static let channelName = "uk.gencto.device_key"
  private static let prefix = "uk.gencto.device_key."
  private let defaults = UserDefaults(suiteName: "uk.gencto.device_key") ?? .standard
  private let queue = DispatchQueue(label: "uk.gencto.device_key", qos: .userInitiated)

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    registrar.addMethodCallDelegate(DeviceKeyPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let reply: (Any?) -> Void = { value in DispatchQueue.main.async { result(value) } }
    switch call.method {
    case "isAvailable":
      result(availability())
    case "create":
      guard let alias = args["alias"] as? String else {
        result(FlutterError(code: "failed", message: "alias missing", details: nil))
        return
      }
      let cred = args["allowDeviceCredential"] as? Bool ?? false
      queue.async { reply(self.create(alias: alias, deviceCredential: cred)) }
    case "sign":
      guard let alias = args["alias"] as? String,
        let bytes = args["bytes"] as? FlutterStandardTypedData
      else {
        result(["result": "failed", "message": "alias or bytes missing"])
        return
      }
      let reason = args["reason"] as? String ?? "Unlock"
      let cancel = args["cancelLabel"] as? String
      queue.async {
        self.sign(alias: alias, data: bytes.data, reason: reason, cancel: cancel, reply: reply)
      }
    case "delete":
      if let alias = args["alias"] as? String {
        defaults.removeObject(forKey: Self.prefix + alias)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - isAvailable

  private func availability() -> [String: String] {
    let none = ["kind": "none", "name": ""]
    guard SecureEnclave.isAvailable else { return none }
    let ctx = LAContext()
    var error: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
      return none
    }
    switch ctx.biometryType {
    case .touchID:
      return ["kind": "touchId", "name": "Touch ID"]
    case .faceID:
      return ["kind": "faceId", "name": "Face ID"]
    default:
      if #available(iOS 17.0, macOS 14.0, *), ctx.biometryType == .opticID {
        return ["kind": "opticId", "name": "Optic ID"]
      }
      return none
    }
  }

  // MARK: - create

  private func create(alias: String, deviceCredential: Bool) -> Any {
    guard SecureEnclave.isAvailable else {
      return FlutterError(code: "unavailable", message: "no Secure Enclave", details: nil)
    }
    let probe = LAContext()
    var laError: NSError?
    let policy: LAPolicy =
      deviceCredential ? .deviceOwnerAuthentication : .deviceOwnerAuthenticationWithBiometrics
    guard probe.canEvaluatePolicy(policy, error: &laError) else {
      let code = laError.map { Self.code(of: $0, deviceCredential: deviceCredential) }
      return FlutterError(
        code: code == "lockout" ? "lockout" : "unavailable",
        message: laError?.localizedDescription ?? "biometrics not available", details: nil)
    }
    guard let access = Self.accessControl(deviceCredential: deviceCredential) else {
      return FlutterError(code: "failed", message: "no access control", details: nil)
    }
    do {
      let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
      var record: [String: Any] = ["blob": key.dataRepresentation, "cred": deviceCredential]
      // The enrolled set at creation: when it moves, a `biometryCurrentSet` key
      // can never sign again, and `sign` says `invalidated` without a prompt.
      if !deviceCredential, let state = probe.evaluatedPolicyDomainState {
        record["state"] = state
      }
      defaults.set(record, forKey: Self.prefix + alias)
      return [
        "alg": "es256",
        "publicKey": FlutterStandardTypedData(bytes: key.publicKey.x963Representation),
      ]
    } catch {
      return FlutterError(code: "failed", message: "\(error)", details: nil)
    }
  }

  private static func accessControl(deviceCredential: Bool) -> SecAccessControl? {
    let flags: SecAccessControlCreateFlags =
      deviceCredential ? [.privateKeyUsage, .userPresence] : [.privateKeyUsage, .biometryCurrentSet]
    return SecAccessControlCreateWithFlags(
      nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, nil)
  }

  // MARK: - sign

  private func sign(
    alias: String, data: Data, reason: String, cancel: String?, reply: @escaping (Any?) -> Void
  ) {
    guard let record = defaults.dictionary(forKey: Self.prefix + alias),
      let blob = record["blob"] as? Data
    else {
      reply(["result": "invalidated"])
      return
    }
    let deviceCredential = record["cred"] as? Bool ?? false
    if !deviceCredential {
      let probe = LAContext()
      var laError: NSError?
      if !probe.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &laError) {
        let code = laError.map { Self.code(of: $0, deviceCredential: false) } ?? "unavailable"
        reply(["result": code, "message": laError?.localizedDescription ?? ""])
        return
      }
      if let then = record["state"] as? Data, let now = probe.evaluatedPolicyDomainState,
        then != now
      {
        reply(["result": "invalidated"])
        return
      }
    }
    guard let access = Self.accessControl(deviceCredential: deviceCredential) else {
      reply(["result": "failed", "message": "no access control"])
      return
    }
    let ctx = LAContext()
    ctx.localizedReason = reason
    if let cancel { ctx.localizedCancelTitle = cancel }
    if !deviceCredential {
      // The UI has its own "Use the password"; hide the prompt's fallback.
      ctx.localizedFallbackTitle = ""
    }
    ctx.evaluateAccessControl(access, operation: .useKeySign, localizedReason: reason) {
      ok, error in
      guard ok else {
        let e = error as NSError?
        reply([
          "result": e.map { Self.code(of: $0, deviceCredential: deviceCredential) } ?? "failed",
          "message": e?.localizedDescription ?? "",
        ])
        return
      }
      let key: SecureEnclave.P256.Signing.PrivateKey
      do {
        key = try SecureEnclave.P256.Signing.PrivateKey(
          dataRepresentation: blob, authenticationContext: ctx)
      } catch {
        // A blob this enclave cannot open: another device's (a restored
        // backup) or a key the OS dropped.
        reply(["result": "invalidated", "message": "\(error)"])
        return
      }
      do {
        let signature = try key.signature(for: data)
        reply([
          "result": "signed",
          "signature": FlutterStandardTypedData(bytes: signature.derRepresentation),
        ])
      } catch {
        let e = error as NSError
        if e.domain == LAErrorDomain {
          reply(["result": Self.code(of: e, deviceCredential: deviceCredential),
                 "message": e.localizedDescription])
        } else {
          reply(["result": "failed", "message": "\(error)"])
        }
      }
    }
  }

  /// A LocalAuthentication error as a result of `sign`.
  private static func code(of error: NSError, deviceCredential: Bool) -> String {
    guard error.domain == LAErrorDomain, let code = LAError.Code(rawValue: error.code) else {
      return "failed"
    }
    switch code {
    case .userCancel, .appCancel, .systemCancel, .userFallback:
      return "cancelled"
    case .biometryLockout, .authenticationFailed:
      return "lockout"
    case .biometryNotEnrolled:
      // Every finger or face removed: a `biometryCurrentSet` key is gone for good.
      return deviceCredential ? "unavailable" : "invalidated"
    case .biometryNotAvailable, .passcodeNotSet, .notInteractive:
      return "unavailable"
    default:
      return "failed"
    }
  }
}
