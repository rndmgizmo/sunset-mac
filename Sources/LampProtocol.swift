import Foundation
import CommonCrypto

enum LampProtocol {
    static let header: [UInt8] = [0x54, 0x52, 0x00, 0x57]
    private static let key: [UInt8] = [0x34, 0x52, 0x2a, 0x5b, 0x7a, 0x6e, 0x49, 0x2c,
                                       0x08, 0x09, 0x0a, 0x9d, 0x8d, 0x2a, 0x23, 0xf8]

    static func join() -> Data { encrypt(frame(command: 1)) }

    static func color(red: UInt8, green: UInt8, blue: UInt8, brightness: Int, mode: UInt8 = 0, speed: Int = 100) -> Data {
        var bytes = frame(command: 2)
        bytes[6] = mode
        bytes[7] = red; bytes[8] = green; bytes[9] = blue
        bytes[10] = UInt8(max(0, min(100, brightness)))
        bytes[11] = UInt8(max(1, min(100, speed)))
        return encrypt(bytes)
    }

    static func off() -> Data { color(red: 0, green: 0, blue: 0, brightness: 0) }

    private static func frame(command: UInt8) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes.replaceSubrange(0..<4, with: header)
        bytes[4] = command; bytes[5] = 1
        return bytes
    }

    static func decrypt(_ data: Data) -> [UInt8]? {
        guard data.count == 16 else { return nil }
        let bytes = crypt(Array(data), operation: CCOperation(kCCDecrypt))
        return Array(bytes.prefix(4)) == header ? bytes : nil
    }

    private static func encrypt(_ bytes: [UInt8]) -> Data {
        Data(crypt(bytes, operation: CCOperation(kCCEncrypt)))
    }

    private static func crypt(_ bytes: [UInt8], operation: CCOperation) -> [UInt8] {
        precondition(bytes.count == 16)
        var output = [UInt8](repeating: 0, count: 16)
        var moved = 0
        let status = key.withUnsafeBytes { keyBuffer in
            bytes.withUnsafeBytes { input in
                output.withUnsafeMutableBytes { result in
                    CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                            keyBuffer.baseAddress, key.count, nil, input.baseAddress, bytes.count,
                            result.baseAddress, 16, &moved)
                }
            }
        }
        precondition(status == kCCSuccess && moved == 16, "AES operation failed")
        return output
    }
}
