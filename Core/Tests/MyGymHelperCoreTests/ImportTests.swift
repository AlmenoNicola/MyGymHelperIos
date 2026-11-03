import XCTest
@testable import MyGymHelperCore

/// Schede in tabella (Excel, Word, CSV, PDF/foto con colonne). Stessi casi di ImportTests.kt.
final class TablePlanTests: XCTestCase {
    func testTabSeparatedTableWithHeader() {
        let text = "Giorno A\n" +
            "Esercizio\tSerie\tRipetizioni\tPeso (kg)\tRecupero\n" +
            "Panca piana\t4\t8-10\t60\t90\"\n" +
            "Croci con manubri\t3\t12\t\t1'30\n" +
            "Squat\t5\t5\t82,5\t2 min\n"
        let plan = TrainingPlanParser.parse(text)
        XCTAssertEqual(plan.days.count, 1)
        XCTAssertEqual(plan.days[0].title, "Giorno A")
        let e = plan.days[0].entries
        XCTAssertEqual(e.count, 3)
        XCTAssertEqual(e[0].name, "Panca piana")
        XCTAssertEqual(e[0].sets, 4); XCTAssertEqual(e[0].repsMin, 8); XCTAssertEqual(e[0].repsMax, 10)
        XCTAssertEqual(e[0].weightKg, 60); XCTAssertEqual(e[0].restSeconds, 90)
        XCTAssertEqual(e[1].name, "Croci con manubri")
        XCTAssertNil(e[1].weightKg); XCTAssertEqual(e[1].restSeconds, 90)
        XCTAssertEqual(e[2].weightKg, 82.5); XCTAssertEqual(e[2].restSeconds, 120)
    }

    func testHeaderWithDayInFirstCell() {
        let text = "Lunedì\tSerie\tRip\tKg\nLat machine\t4\t10\t45\nGiorno B\tSerie\tRip\tKg\nCurl\t3\t12\t12,5\n"
        let plan = TrainingPlanParser.parse(text)
        XCTAssertEqual(plan.days.count, 2)
        XCTAssertEqual(plan.days[0].title, "Lunedì")
        XCTAssertEqual(plan.days[0].entries[0].name, "Lat machine")
        XCTAssertEqual(plan.days[0].entries[0].weightKg, 45)
        XCTAssertEqual(plan.days[1].title, "Giorno B")
        XCTAssertEqual(plan.days[1].entries[0].weightKg, 12.5)
    }

    func testCombinedSetsRepsColumn() {
        let e = TrainingPlanParser.parse("Esercizio | Serie x Ripetizioni | Carico\nStacco | 3x5 | 100\n").allEntries
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].name, "Stacco"); XCTAssertEqual(e[0].sets, 3); XCTAssertEqual(e[0].repsMin, 5); XCTAssertEqual(e[0].weightKg, 100)
    }

    func testOcrRowsWithMissingCells() {
        // L'OCR non vede le celle vuote: i valori si assegnano in ordine, le unita' decidono la colonna.
        let text = "Esercizio Serie Ripetizioni Peso Recupero\n" +
            "Panca piana\t4\t10\t60 kg\t90\"\n" +
            "Piegamenti\t3\t15\t60\"\n" +
            "Rematore 4 8 40\n" +
            "Giorno B\n" +
            "Curl 3 12\n"
        let plan = TrainingPlanParser.parse(text)
        XCTAssertEqual(plan.days.count, 2)
        XCTAssertEqual(plan.days[1].title, "Giorno B")
        XCTAssertEqual(plan.days[1].entries.map(\.name), ["Curl"])
        let e = plan.days[0].entries
        XCTAssertEqual(e.count, 3)
        XCTAssertEqual(e[0].weightKg, 60); XCTAssertEqual(e[0].restSeconds, 90)
        XCTAssertEqual(e[1].name, "Piegamenti"); XCTAssertNil(e[1].weightKg); XCTAssertEqual(e[1].restSeconds, 60)
        XCTAssertEqual(e[2].name, "Rematore"); XCTAssertEqual(e[2].sets, 4); XCTAssertEqual(e[2].repsMin, 8); XCTAssertEqual(e[2].weightKg, 40)
    }

    func testRepsOnlyAndNotesIgnored() {
        let e = TrainingPlanParser.parse("Esercizio\tRipetizioni\tNote\nPlank\t\tTenere 30 secondi\nAddominali\t20\tlenti\n").allEntries
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].name, "Addominali"); XCTAssertNil(e[0].sets); XCTAssertEqual(e[0].repsMin, 20)
    }

    func testOldFormatStillWorksAfterHeader() {
        let e = TrainingPlanParser.parse("Esercizio\tSerie\tRip\nPanca\t4\t8\nSquat 5x5 80kg\n").allEntries
        XCTAssertEqual(e.count, 2)
        XCTAssertEqual(e[1].weightKg, 80)
    }

    func testRestCellFormats() {
        XCTAssertEqual(TrainingPlanParser.restCell("1'30"), 90)
        XCTAssertEqual(TrainingPlanParser.restCell("1:30"), 90)
        XCTAssertEqual(TrainingPlanParser.restCell("2 min"), 120)
        XCTAssertEqual(TrainingPlanParser.restCell("75\""), 75)
        XCTAssertEqual(TrainingPlanParser.restCell("3"), 180)
    }
}

