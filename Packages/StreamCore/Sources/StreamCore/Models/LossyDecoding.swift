import Foundation

/// Decodes an array while skipping elements that fail to decode.
/// Community add-ons often return slightly malformed items; one bad entry
/// should not hide the rest of a catalog or stream list.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            // Decoding the wrapper never throws, so the container always
            // advances past the element, even when the element is malformed.
            if let value = try container.decode(Failable.self).value {
                result.append(value)
            }
        }
        elements = result
    }

    private struct Failable: Decodable {
        let value: Element?
        init(from decoder: Decoder) throws {
            value = try? Element(from: decoder)
        }
    }
}

extension KeyedDecodingContainer {
    func lossyArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T]? {
        guard contains(key) else { return nil }
        return (try? decode(LossyArray<T>.self, forKey: key))?.elements
    }

    /// Accepts either a JSON number or a numeric string.
    func flexibleInt(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key) { return Int(value) }
        if let value = try? decode(String.self, forKey: key) { return Int(value) }
        return nil
    }

    /// Accepts either a JSON string or a number rendered as a string.
    func flexibleString(forKey key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key) {
            return value.rounded() == value ? String(Int(value)) : String(value)
        }
        return nil
    }
}
