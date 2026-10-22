import Foundation

func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

// Independent AES-ECB vectors cross-checked with OpenSSL.
precondition(hex(LampProtocol.join()) == "814070cf48ab60e4b8079d5e273c78a0")
let orange = LampProtocol.color(red: 255, green: 80, blue: 8, brightness: 40)
precondition(hex(orange) == "706272fc3fee3259ec18c67d341bf90c")
let decoded = LampProtocol.decrypt(orange)!
precondition(decoded == [0x54, 0x52, 0, 0x57, 2, 1, 0, 255, 80, 8, 40, 100, 0, 0, 0, 0])
precondition(LampProtocol.decrypt(Data(repeating: 0, count: 16)) == nil)
precondition(LampProtocol.decrypt(Data(repeating: 0, count: 15)) == nil)
let off = LampProtocol.decrypt(LampProtocol.off())!
precondition(off[6...10].allSatisfy { $0 == 0 })
let clamped = LampProtocol.decrypt(LampProtocol.color(red: 1, green: 2, blue: 3, brightness: 999, speed: -10))!
precondition(clamped[10] == 100 && clamped[11] == 1)
// Regression: the first reconnect must not spend eight seconds in a retry gap.
precondition(ConnectionTiming.retryDelay(afterFailures: 0) == 0)
let repeatedFailures = (0..<10).map { ConnectionTiming.retryDelay(afterFailures: $0) }
precondition(repeatedFailures == [0, 1, 2, 4, 8, 8, 8, 8, 8, 8])
print("Checks passed: AES vectors, frame format, off, input limits, invalid notifications, immediate reconnect, bounded error backoff.")
