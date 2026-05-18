//
//  MsgPackEncoder.swift
//  SuperHyper
//
//  Created by Ian.Wang on 2026/5/18.
//  Copyright © 2026 Ian.Wang. All rights reserved.
//

import Foundation

/// A lightweight MessagePack encoder used for action hashing in Hyperliquid signing.
///
/// Hyperliquid uses MessagePack (MsgPack) as the serialization format when computing
/// action hashes for L1 transactions. The hash must be deterministic — the same action
/// must always produce the same bytes — so this encoder provides two map encoding modes:
///
/// - **`encode(_:)`**: Encodes dictionaries with keys sorted alphabetically.
///   Suitable for most actions where key order does not matter.
/// - **`encodeOrderedMap(_:)`**: Encodes key-value pairs in the exact order provided.
///   Critical for actions like `placeOrder` where Hyperliquid expects a specific key order
///   in the MsgPack output to produce a matching hash.
///
/// Supported types: `NSNull`, `Bool`, `Int`, `UInt`, `Double`, `String`, `Data`,
/// `[String: Any]` (maps), `[Any]` (arrays), and `OrderedAction`.
///
/// Encoding follows the MessagePack specification (https://msgpack.org):
/// - Positive fixint: 0x00–0x7f
/// - Negative fixint: 0xe0–0xff
/// - uint8/16/32/64: 0xcc/0xcd/0xce/0xcf
/// - int8/16/32/64: 0xd0/0xd1/0xd2/0xd3
/// - float64: 0xcb
/// - fixstr/str8/str16/str32: 0xa0–0xbf/0xd9/0xda/0xdb
/// - bin8/bin16/bin32: 0xc4/0xc5/0xc6
/// - fixmap/map16/map32: 0x80–0x8f/0xde/0xdf
/// - fixarray/array16/array32: 0x90–0x9f/0xdc/0xdd
struct MsgPackEncoder {
    /// Encodes a value to MessagePack binary format.
    ///
    /// Dictionary keys are sorted alphabetically for deterministic output.
    /// - Parameter value: The value to encode (supports dictionaries, arrays, primitives, etc.).
    /// - Returns: The MessagePack-encoded data.
    func encode(_ value: Any) -> Data {
        var data = Data()
        appendValue(value, to: &data)
        return data
    }

    /// Encodes an ordered list of key-value pairs to MessagePack map format.
    ///
    /// Keys are encoded in the exact order provided, which is critical for
    /// deterministic action hashing where the Hyperliquid exchange expects
    /// a specific key order.
    /// - Parameter pairs: Array of (key, value) tuples in the desired encoding order.
    /// - Returns: The MessagePack-encoded data.
    func encodeOrderedMap(_ pairs: [(String, Any)]) -> Data {
        var data = Data()
        appendOrderedMap(pairs, to: &data)
        return data
    }

    /// Dispatches encoding based on the value's runtime type.
    private func appendValue(_ value: Any, to data: inout Data) {
        switch value {
        case is NSNull:
            data.append(0xc0)
        case let bool as Bool:
            data.append(bool ? 0xc3 : 0xc2)
        case let int as Int:
            appendInt(int, to: &data)
        case let uint as UInt:
            appendUInt(uint, to: &data)
        case let double as Double:
            appendDouble(double, to: &data)
        case let string as String:
            appendString(string, to: &data)
        case let dict as [String: Any]:
            appendMap(dict, to: &data)
        case let ordered as OrderedAction:
            appendOrderedMap(ordered.orderedPairs, to: &data)
        case let array as [Any]:
            appendArray(array, to: &data)
        case let dataVal as Data:
            appendBinary(dataVal, to: &data)
        case let nsNumber as NSNumber:
            // NSNumber can be a bool or a number; disambiguate first
            if nsNumber === kCFBooleanTrue as AnyObject {
                data.append(0xc3)
            } else if nsNumber === kCFBooleanFalse as AnyObject {
                data.append(0xc2)
            } else if CFNumberGetType(nsNumber) == .doubleType || CFNumberGetType(nsNumber) == .floatType {
                appendDouble(nsNumber.doubleValue, to: &data)
            } else {
                appendInt(nsNumber.intValue, to: &data)
            }
        default:
            // Unknown type: encode as nil
            data.append(0xc0)
        }
    }

