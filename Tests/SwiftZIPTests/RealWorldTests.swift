import Foundation
import Testing
@testable import SwiftZIP

@Suite("Real-World ZIP Archives")
struct RealWorldTests {

    // MARK: - OOXML Paths

    /// Standard paths found in an .xlsx file.
    private static let ooxmlPaths: [String] = [
        "[Content_Types].xml",
        "_rels/.rels",
        "xl/workbook.xml",
        "xl/styles.xml",
        "xl/sharedStrings.xml",
        "xl/worksheets/sheet1.xml",
    ]

    // MARK: - Realistic XML Content

    private static let contentTypesXML: String = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
            <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
            <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
            <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
        </Types>
        """

    private static let relsXML: String = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """

    private static let workbookXML: String = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <sheets>
                <sheet name="Sheet1" sheetId="1" r:id="rId1" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>
            </sheets>
        </workbook>
        """

    private static let stylesXML: String = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <fonts count="1">
                <font><sz val="11"/><name val="Calibri"/></font>
            </fonts>
            <fills count="2">
                <fill><patternFill patternType="none"/></fill>
                <fill><patternFill patternType="gray125"/></fill>
            </fills>
            <borders count="1">
                <border><left/><right/><top/><bottom/><diagonal/></border>
            </borders>
            <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
            <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
        </styleSheet>
        """

    private static let sharedStringsXML: String = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="3" uniqueCount="3">
            <si><t>Revenue</t></si>
            <si><t>Expenses</t></si>
            <si><t>Net Income</t></si>
        </sst>
        """

    private static let worksheetXML: String = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <sheetData>
                <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1"><v>100000</v></c></row>
                <row r="2"><c r="A2" t="s"><v>1</v></c><c r="B2"><v>75000</v></c></row>
                <row r="3"><c r="A3" t="s"><v>2</v></c><c r="B3"><v>25000</v></c></row>
            </sheetData>
        </worksheet>
        """

    /// Builds the standard OOXML entries as (path, data) tuples.
    private static func ooxmlEntries() -> [(path: String, data: Data)] {
        [
            (ooxmlPaths[0], Data(contentTypesXML.utf8)),
            (ooxmlPaths[1], Data(relsXML.utf8)),
            (ooxmlPaths[2], Data(workbookXML.utf8)),
            (ooxmlPaths[3], Data(stylesXML.utf8)),
            (ooxmlPaths[4], Data(sharedStringsXML.utf8)),
            (ooxmlPaths[5], Data(worksheetXML.utf8)),
        ]
    }

    // MARK: - 1. XLSX-like Structure (Stored)

    @Test("XLSX-like stored ZIP contains all OOXML parts and round-trips correctly")
    func xlsxLikeStoredStructure() throws {
        let parts = RealWorldTests.ooxmlEntries()
        let zipEntries = parts.map { ZIPEntry(path: $0.path, data: $0.data) }
        let archive = try ZIPWriter.write(entries: zipEntries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 6)
        for (original, read) in zip(parts, result) {
            #expect(read.path == original.path)
            #expect(read.data == original.data)
        }
    }

    // MARK: - 2. XLSX-like Deflated

