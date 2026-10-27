import XCTest
@testable import RegnskapKit

final class JSONValueTests: XCTestCase {
    func testRoundTrip() throws {
        let data = Data(#"{"a":[1,"x",true,null],"b":{"c":2.5}}"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(value["a"]?[0]?.int, 1)
        XCTAssertEqual(value["a"]?[1]?.string, "x")
        XCTAssertEqual(value["a"]?[2]?.bool, true)
        XCTAssertEqual(value["a"]?[3], .null)
        XCTAssertEqual(value["b"]?["c"]?.double, 2.5)
        XCTAssertNil(value["missing"])
        let encoded = try JSONEncoder().encode(value)
        let again = try JSONDecoder().decode(JSONValue.self, from: encoded)
        XCTAssertEqual(again, value)
    }

    func testParsesLine() {
        XCTAssertEqual(JSONValue(line: #"{"k":"v"}"#)?["k"]?.string, "v")
        XCTAssertNil(JSONValue(line: "not json"))
    }
}
