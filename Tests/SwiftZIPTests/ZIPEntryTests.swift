import Testing
import Foundation
@testable import SwiftZIP

@Suite("ZIPEntry Tests")
struct ZIPEntryTests {
    @Test("Default compression method is .stored")
    func defaultMethodIsStored() {
        let entry = ZIPEntry(path: "test.txt", data: Data("hello".utf8))
        #expect(entry.method == .stored)
    }

    @Test("Explicit compression method is preserved")
    func explicitMethod() {
        let entry = ZIPEntry(path: "test.txt", data: Data("hello".utf8), method: .deflated)
        #expect(entry.method == .deflated)
    }

    @Test("Equatable: identical entries are equal")
    func equatableIdentical() {
        let data = Data("content".utf8)
        let a = ZIPEntry(path: "file.txt", data: data, method: .stored)
        let b = ZIPEntry(path: "file.txt", data: data, method: .stored)
        #expect(a == b)
    }

    @Test("Equatable: different paths are not equal")
    func equatableDifferentPaths() {
        let data = Data("content".utf8)
        let a = ZIPEntry(path: "file1.txt", data: data)
        let b = ZIPEntry(path: "file2.txt", data: data)
        #expect(a != b)
    }

    @Test("Equatable: different data are not equal")
    func equatableDifferentData() {
        let a = ZIPEntry(path: "file.txt", data: Data("aaa".utf8))
        let b = ZIPEntry(path: "file.txt", data: Data("bbb".utf8))
        #expect(a != b)
    }

    @Test("Equatable: different methods are not equal")
    func equatableDifferentMethods() {
        let data = Data("content".utf8)
        let a = ZIPEntry(path: "file.txt", data: data, method: .stored)
        let b = ZIPEntry(path: "file.txt", data: data, method: .deflated)
        #expect(a != b)
    }

    @Test("Sendable conformance compiles in sendable context")
    func sendableConformance() async {
        let entry = ZIPEntry(path: "test.txt", data: Data("hello".utf8))
        let task = Task { @Sendable in
            return entry.path
        }
        let result = await task.value
        #expect(result == "test.txt")
    }

    @Test("Properties are stored correctly")
    func propertiesStored() {
        let data = Data([0x01, 0x02, 0x03])
        let entry = ZIPEntry(path: "dir/file.bin", data: data, method: .deflated)
        #expect(entry.path == "dir/file.bin")
        #expect(entry.data == data)
        #expect(entry.method == .deflated)
    }
}