    @Test("XLSX-like deflated ZIP decompresses all OOXML parts correctly")
    func xlsxLikeDeflatedStructure() throws {
        let parts = RealWorldTests.ooxmlEntries()
        let archive = try buildMultiEntryDeflatedZIP(entries: parts)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 6)
        for (original, read) in zip(parts, result) {
            #expect(read.path == original.path)
            #expect(read.data == original.data)
            #expect(read.method == .deflated)
        }
    }

    // MARK: - 3. Content-Types XML

    @Test("Realistic [Content_Types].xml entry reads back with correct XML content")
    func contentTypesXMLRoundTrip() throws {
        let xmlData = Data(RealWorldTests.contentTypesXML.utf8)
        let entries = [ZIPEntry(path: "[Content_Types].xml", data: xmlData)]
        let archive = try ZIPWriter.write(entries: entries)

        let result = try ZIPReader.read(from: archive)
        #expect(result.count == 1)
        #expect(result[0].path == "[Content_Types].xml")

        let readXML = String(decoding: result[0].data, as: UTF8.self)
        #expect(readXML.contains("http://schemas.openxmlformats.org/package/2006/content-types"))
        #expect(readXML.contains("spreadsheetml.sheet.main+xml"))
        #expect(readXML.contains("spreadsheetml.styles+xml"))
    }

    // MARK: - 4. Shared Strings XML with Unicode

    @Test("Shared strings XML with unicode content survives round-trip")
    func sharedStringsUnicodeRoundTrip() throws {
        let unicodeSST = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="5" uniqueCount="5">
                <si><t>Revenu</t></si>
                <si><t>D\u{00E9}penses</t></si>
                <si><t>\u{00C9}conomies</t></si>
                <si><t>\u{65E5}\u{672C}\u{8A9E}</t></si>
                <si><t>R\u{00E9}sum\u{00E9}</t></si>
            </sst>
            """
        let xmlData = Data(unicodeSST.utf8)
        let entries = [ZIPEntry(path: "xl/sharedStrings.xml", data: xmlData)]
        let archive = try ZIPWriter.write(entries: entries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 1)
        let readXML = String(decoding: result[0].data, as: UTF8.self)
        #expect(readXML.contains("D\u{00E9}penses"))
        #expect(readXML.contains("\u{00C9}conomies"))
        #expect(readXML.contains("\u{65E5}\u{672C}\u{8A9E}"))
        #expect(readXML.contains("R\u{00E9}sum\u{00E9}"))
    }

    // MARK: - 5. Large Worksheet XML (1000 rows)

    @Test("Large worksheet XML with 1000 rows round-trips correctly")
    func largeWorksheetRoundTrip() throws {
        var xml = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
                <sheetData>

            """
        for row in 1...1000 {
            xml += "        <row r=\"\(row)\">"
            xml += "<c r=\"A\(row)\"><v>\(row)</v></c>"
            xml += "<c r=\"B\(row)\"><v>\(Double(row) * 1.5)</v></c>"
            xml += "<c r=\"C\(row)\"><v>\(row * 100)</v></c>"
            xml += "</row>\n"
        }
        xml += """
                </sheetData>
            </worksheet>
            """

        let xmlData = Data(xml.utf8)
        let entries = [ZIPEntry(path: "xl/worksheets/sheet1.xml", data: xmlData)]
        let archive = try ZIPWriter.write(entries: entries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 1)
        #expect(result[0].data == xmlData)

        let readXML = String(decoding: result[0].data, as: UTF8.self)
        #expect(readXML.contains("<row r=\"1\">"))
        #expect(readXML.contains("<row r=\"500\">"))
        #expect(readXML.contains("<row r=\"1000\">"))
    }

    // MARK: - 6. Read Entry by Path

    @Test("Read specific OOXML parts by path from a multi-entry ZIP")
    func readEntryByPath() throws {
        let parts = RealWorldTests.ooxmlEntries()
        let zipEntries = parts.map { ZIPEntry(path: $0.path, data: $0.data) }
        let archive = try ZIPWriter.write(entries: zipEntries)

        // Read the workbook by path
        let workbookOpt = try ZIPReader.readEntry(named: "xl/workbook.xml", from: archive)
        let workbook = try #require(workbookOpt)
        let workbookXML = String(decoding: workbook.data, as: UTF8.self)
        #expect(workbookXML.contains("<sheet name=\"Sheet1\""))

        // Read the styles by path
        let stylesOpt = try ZIPReader.readEntry(named: "xl/styles.xml", from: archive)
        let styles = try #require(stylesOpt)
        let stylesXML = String(decoding: styles.data, as: UTF8.self)
        #expect(stylesXML.contains("<font>"))

        // Non-existent path returns nil
        let missing = try ZIPReader.readEntry(named: "xl/not_here.xml", from: archive)
        #expect(missing == nil)
    }

    // MARK: - 7. List OOXML Parts

    @Test("listEntries returns all standard OOXML paths in order")
    func listOOXMLParts() throws {
        let parts = RealWorldTests.ooxmlEntries()
        let zipEntries = parts.map { ZIPEntry(path: $0.path, data: $0.data) }
        let archive = try ZIPWriter.write(entries: zipEntries)

        let paths = try ZIPReader.listEntries(in: archive)
        #expect(paths == RealWorldTests.ooxmlPaths)
    }

    // MARK: - 8. Mixed Compression (Stored + Deflated)

    @Test("ZIP with mixed stored and deflated entries reads both correctly")
    func mixedCompression() throws {
        let storedContent = Data(RealWorldTests.relsXML.utf8)
        let deflatedContent = Data(RealWorldTests.worksheetXML.utf8)

        let archive = try buildMixedCompressionZIP(
            storedEntries: [("_rels/.rels", storedContent)],
            deflatedEntries: [("xl/worksheets/sheet1.xml", deflatedContent)]
        )

        let result = try ZIPReader.read(from: archive)
        #expect(result.count == 2)

        // First entry: stored
        #expect(result[0].path == "_rels/.rels")
        #expect(result[0].data == storedContent)
        #expect(result[0].method == .stored)

        // Second entry: deflated
        #expect(result[1].path == "xl/worksheets/sheet1.xml")
        #expect(result[1].data == deflatedContent)
        #expect(result[1].method == .deflated)
    }

    // MARK: - 9. Realistic File Sizes

    @Test("Entries with realistic Excel file sizes round-trip correctly")
    func realisticFileSizes() throws {
        // ~500 bytes: rels file
        let relsData = makeRepeatedXML(
            template: "<Relationship Id=\"rId{n}\" Target=\"sheet{n}.xml\"/>",
            count: 10,
            wrapper: ("<Relationships>", "</Relationships>")
        )

        // ~2KB: styles file
        let stylesData = makeRepeatedXML(
            template: "<xf numFmtId=\"{n}\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>",
            count: 50,
            wrapper: ("<cellXfs>", "</cellXfs>")
        )

        // ~10KB: worksheet
        var worksheetXML = "<sheetData>"
        for row in 1...200 {
            worksheetXML += "<row r=\"\(row)\">"
            worksheetXML += "<c r=\"A\(row)\"><v>\(row)</v></c>"
            worksheetXML += "<c r=\"B\(row)\"><v>\(row * 2)</v></c>"
            worksheetXML += "<c r=\"C\(row)\"><v>\(row * 3)</v></c>"
            worksheetXML += "</row>"
        }
        worksheetXML += "</sheetData>"
        let worksheetData = Data(worksheetXML.utf8)

        let entries = [
            ZIPEntry(path: "_rels/.rels", data: relsData),
            ZIPEntry(path: "xl/styles.xml", data: stylesData),
            ZIPEntry(path: "xl/worksheets/sheet1.xml", data: worksheetData),
        ]
        let archive = try ZIPWriter.write(entries: entries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 3)
        // Verify sizes are in expected ranges
        #expect(result[0].data.count > 300)
        #expect(result[0].data.count < 1000)
        #expect(result[1].data.count > 1500)
        #expect(result[1].data.count < 5000)
        #expect(result[2].data.count > 8000)
        #expect(result[2].data.count < 20000)

        // Verify data integrity
        for (original, read) in zip(entries, result) {
            #expect(read.path == original.path)
            #expect(read.data == original.data)
        }
    }

    // MARK: - 10. UTF-8 Content Round-Trip

    @Test("XML entries with non-ASCII content (accented, CJK) survive round-trip through deflated ZIP")
    func utf8ContentDeflatedRoundTrip() throws {
        let unicodeXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <data>
                <item lang="fr">Pr\u{00EA}t hypoth\u{00E9}caire \u{00E0} taux fixe</item>
                <item lang="de">Verm\u{00F6}gensverwaltung und Finanzberatung</item>
                <item lang="ja">\u{8CA1}\u{52D9}\u{8AF8}\u{8868}\u{306E}\u{5206}\u{6790}</item>
                <item lang="zh">\u{8D44}\u{4EA7}\u{8D1F}\u{503A}\u{8868}</item>
                <item lang="ko">\u{C7AC}\u{BB34}\u{C81C}\u{D45C}</item>
                <item lang="ar">\u{0627}\u{0644}\u{0645}\u{064A}\u{0632}\u{0627}\u{0646}\u{064A}\u{0629} \u{0627}\u{0644}\u{0639}\u{0645}\u{0648}\u{0645}\u{064A}\u{0629}</item>
                <item special="symbols">\u{00A3}100 \u{00B7} \u{20AC}200 \u{00B7} \u{00A5}300</item>
            </data>
            """
        let xmlData = Data(unicodeXML.utf8)

        let entries: [(path: String, data: Data)] = [
            ("xl/unicode_data.xml", xmlData),
        ]
        let archive = try buildMultiEntryDeflatedZIP(entries: entries)
        let result = try ZIPReader.read(from: archive)

        #expect(result.count == 1)
        #expect(result[0].data == xmlData)

        let readXML = String(decoding: result[0].data, as: UTF8.self)
        // French
        #expect(readXML.contains("Pr\u{00EA}t hypoth\u{00E9}caire"))
        // German
        #expect(readXML.contains("Verm\u{00F6}gensverwaltung"))
        // Japanese
        #expect(readXML.contains("\u{8CA1}\u{52D9}\u{8AF8}\u{8868}"))
        // Chinese
        #expect(readXML.contains("\u{8D44}\u{4EA7}\u{8D1F}\u{503A}\u{8868}"))
        // Korean
        #expect(readXML.contains("\u{C7AC}\u{BB34}\u{C81C}\u{D45C}"))
        // Currency symbols
        #expect(readXML.contains("\u{00A3}100"))
        #expect(readXML.contains("\u{20AC}200"))
        #expect(readXML.contains("\u{00A5}300"))
    }

    // MARK: - Helpers

    /// Builds a ZIP archive with multiple deflated entries.
    ///
    /// Since ``ZIPWriter`` only supports stored entries, this constructs the
    /// binary ZIP format directly with deflated payloads to simulate what
    /// Excel and other tools produce.
    private func buildMultiEntryDeflatedZIP(
        entries: [(path: String, data: Data)]
    ) throws -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var entryCount: UInt16 = 0

        for (path, originalData) in entries {
            let compressed = try Deflate.compress(originalData)
            let crc = CRC32.calculate(originalData)
            let pathData = Data(path.utf8)
            let localOffset = UInt32(archive.count)

            // Local file header
            archive.appendUInt32(0x04034B50)
            archive.appendUInt16(20)                              // version needed
            archive.appendUInt16(0)                               // flags
            archive.appendUInt16(8)                               // deflated
            archive.appendUInt16(0)                               // mod time
            archive.appendUInt16(0)                               // mod date
            archive.appendUInt32(crc)
            archive.appendUInt32(UInt32(compressed.count))        // compressed size
            archive.appendUInt32(UInt32(originalData.count))      // uncompressed size
            archive.appendUInt16(UInt16(pathData.count))
            archive.appendUInt16(0)                               // extra field length
            archive.append(pathData)
            archive.append(compressed)

            // Central directory entry
            centralDirectory.appendUInt32(0x02014B50)
            centralDirectory.appendUInt16(20)                     // version made by
            centralDirectory.appendUInt16(20)                     // version needed
            centralDirectory.appendUInt16(0)                      // flags
            centralDirectory.appendUInt16(8)                      // deflated
            centralDirectory.appendUInt16(0)                      // mod time
            centralDirectory.appendUInt16(0)                      // mod date
            centralDirectory.appendUInt32(crc)
            centralDirectory.appendUInt32(UInt32(compressed.count))
            centralDirectory.appendUInt32(UInt32(originalData.count))
            centralDirectory.appendUInt16(UInt16(pathData.count))
            centralDirectory.appendUInt16(0)                      // extra field length
            centralDirectory.appendUInt16(0)                      // comment length
            centralDirectory.appendUInt16(0)                      // disk number start
            centralDirectory.appendUInt16(0)                      // internal attributes
            centralDirectory.appendUInt32(0)                      // external attributes
            centralDirectory.appendUInt32(localOffset)
            centralDirectory.append(pathData)
            entryCount += 1
        }

        let cdOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        let cdSize = UInt32(centralDirectory.count)

        // End of Central Directory
        archive.appendUInt32(0x06054B50)
        archive.appendUInt16(0)                                   // disk number
        archive.appendUInt16(0)                                   // disk with CD
        archive.appendUInt16(entryCount)
        archive.appendUInt16(entryCount)
        archive.appendUInt32(cdSize)
        archive.appendUInt32(cdOffset)
        archive.appendUInt16(0)                                   // comment length

        return archive
    }

    /// Builds a ZIP archive with a mix of stored and deflated entries.
    private func buildMixedCompressionZIP(
        storedEntries: [(String, Data)],
        deflatedEntries: [(String, Data)]
    ) throws -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var entryCount: UInt16 = 0

        // Write stored entries
        for (path, data) in storedEntries {
            let crc = CRC32.calculate(data)
            let pathData = Data(path.utf8)
            let localOffset = UInt32(archive.count)

            // Local file header
            archive.appendUInt32(0x04034B50)
            archive.appendUInt16(20)
            archive.appendUInt16(0)
            archive.appendUInt16(0)                               // stored
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt32(crc)
            archive.appendUInt32(UInt32(data.count))              // compressed = uncompressed
            archive.appendUInt32(UInt32(data.count))
            archive.appendUInt16(UInt16(pathData.count))
            archive.appendUInt16(0)
            archive.append(pathData)
            archive.append(data)

            // Central directory entry
            centralDirectory.appendUInt32(0x02014B50)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)                      // stored
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(crc)
            centralDirectory.appendUInt32(UInt32(data.count))
            centralDirectory.appendUInt32(UInt32(data.count))
            centralDirectory.appendUInt16(UInt16(pathData.count))
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(0)
            centralDirectory.appendUInt32(localOffset)
            centralDirectory.append(pathData)
            entryCount += 1
        }

        // Write deflated entries
        for (path, originalData) in deflatedEntries {
            let compressed = try Deflate.compress(originalData)
            let crc = CRC32.calculate(originalData)
            let pathData = Data(path.utf8)
            let localOffset = UInt32(archive.count)

            // Local file header
            archive.appendUInt32(0x04034B50)
            archive.appendUInt16(20)
            archive.appendUInt16(0)
            archive.appendUInt16(8)                               // deflated
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt32(crc)
            archive.appendUInt32(UInt32(compressed.count))
            archive.appendUInt32(UInt32(originalData.count))
            archive.appendUInt16(UInt16(pathData.count))
            archive.appendUInt16(0)
            archive.append(pathData)
            archive.append(compressed)

            // Central directory entry
            centralDirectory.appendUInt32(0x02014B50)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(8)                      // deflated
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(crc)
            centralDirectory.appendUInt32(UInt32(compressed.count))
            centralDirectory.appendUInt32(UInt32(originalData.count))
            centralDirectory.appendUInt16(UInt16(pathData.count))
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(0)
            centralDirectory.appendUInt32(localOffset)
            centralDirectory.append(pathData)
            entryCount += 1
        }

        let cdOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        let cdSize = UInt32(centralDirectory.count)

        // End of Central Directory
        archive.appendUInt32(0x06054B50)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(entryCount)
        archive.appendUInt16(entryCount)
        archive.appendUInt32(cdSize)
        archive.appendUInt32(cdOffset)
        archive.appendUInt16(0)

        return archive
    }

    /// Builds XML with a repeated element pattern, useful for generating
    /// content of a specific approximate size.
    private func makeRepeatedXML(
        template: String,
        count: Int,
        wrapper: (String, String)
    ) -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += wrapper.0 + "\n"
        for i in 1...count {
            xml += "    " + template.replacingOccurrences(of: "{n}", with: "\(i)") + "\n"
        }
        xml += wrapper.1 + "\n"
        return Data(xml.utf8)
    }
}
