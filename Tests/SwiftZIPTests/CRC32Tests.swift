import Testing
import Foundation
@testable import SwiftZIP

@Suite("CRC32 Checksum Tests")
struct CRC32Tests {
    @Test("Empty data produces CRC of 0x00000000")
    func emptyData() {
        let crc = CRC32.calculate(Data())
        #expect(crc == 0x00000000)
    }

    @Test("Known vector: ASCII '123456789' produces 0xCBF43926")
    func knownVector123456789() {
        let data = Data("123456789".utf8)
        let crc = CRC32.calculate(data)
        #expect(crc == 0xCBF43926)
    }

    @Test("Known vector: single zero byte")
    func singleZeroByte() {
        let data = Data([0x00])
        let crc = CRC32.calculate(data)
        #expect(crc == 0xD202EF8D)
    }

    @Test("Round-trip consistency: same data always produces same CRC")
    func roundTripConsistency() {
        let data = Data("Hello, SwiftZIP!".utf8)
        let crc1 = CRC32.calculate(data)
        let crc2 = CRC32.calculate(data)
        #expect(crc1 == crc2)
    }

    @Test("Large data: 1MB of zeros produces consistent result")
    func largeDataConsistency() {
        let data = Data(repeating: 0x00, count: 1_000_000)
        let crc1 = CRC32.calculate(data)
        let crc2 = CRC32.calculate(data)
        #expect(crc1 == crc2)
        // Known CRC-32 for 1,000,000 zero bytes
        #expect(crc1 == 0x1279CB9E)
    }

    @Test("Various byte patterns produce distinct CRCs")
    func variousBytePatterns() {
        let allZeros = CRC32.calculate(Data(repeating: 0x00, count: 4))
        let allOnes = CRC32.calculate(Data(repeating: 0xFF, count: 4))
        let ascending = CRC32.calculate(Data([0x01, 0x02, 0x03, 0x04]))
        #expect(allZeros != allOnes)
        #expect(allZeros != ascending)
        #expect(allOnes != ascending)
    }

    @Test("Lookup table has 256 entries")
    func tableSize() {
        #expect(CRC32.table.count == 256)
    }
}
