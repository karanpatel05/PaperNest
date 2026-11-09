import Foundation
import Testing
import PaperNestCore

@Suite struct InlineTextStyleTests {
    // If defaulted decoding drops new style keys, older libraries open but every
    // subsequent save silently turns formatted text back into regular Helvetica.
    @Test func decodingAndReencodingRetainsFontTraits() throws {
        let original = TextBox(frame: CGRect(x: 20, y: 30, width: 200, height: 80), text: "Styled")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["fontFamily"] = "serif"
        json["isBold"] = true
        json["isItalic"] = true
        let decoded = try JSONDecoder().decode(TextBox.self, from: JSONSerialization.data(withJSONObject: json))
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        #expect(encoded["fontFamily"] as? String == "serif")
        #expect(encoded["isBold"] as? Bool == true)
        #expect(encoded["isItalic"] as? Bool == true)
    }

    @Test func legacyTextWithoutStyleKeysStillDecodes() throws {
        let original = TextBox(frame: CGRect(x: 20, y: 30, width: 200, height: 80), text: "Legacy")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        for key in ["fontFamily", "isBold", "isItalic"] { json.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(TextBox.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded == original)
    }
}
