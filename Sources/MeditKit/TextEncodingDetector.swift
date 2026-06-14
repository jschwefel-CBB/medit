import Foundation

/// Detects the text encoding of raw file bytes and decodes them, and performs
/// the inverse encode for saving. Pure value logic — no AppKit, fully testable.
///
/// Strategy (in order):
///   1. Honor a leading byte-order mark (UTF-8, UTF-16 LE/BE, UTF-32 LE/BE).
///   2. Try strict UTF-8.
///   3. Fall back to ISO Latin-1, which maps every possible byte and therefore
///      never fails — this is the "don't lose the user's file" safety net that
///      mirrors how gedit degrades to a single-byte encoding.
public enum TextEncodingDetector {

    /// The result of decoding raw bytes into text.
    public struct Decoded: Equatable {
        public let string: String
        public let encoding: String.Encoding
        /// True when the source bytes began with a byte-order mark.
        public let hadBOM: Bool

        public init(string: String, encoding: String.Encoding, hadBOM: Bool) {
            self.string = string
            self.encoding = encoding
            self.hadBOM = hadBOM
        }
    }

    // MARK: Decoding

    /// Decode raw bytes to text, inferring the encoding. Returns `nil` only in
    /// the theoretically-impossible case that even Latin-1 decoding fails.
    public static func decode(_ data: Data) -> Decoded? {
        if let bomDecoded = decodeUsingBOM(data) {
            return bomDecoded
        }

        // Strict UTF-8: reject invalid byte sequences so we can fall through
        // to Latin-1 rather than silently producing replacement characters.
        if let utf8 = String(bytes: data, encoding: .utf8) {
            return Decoded(string: utf8, encoding: .utf8, hadBOM: false)
        }

        // Latin-1 is total over bytes: this always succeeds.
        if let latin1 = String(bytes: data, encoding: .isoLatin1) {
            return Decoded(string: latin1, encoding: .isoLatin1, hadBOM: false)
        }

        return nil
    }

    private static func decodeUsingBOM(_ data: Data) -> Decoded? {
        let bytes = [UInt8](data.prefix(4))

        // UTF-32 BOMs must be checked before UTF-16, since UTF-32 LE begins
        // with the same two bytes as UTF-16 LE (0xFF 0xFE).
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return decode(stripping: 4, from: data, as: .utf32BigEndian)
        }
        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            return decode(stripping: 4, from: data, as: .utf32LittleEndian)
        }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return decode(stripping: 3, from: data, as: .utf8)
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            return decode(stripping: 2, from: data, as: .utf16BigEndian)
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            return decode(stripping: 2, from: data, as: .utf16LittleEndian)
        }
        return nil
    }

    private static func decode(stripping bomLength: Int, from data: Data, as encoding: String.Encoding) -> Decoded? {
        let payload = data.dropFirst(bomLength)
        guard let string = String(bytes: payload, encoding: encoding) else { return nil }
        // Report the family encoding (e.g. .utf16) so round-trips re-emit a BOM.
        let reported: String.Encoding
        switch encoding {
        case .utf16LittleEndian, .utf16BigEndian: reported = .utf16
        case .utf32LittleEndian, .utf32BigEndian: reported = .utf32
        default: reported = encoding
        }
        return Decoded(string: string, encoding: reported, hadBOM: true)
    }

    // MARK: Encoding

    /// Encode text for writing to disk. When `includeBOM` is true and the
    /// encoding is UTF-8, a UTF-8 BOM is prepended. (UTF-16/32 already emit a
    /// BOM via Foundation's encoders.)
    public static func encode(_ string: String, as encoding: String.Encoding, includeBOM: Bool) -> Data {
        if encoding == .utf8 {
            var data = includeBOM ? Data([0xEF, 0xBB, 0xBF]) : Data()
            data.append(Data(string.utf8))
            return data
        }
        return string.data(using: encoding) ?? Data(string.utf8)
    }
}
