import Foundation
import Security
import CommonCrypto

/// Extension-safe helper (no Flutter/UIKit imports).
/// Can be compiled into both the host app and Notification Service Extension.
@objc(PushedCoreClient)
public class PushedCoreClient: NSObject {
    // Shared Keychain identifiers (same as in previous versions / native lib)
    private static let clientTokenAccount = "pushed_token"
    private static let clientTokenService = "pushed_messaging_service"

    // Must match native library crypto params for backwards compatibility
    private static let tokenCryptoKey = "Rt9n4BbW7Y97fhUkyygddZ8sr8xPNYaU"
    private static let tokenCryptoIv = "xjPamAwc7QLYQkhm"

    // MARK: - Public API

    /// Load clientToken from Keychain (shared via Keychain Sharing entitlements).
    @objc
    public static func loadClientTokenFromKeychain() -> String {
        guard let raw = readKeychainString(account: clientTokenAccount, service: clientTokenService),
              !raw.isEmpty
        else {
            return ""
        }
        return decryptToken(raw) ?? raw
    }

    /// Best-effort messageId extractor from APNS userInfo.
    @objc
    public static func extractMessageId(from userInfo: [AnyHashable: Any]) -> String? {
        // Common variants (root-level)
        if let s = userInfo["messageId"] as? String, !s.isEmpty { return s }
        if let s = userInfo["message_id"] as? String, !s.isEmpty { return s }
        if let s = userInfo["mid"] as? String, !s.isEmpty { return s }

        // Often "data" is a JSON string or dict
        if let dataStr = userInfo["data"] as? String, let s = extractMessageId(fromJsonString: dataStr) { return s }
        if let dataDict = userInfo["data"] as? [String: Any], let s = extractMessageId(from: dataDict) { return s }

        // Sometimes nested under pushedNotification
        if let pn = userInfo["pushedNotification"] as? [String: Any], let s = extractMessageId(from: pn) { return s }

        return nil
    }

    /// Confirm APNs delivery (used by Notification Service Extension).
    @objc
    public static func confirmApnsDelivery(_ messageId: String) {
        confirmApnsDelivery(messageId) { _ in }
    }

    /// Confirm APNs delivery with completion flag (success/failure).
    public static func confirmApnsDelivery(_ messageId: String, completion: @escaping (Bool) -> Void) {
        let clientToken = loadClientTokenFromKeychain()
        guard !clientToken.isEmpty else {
            completion(false)
            return
        }

        let credentials = "\(clientToken):\(messageId)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            completion(false)
            return
        }
        let basicAuth = "Basic \(credentialsData.base64EncodedString())"

        guard let url = URL(string: "https://pub.multipushed.ru/v2/confirm?transportKind=Apns") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(basicAuth, forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if error != nil {
                completion(false)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(false)
                return
            }
            completion((200...299).contains(http.statusCode))
        }
        task.resume()
    }

    /// Send client interaction (1=SHOW, 2=CLICK)
    @objc
    public static func sendInteraction(_ interaction: Int, messageId: String) {
        guard interaction == 1 || interaction == 2 else { return }

        let clientToken = loadClientTokenFromKeychain()
        guard !clientToken.isEmpty else { return }

        let urlString = "https://api.multipushed.ru/v2/mobile-push/confirm-client-interaction?clientInteraction=\(interaction)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let basicAuth = "Basic " + Data("\(clientToken):\(messageId)".utf8).base64EncodedString()
        request.addValue(basicAuth, forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "clientToken": clientToken,
            "messageId": messageId
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return
        }

        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    // MARK: - Keychain

    private static func readKeychainString(account: String, service: String) -> String? {
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword]
        query[kSecAttrAccount] = account
        query[kSecAttrService] = service
        query[kSecReturnData] = true
        query[kSecAttrSynchronizable] = false

        var ref: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)
        guard status == errSecSuccess, let data = ref as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Token decrypt (compat)

    private static func decryptToken(_ storedValue: String) -> String? {
        // If it's not base64, it's likely a legacy/plain token.
        guard let encryptedData = Data(base64Encoded: storedValue) else {
            return storedValue
        }

        guard let decrypted = aesCrypt(data: encryptedData, operation: CCOperation(kCCDecrypt)),
              let decryptedStr = String(data: decrypted, encoding: .utf8)
        else {
            return storedValue
        }

        if decryptedStr.hasPrefix("encrypted:") {
            return String(decryptedStr.dropFirst("encrypted:".count))
        }

        return storedValue
    }

    private static func aesCrypt(data: Data, operation: CCOperation) -> Data? {
        // AES-128 + PKCS7Padding
        let keyData = Data(tokenCryptoKey.utf8).prefix(kCCKeySizeAES128)
        let ivData = Data(tokenCryptoIv.utf8).prefix(kCCBlockSizeAES128)

        var outLength: size_t = 0
        var outData = Data(count: data.count + kCCBlockSizeAES128)
        let outCapacity = outData.count

        let status = outData.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { inBytes in
                ivData.withUnsafeBytes { ivBytes in
                    keyData.withUnsafeBytes { keyBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, keyData.count,
                            ivBytes.baseAddress,
                            inBytes.baseAddress, data.count,
                            outBytes.baseAddress, outCapacity,
                            &outLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        outData.removeSubrange(outLength..<outData.count)
        return outData
    }

    // MARK: - JSON helpers

    private static func extractMessageId(from dict: [String: Any]) -> String? {
        if let s = dict["messageId"] as? String, !s.isEmpty { return s }
        if let s = dict["message_id"] as? String, !s.isEmpty { return s }
        if let s = dict["mid"] as? String, !s.isEmpty { return s }
        if let nested = dict["data"] as? [String: Any], let s = extractMessageId(from: nested) { return s }
        if let s = dict["data"] as? String, let mid = extractMessageId(fromJsonString: s) { return mid }
        if let pn = dict["pushedNotification"] as? [String: Any], let s = extractMessageId(from: pn) { return s }
        return nil
    }

    private static func extractMessageId(fromJsonString json: String) -> String? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let dict = obj as? [String: Any] {
            return extractMessageId(from: dict)
        }
        return nil
    }
}

