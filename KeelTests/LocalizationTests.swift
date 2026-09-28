import XCTest
@testable import Keel

final class LocalizationTests: XCTestCase {
  private func bundle(_ language: String) throws -> Bundle {
    let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), "\(language) is missing")
    return try XCTUnwrap(Bundle(path: path))
  }

  func testEveryLanguageShipsTheCatalog() throws {
    let expected = ["pt-PT": "Limite de carga", "fr": "Limite de charge", "es": "Límite de carga", "de": "Ladelimit"]
    for (language, value) in expected {
      XCTAssertEqual(try bundle(language).localizedString(forKey: "Charge limit", value: nil, table: nil), value)
    }
  }

  func testFormatStringsKeepTheirPlaceholders() throws {
    let format = try bundle("de").localizedString(forKey: "Set charge limit to %lld%%", value: nil, table: nil)
    XCTAssertEqual(String(format: format, 85), "Ladelimit auf 85 % setzen")
  }
}
