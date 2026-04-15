import Foundation
import CommonCrypto

extension UsageMonitorCommand {
    // Keep key derivation and cookie decryption together so provider files can reuse one compatibility path.
    func deriveClaudeDesktopKey(secret: String) -> Data? {
        let password = Array(secret.utf8)
        let salt = Array("saltysalt".utf8)
        var derived = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            String(decoding: password, as: UTF8.self),
            password.count,
            salt,
            salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
            1003,
            &derived,
            derived.count
        )
        guard status == kCCSuccess else { return nil }
        return Data(derived)
    }

    func dataFromHexString(_ hex: String) -> Data? {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count.isMultiple(of: 2) else { return nil }

        var data = Data(capacity: trimmed.count / 2)
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let nextIndex = trimmed.index(index, offsetBy: 2)
            guard let byte = UInt8(trimmed[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        return data
    }

    func stringFromHexString(_ hex: String) -> String? {
        guard let data = dataFromHexString(hex) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func decryptClaudeDesktopCache(encryptedData: Data, key: Data) -> Data? {
        decryptChromiumCookieValue(encryptedData: encryptedData, key: key)
    }

    func decryptChromiumCookieValue(encryptedData: Data, key: Data) -> Data? {
        let prefix = Data("v10".utf8)
        let ciphertext: Data
        if encryptedData.starts(with: prefix) {
            ciphertext = encryptedData.dropFirst(prefix.count)
        } else {
            ciphertext = encryptedData
        }

        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: ciphertext.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var decryptedLength = 0

        let status = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress,
                            ciphertext.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &decryptedLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        output.removeSubrange(decryptedLength..<output.count)
        return output
    }

    func extractClaudeSessionKey(from decrypted: Data) -> String? {
        let decoded = String(decoding: decrypted, as: UTF8.self)
        guard let range = decoded.range(of: #"sk-ant-[A-Za-z0-9_-]+"#, options: .regularExpression) else {
            return nil
        }
        return String(decoded[range])
    }
}