final class OfficeTextTests: XCTestCase {
    /// Lo stesso .xlsx di prova di ImportTests.kt (zip con compressione deflate), in base64.
    private let xlsxBase64 = "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"

    func testDetectsKinds() {
        XCTAssertEqual(OfficeText.detect(Data("%PDF-1.7 ...".utf8)), .pdf)
        XCTAssertEqual(OfficeText.detect(Data(base64Encoded: xlsxBase64)!), .zip)
        XCTAssertEqual(OfficeText.detect(Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0])), .legacyOffice)
        XCTAssertEqual(OfficeText.detect(Data([0xFF, 0xD8, 0xFF, 0xE0])), .image)
        XCTAssertEqual(OfficeText.detect(Data("Panca 4x8".utf8)), .other)
    }

    func testXlsxToPlan() throws {
        let entries = try OfficeText.unzipXML(Data(base64Encoded: xlsxBase64)!)
        let text = try XCTUnwrap(OfficeText.fromOOXML(entries))
        XCTAssertTrue(text.hasPrefix("Giorno A\n\tEsercizio\tSerie\tRipetizioni\tPeso\n\tPanca & piana\t4\t8-10\t62.5\n\tCurl\t3\t12\t\n"), text)
        let plan = TrainingPlanParser.parse(text)
        XCTAssertEqual(plan.days.map(\.title), ["Giorno A"])
        let e = plan.allEntries
        XCTAssertEqual(e[0].name, "Panca & piana"); XCTAssertEqual(e[0].repsMax, 10); XCTAssertEqual(e[0].weightKg, 62.5)
        XCTAssertEqual(e[1].name, "Curl"); XCTAssertEqual(e[1].repsMin, 12); XCTAssertNil(e[1].weightKg)
    }

    func testDocxTableAndParagraphs() {
        let doc = """
        <w:document xmlns:w="w"><w:body>
        <w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs></w:pPr><w:r><w:t>Giorno 1</w:t></w:r></w:p>
        <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Esercizio</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Serie</w:t></w:r></w:p></w:tc>
          <w:tc><w:p><w:r><w:t>Rip.</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Kg</w:t></w:r></w:p></w:tc></w:tr>
        <w:tr><w:tc><w:p><w:r><w:t>Leg</w:t></w:r><w:r><w:t xml:space="preserve"> press</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>4</w:t></w:r></w:p></w:tc>
          <w:tc><w:p><w:r><w:t>12</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>120</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        <w:p><w:r><w:t>Plank</w:t></w:r><w:r><w:tab/><w:t>3x30</w:t></w:r></w:p>
        </w:body></w:document>
        """
        let text = OfficeText.fromOOXML(["word/document.xml": doc])
        XCTAssertEqual(text, "Giorno 1\nEsercizio\tSerie\tRip.\tKg\nLeg press\t4\t12\t120\nPlank\t3x30\n")
        let plan = TrainingPlanParser.parse(text ?? "")
        XCTAssertEqual(plan.days.map(\.title), ["Giorno 1"])
        XCTAssertEqual(plan.allEntries[0].weightKg, 120)
        XCTAssertEqual(plan.allEntries[1].name, "Plank")
    }

    func testCsvWithSemicolonsAndQuotes() {
        let text = OfficeText.csvToTabs("Esercizio;Serie;Ripetizioni;Peso\r\n\"Panca; inclinata\";4;10;\"22,5\"\r\nCurl;3;12;\n")
        XCTAssertEqual(text, "Esercizio\tSerie\tRipetizioni\tPeso\nPanca; inclinata\t4\t10\t22,5\nCurl\t3\t12\t\n")
        XCTAssertEqual(TrainingPlanParser.parse(text).allEntries[0].weightKg, 22.5)
    }

    func testXmlEntitiesAndBinary() {
        XCTAssertEqual(XMLTokens.decode("a&lt;b &amp; &quot;c&quot; &#233;"), "a<b & \"c\" é")
        XCTAssertTrue(OfficeText.looksBinary("\u{0}\u{1}\u{2}abc\u{3}\u{4}"))
        XCTAssertFalse(OfficeText.looksBinary("Panca\t4\t8\n"))
        XCTAssertEqual(OfficeText.columnIndex("AB12"), 27)
    }
}
