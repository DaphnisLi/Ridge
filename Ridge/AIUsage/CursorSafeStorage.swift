import Foundation
import Security

/// 解密 Cursor 3.x 写入 `state.vscdb` 的 `cursor-safe-storage:v1:` Electron safeStorage 载荷。
enum CursorSafeStorage {
    static let prefix = "cursor-safe-storage:v1:"
    private static let keychainService = "Cursor Safe Storage"
    private static let keychainAccount = "Cursor Key"

    static func isEncrypted(_ value: String) -> Bool {
        value.hasPrefix(prefix)
    }

    /// 返回明文 JWT；失败抛错（含钥匙串拒绝）。
    static func decryptToken(_ stored: String) throws -> String {
        if !isEncrypted(stored) {
            return stored.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let password = try readKeychainPassword()
        guard let payload = Data(base64Encoded: String(stored.dropFirst(prefix.count))) else {
            throw CursorAuthError.decryptFailed
        }
        guard payload.count > 3, String(data: payload.prefix(3), encoding: .utf8) == "v10" else {
            throw CursorAuthError.decryptFailed
        }
        let cipher = payload.dropFirst(3)
        let key = try deriveChromiumKey(password: password)
        let plain = try aes128CBCDecrypt(data: Data(cipher), key: key, iv: Data(repeating: 0x20, count: 16))
        let token = String(data: plain, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        guard let token, !token.isEmpty else { throw CursorAuthError.decryptFailed }
        return token
    }

    private static func readKeychainPassword() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let password = String(data: data, encoding: .utf8), !password.isEmpty
        else {
            AppLog.warn("AIUsage", "无法读取 Cursor Safe Storage 钥匙串", ["status": status])
            throw CursorAuthError.keychainDenied
        }
        return password
    }

    private static func deriveChromiumKey(password: String) throws -> Data {
        var derived = Data(count: 16)
        let passwordData = Data(password.utf8)
        let salt = Data("saltysalt".utf8)
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            passwordData.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        16
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CursorAuthError.decryptFailed }
        return derived
    }

    private static func aes128CBCDecrypt(data: Data, key: Data, iv: Data) throws -> Data {
        let outCapacity = data.count + kCCBlockSizeAES128
        var out = Data(count: outCapacity)
        var outLength = 0
        let status: CCCryptorStatus = out.withUnsafeMutableBytes { outBytes in
            guard let outBase = outBytes.baseAddress else { return CCCryptorStatus(kCCParamError) }
            return data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        var moved = 0
                        let result = CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            outBase, outCapacity,
                            &moved
                        )
                        outLength = moved
                        return result
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw CursorAuthError.decryptFailed }
        return out.prefix(outLength)
    }
}

enum CursorAuthError: Error {
    case databaseMissing
    case tokenMissing
    case keychainDenied
    case decryptFailed
    case httpStatus(Int)
    case decodeFailed
    case offline
}
