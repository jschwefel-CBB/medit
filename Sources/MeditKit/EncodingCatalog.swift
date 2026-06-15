import Foundation

/// The user-selectable text encodings for the status-bar encoding picker. Pure
/// value data; display names reuse TextEncodingDetector.displayName.
public enum EncodingCatalog {

    public struct Entry {
        public let encoding: String.Encoding
        public var displayName: String { TextEncodingDetector.displayName(for: encoding) }
        public init(_ encoding: String.Encoding) { self.encoding = encoding }
    }

    public static let selectable: [Entry] = [
        Entry(.utf8),
        Entry(.utf16),
        Entry(.isoLatin1),
        Entry(.ascii),
    ]
}