    /// Encodes a signed integer using the smallest MsgPack representation.
    ///
    /// Positive values use fixint (0x00–0x7f) or uint8/16/32/64 formats.
    /// Negative values use negative fixint (−32 to −1) or int8/16/32/64 formats.
    private func appendInt(_ value: Int, to data: inout Data) {
        if value >= 0 {
            if value < 128 {
                data.append(UInt8(value))
            } else if value <= UInt8.max {
                data.append(0xcc)
                data.append(UInt8(value))
            } else if value <= UInt16.max {
                data.append(0xcd)
                data.append(contentsOf: withUnsafeBytes(of: UInt16(value).bigEndian) { Data($0) })
            } else if value <= UInt32.max {
                data.append(0xce)
                data.append(contentsOf: withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) })
            } else {
                data.append(0xcf)
                data.append(contentsOf: withUnsafeBytes(of: UInt64(value).bigEndian) { Data($0) })
            }
        } else {
            if value >= -32 {
                data.append(UInt8(Int8(value)))
            } else if value >= Int8.min {
                data.append(0xd0)
                data.append(UInt8(Int8(truncatingIfNeeded: value)))
            } else if value >= Int16.min {
                data.append(0xd1)
                data.append(contentsOf: withUnsafeBytes(of: Int16(value).bigEndian) { Data($0) })
            } else if value >= Int32.min {
                data.append(0xd2)
                data.append(contentsOf: withUnsafeBytes(of: Int32(value).bigEndian) { Data($0) })
            } else {
                data.append(0xd3)
                data.append(contentsOf: withUnsafeBytes(of: Int64(value).bigEndian) { Data($0) })
            }
        }
    }

    /// Encodes an unsigned integer using the smallest MsgPack representation.
    private func appendUInt(_ value: UInt, to data: inout Data) {
        if value <= UInt8.max {
            if value < 128 {
                data.append(UInt8(value))
            } else {
                data.append(0xcc)
                data.append(UInt8(value))
            }
        } else if value <= UInt16.max {
            data.append(0xcd)
            data.append(contentsOf: withUnsafeBytes(of: UInt16(value).bigEndian) { Data($0) })
        } else if value <= UInt32.max {
            data.append(0xce)
            data.append(contentsOf: withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) })
        } else {
            data.append(0xcf)
            data.append(contentsOf: withUnsafeBytes(of: UInt64(value).bigEndian) { Data($0) })
        }
    }

    /// Encodes a 64-bit float in MsgPack format (0xcb prefix + 8 bytes big-endian IEEE 754).
    private func appendDouble(_ value: Double, to data: inout Data) {
        data.append(0xcb)
        data.append(contentsOf: withUnsafeBytes(of: value.bitPattern.bigEndian) { Data($0) })
    }

    /// Encodes a UTF-8 string with the appropriate length prefix.
    ///
    /// fixstr (0xa0–0xbf) for lengths 0–31, str8/str16/str32 for longer strings.
    private func appendString(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        let len = bytes.count
        if len < 32 {
            data.append(UInt8(0xa0 | len))
        } else if len <= UInt8.max {
            data.append(0xd9)
            data.append(UInt8(len))
        } else if len <= UInt16.max {
            data.append(0xda)
            data.append(contentsOf: withUnsafeBytes(of: UInt16(len).bigEndian) { Data($0) })
        } else {
            data.append(0xdb)
            data.append(contentsOf: withUnsafeBytes(of: UInt32(len).bigEndian) { Data($0) })
        }
        data.append(bytes)
    }

    /// Encodes binary data with the appropriate length prefix (bin8/bin16/bin32).
    private func appendBinary(_ value: Data, to data: inout Data) {
        let len = value.count
        if len <= UInt8.max {
            data.append(0xc4)
            data.append(UInt8(len))
        } else if len <= UInt16.max {
            data.append(0xc5)
            data.append(contentsOf: withUnsafeBytes(of: UInt16(len).bigEndian) { Data($0) })
        } else {
            data.append(0xc6)
            data.append(contentsOf: withUnsafeBytes(of: UInt32(len).bigEndian) { Data($0) })
        }
        data.append(value)
    }

    /// Encodes a dictionary as a MsgPack map with keys sorted alphabetically.
    ///
    /// Sorting ensures deterministic output regardless of dictionary insertion order,
    /// which is essential for producing consistent hashes.
    private func appendMap(_ value: [String: Any], to data: inout Data) {
        let len = value.count
        if len < 16 {
            data.append(UInt8(0x80 | len))
        } else if len <= UInt16.max {
            data.append(0xde)
            data.append(contentsOf: withUnsafeBytes(of: UInt16(len).bigEndian) { Data($0) })
        } else {
            data.append(0xdf)
            data.append(contentsOf: withUnsafeBytes(of: UInt32(len).bigEndian) { Data($0) })
        }
        let sortedKeys = value.keys.sorted()
        for key in sortedKeys {
            appendString(key, to: &data)
            appendValue(value[key]!, to: &data)
        }
    }

    /// Encodes key-value pairs as a MsgPack map preserving the given key order.
    ///
    /// This is the critical encoding path for `OrderedAction` — the Hyperliquid
    /// exchange requires keys in a specific order for action hashing, and this
    /// method guarantees that order is preserved in the serialized output.
    private func appendOrderedMap(_ pairs: [(String, Any)], to data: inout Data) {
        let len = pairs.count
        if len < 16 {
            data.append(UInt8(0x80 | len))
        } else if len <= UInt16.max {
            data.append(0xde)
            data.append(contentsOf: withUnsafeBytes(of: UInt16(len).bigEndian) { Data($0) })
        } else {
            data.append(0xdf)
            data.append(contentsOf: withUnsafeBytes(of: UInt32(len).bigEndian) { Data($0) })
        }
        for (key, val) in pairs {
            appendString(key, to: &data)
            appendValue(val, to: &data)
        }
    }

    /// Encodes an array with the appropriate length prefix (fixarray/array16/array32).
    private func appendArray(_ value: [Any], to data: inout Data) {
        let len = value.count
        if len < 16 {
            data.append(UInt8(0x90 | len))
        } else if len <= UInt16.max {
            data.append(0xdc)
            data.append(contentsOf: withUnsafeBytes(of: UInt16(len).bigEndian) { Data($0) })
        } else {
            data.append(0xdd)
            data.append(contentsOf: withUnsafeBytes(of: UInt32(len).bigEndian) { Data($0) })
        }
        for item in value {
            appendValue(item, to: &data)
        }
    }
}
