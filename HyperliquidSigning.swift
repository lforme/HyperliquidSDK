//
//  HyperliquidSigning.swift
//  SuperHyper
//
//  Created by Ian.Wang on 2026/5/18.
//  Copyright © 2026 Ian.Wang. All rights reserved.
//

import Foundation
import CryptoSwift

/// Handles EIP-712 cryptographic signing for Hyperliquid L1 actions and user-signed actions.
///
/// This class implements the full signing pipeline required by the Hyperliquid exchange:
/// 1. **L1 Actions** (trading operations) use the "phantom agent" pattern — the action is
///    MsgPack-encoded and hashed, then wrapped in a phantom agent struct and signed via EIP-712.
/// 2. **User-Signed Actions** (e.g. approve, reject) are signed directly with EIP-712 typed data.
///
/// The signing process relies on secp256k1 ECDSA and Keccak-256 hashing, compatible with
/// Ethereum wallets and the Hyperliquid on-chain verifier.
public class HyperliquidSigning {
    /// The raw 32-byte secp256k1 private key.
    private let privateKey: Data
    /// Whether to use mainnet or testnet endpoints and domain parameters.
    private let isMainnet: Bool
    /// Optional vault address for vault-specific operations.
    private(set) var vaultAddress: String?
    /// The Ethereum address derived from the private key (hex string with "0x" prefix).
    private(set) var address: String

    /// Creates a signing instance from a hex-encoded private key.
    ///
    /// - Parameters:
    ///   - privateKey: Hex-encoded private key (with or without "0x" prefix).
    ///   - isMainnet: Whether to use mainnet domain parameters (default: `true`).
    ///   - vaultAddress: Optional vault address for vault-scoped operations.
    /// - Throws: `HLError.invalidPrivateKey` if the key is not exactly 32 bytes.
    public init(privateKey: String, isMainnet: Bool = true, vaultAddress: String? = nil) throws {
        let cleanKey = privateKey.hasPrefix("0x") ? String(privateKey.dropFirst(2)) : privateKey
        let keyData = Data(hex: cleanKey)
        guard keyData.count == 32 else {
            throw HLError.invalidPrivateKey
        }
        self.privateKey = keyData
        self.isMainnet = isMainnet
        self.vaultAddress = vaultAddress
        self.address = try Self.deriveAddress(from: keyData)
    }

    /// Derives an Ethereum address from a secp256k1 private key.
    ///
    /// The derivation follows the standard Ethereum path: private key → public key → Keccak-256 → last 20 bytes.
    /// - Parameter privateKey: The 32-byte private key.
    /// - Returns: The Ethereum address as a hex string with "0x" prefix.
    /// - Throws: `HLError.invalidPrivateKey` if the public key cannot be derived.
    static func deriveAddress(from privateKey: Data) throws -> String {
        guard let publicKey = SECP256K1.privateKeyToPublicKey(privateKey) else {
            throw HLError.invalidPrivateKey
        }
        let uncompressed = SECP256K1.uncompressPublicKey(publicKey)
        let hash = Data(SHA3(variant: .keccak256).calculate(for: uncompressed.dropFirst(1).bytes))
        return "0x" + hash[12..<32].toHexString()
    }

    /// Signs an L1 action using the phantom agent EIP-712 pattern.
    ///
    /// This is the primary signing flow for exchange operations (place order, cancel, etc.):
    /// 1. The action is MsgPack-encoded and combined with nonce, vault address, and expiry
    ///    to produce an `actionHash`.
    /// 2. The hash is embedded into a "phantom agent" struct (`source` + `connectionId`).
    /// 3. The phantom agent is signed via EIP-712 with the Hyperliquid Exchange domain.
    ///
    /// - Parameters:
    ///   - action: The action to sign. Can be a `[String: Any]` dictionary or an `OrderedAction`
    ///     for deterministic key ordering (required for actions where key order affects the hash).
    ///   - nonce: Unique nonce for this action (typically from the exchange).
    ///   - expiresAfter: Optional timestamp after which the action expires (milliseconds).
    /// - Returns: A dictionary with "r", "s" (hex strings) and "v" (Int) signature components.
    /// - Throws: `HLError.signingError` if the action type is invalid or signing fails.
    func signL1Action(action: Any, nonce: Int, expiresAfter: Int? = nil) throws -> [String: Any] {
        let vaultAddr: String? = vaultAddress
        let hash: Data
        if let ordered = action as? OrderedAction {
            hash = actionHash(orderedPairs: ordered.orderedPairs, vaultAddress: vaultAddr, nonce: nonce, expiresAfter: expiresAfter)
        } else if let dict = action as? [String: Any] {
            hash = actionHash(action: dict, vaultAddress: vaultAddr, nonce: nonce, expiresAfter: expiresAfter)
        } else {
            throw HLError.signingError("Invalid action type")
        }
        print("[HLSigning] actionHash: 0x\(hash.toHexString())")
        // Phantom agent: the Hyperliquid L1 signing pattern wraps the action hash
        // in a virtual "Agent" struct that is signed via EIP-712.
        let phantomAgent: [String: Any] = [
            "source": isMainnet ? "a" : "b",
            "connectionId": "0x" + hash.toHexString()
        ]
        let payload = l1Payload(phantomAgent: phantomAgent)
        let signature = try signEIP712(payload: payload)
        print("[HLSigning] signature: r=\(signature["r"] ?? ""), s=\(signature["s"] ?? ""), v=\(signature["v"] ?? "")")
        return signature
    }

    /// Signs a user-signed action using EIP-712 typed data.
    ///
    /// User-signed actions (e.g. approve, reject) are signed directly with the
    /// "HyperliquidSignTransaction" EIP-712 domain, without the phantom agent wrapper.
    /// The action is enriched with `signatureChainId` and `hyperliquidChain` before signing.
    ///
    /// - Parameters:
    ///   - action: The action dictionary to sign.
    ///   - primaryType: The EIP-712 primary type name (e.g. "ApproveAgent").
    ///   - types: Field definitions for the EIP-712 type, as `[name, type]` pairs.
    /// - Returns: A dictionary with "r", "s" (hex strings) and "v" (Int) signature components.
    /// - Throws: `HLError.signingError` if signing fails.
    func signUserSignedAction(
        action: [String: Any],
        primaryType: String,
        types: [[String: String]]
    ) throws -> [String: Any] {
        var enrichedAction = action
        enrichedAction["signatureChainId"] = "0x66eee"
        enrichedAction["hyperliquidChain"] = isMainnet ? "Mainnet" : "Testnet"
        let payload = userSignedPayload(primaryType: primaryType, types: types, action: enrichedAction)
        let signature = try signEIP712(payload: payload)
        return signature
    }

    /// Computes the action hash for an L1 action.
    ///
    /// The hash is computed as: `keccak256(msgpack(action) || nonce || vaultFlag || [vaultAddr] || [expiresAfter])`.
    /// This hash is embedded in the phantom agent and ultimately signed via EIP-712.
    ///
    /// - Parameters:
    ///   - action: Action dictionary. If it contains an `OrderedAction` value, its key order is preserved.
    ///   - vaultAddress: Optional vault address (appended as a flag + 20 bytes if present).
    ///   - nonce: Action nonce (8 bytes big-endian).
    ///   - expiresAfter: Optional expiry timestamp (flag byte + 8 bytes big-endian).
    /// - Returns: The 32-byte Keccak-256 action hash.
    func actionHash(action: [String: Any], vaultAddress: String?, nonce: Int, expiresAfter: Int?) -> Data {
        let encoder = MsgPackEncoder()
        let data: Data
        if let orderedAction = action as? OrderedAction {
            data = encoder.encodeOrderedMap(orderedAction.orderedPairs)
        } else {
            data = encoder.encode(action)
        }
        var result = data
        result += withUnsafeBytes(of: UInt64(nonce).bigEndian) { Data($0) }
        if let vault = vaultAddress {
            result.append(0x01)
            result.append(addressToBytes(vault))
        } else {
            result.append(0x00)
        }
        if let expires = expiresAfter {
            result.append(0x00)
            result += withUnsafeBytes(of: UInt64(expires).bigEndian) { Data($0) }
        }
        return Data(SHA3(variant: .keccak256).calculate(for: result.bytes))
    }

    /// Computes the action hash from an explicitly ordered list of key-value pairs.
    ///
    /// This overload is used when the action is already an `OrderedAction`, ensuring
    /// the MsgPack encoding preserves the exact key order for deterministic hashing.
    func actionHash(orderedPairs: [(String, Any)], vaultAddress: String?, nonce: Int, expiresAfter: Int?) -> Data {
        let encoder = MsgPackEncoder()
        var result = encoder.encodeOrderedMap(orderedPairs)
        result += withUnsafeBytes(of: UInt64(nonce).bigEndian) { Data($0) }
        if let vault = vaultAddress {
            result.append(0x01)
            result.append(addressToBytes(vault))
        } else {
            result.append(0x00)
        }
        if let expires = expiresAfter {
            result.append(0x00)
            result += withUnsafeBytes(of: UInt64(expires).bigEndian) { Data($0) }
        }
        return Data(SHA3(variant: .keccak256).calculate(for: result.bytes))
    }

    /// Builds the EIP-712 payload for L1 action signing using the phantom agent pattern.
    ///
    /// Uses the "Exchange" domain with chain ID 1337 (Hyperliquid's L1 chain ID)
    /// and the "Agent" primary type containing `source` and `connectionId`.
    private func l1Payload(phantomAgent: [String: Any]) -> EIP712Payload {
        return EIP712Payload(
            domain: EIP712Domain(
                name: "Exchange",
                version: "1",
                chainId: 1337,
                verifyingContract: "0x0000000000000000000000000000000000000000"
            ),
            primaryType: "Agent",
            types: [
                "Agent": [
                    EIP712Field(name: "source", type: "string"),
                    EIP712Field(name: "connectionId", type: "bytes32")
                ]
            ],
            message: phantomAgent
        )
    }

    /// Builds the EIP-712 payload for user-signed actions.
    ///
    /// Uses the "HyperliquidSignTransaction" domain with the Hyperliquid chain ID (0x66eee = 421614).
    private func userSignedPayload(primaryType: String, types: [[String: String]], action: [String: Any]) -> EIP712Payload {
        let chainIdStr = action["signatureChainId"] as? String ?? "0x66eee"
        let hexPart = chainIdStr.hasPrefix("0x") ? String(chainIdStr.dropFirst(2)) : chainIdStr
        let chainId = Int(hexPart, radix: 16) ?? 421614
        let fields = types.map { EIP712Field(name: $0["name"] ?? "", type: $0["type"] ?? "") }
        return EIP712Payload(
            domain: EIP712Domain(
                name: "HyperliquidSignTransaction",
                version: "1",
                chainId: chainId,
                verifyingContract: "0x0000000000000000000000000000000000000000"
            ),
            primaryType: primaryType,
            types: [primaryType: fields],
            message: action
        )
    }

    /// Performs EIP-712 typed data signing.
    ///
    /// Follows the EIP-712 specification: `keccak256(0x19 || 0x01 || domainSeparator || messageHash)`.
    /// The resulting hash is signed with secp256k1 ECDSA and returned as (r, s, v).
    private func signEIP712(payload: EIP712Payload) throws -> [String: Any] {
        let domainSeparator = hashStruct(
            type: "EIP712Domain",
            types: payload.allTypes,
            data: payload.domainDict
        )
        print("[HLSigning] domainSeparator: 0x\(domainSeparator.toHexString())")
        let messageHash = hashStruct(
            type: payload.primaryType,
            types: payload.allTypes,
            data: payload.message
        )
        print("[HLSigning] messageHash: 0x\(messageHash.toHexString())")

        // EIP-712: typedDataHash = 0x19 0x01 || domainSeparator || messageHash
        var typedDataHash = Data([0x19, 0x01])
        typedDataHash.append(domainSeparator)
        typedDataHash.append(messageHash)
        let hash = Data(SHA3(variant: .keccak256).calculate(for: typedDataHash.bytes))
        print("[HLSigning] typedDataHash: 0x\(hash.toHexString())")

        guard let sig = SECP256K1.sign(hash: hash, privateKey: privateKey) else {
            throw HLError.signingError("ECDSA signing failed")
        }

        let v = sig.recoveryId + 27
        return [
            "r": "0x" + sig.r.toHexString(),
            "s": "0x" + sig.s.toHexString(),
            "v": v
        ]
    }

    /// Recursively hashes a struct according to EIP-712 `hashStruct` rules:
    /// `keccak256(typeHash || encodeField1 || encodeField2 || ...)`.
    private func hashStruct(type: String, types: [String: [EIP712Field]], data: [String: Any]) -> Data {
        let typeHash = keccak256(Data(typeString(type: type, fields: types[type] ?? []).utf8))
        var encoded = typeHash
        if let fields = types[type] {
            for field in fields {
                encoded.append(encodeField(field: field, value: data[field.name], types: types))
            }
        }
        return Data(SHA3(variant: .keccak256).calculate(for: encoded.bytes))
    }

    /// Encodes a single EIP-712 field value into a 32-byte Data.
    ///
    /// Handles all standard EIP-712 types: `string` (hashed), `bytes32` (padded),
    /// `address` (left-padded to 32 bytes), `uint256`/`uint64`/`uint` (big-endian),
    /// `bool`, and nested struct types (recursively hashed).
    private func encodeField(field: EIP712Field, value: Any?, types: [String: [EIP712Field]]) -> Data {
        guard let value = value else { return Data(repeating: 0, count: 32) }

        switch field.type {
        case "string":
            if let str = value as? String {
                return Data(SHA3(variant: .keccak256).calculate(for: Data(str.utf8).bytes))
            }
        case "bytes32":
            if let str = value as? String {
                let hex = str.hasPrefix("0x") ? String(str.dropFirst(2)) : str
                let data = Data(hex: hex)
                return padTo32(data)
            }
            if let data = value as? Data {
                return padTo32(data)
            }
        case "address":
            if let str = value as? String {
                let hex = str.hasPrefix("0x") ? String(str.dropFirst(2)) : str
                let addrData = Data(hex: hex)
                var padded = Data(repeating: 0, count: 12)
                padded.append(addrData)
                return padded
            }
        case "uint256", "uint64", "uint":
            if let intVal = value as? Int {
                return bigEndianPad32(intVal)
            }
            if let str = value as? String, let intVal = Int(str) {
                return bigEndianPad32(intVal)
            }
        case "bool":
            if let boolVal = value as? Bool {
                return bigEndianPad32(boolVal ? 1 : 0)
            }
        default:
            // Nested struct type: recursively hash
            if let nestedFields = types[field.type] {
                if let nestedData = value as? [String: Any] {
                    return hashStruct(type: field.type, types: types, data: nestedData)
                }
            }
        }
        return Data(repeating: 0, count: 32)
    }

    /// Pads Data to exactly 32 bytes (left-padded with zeros, or right-truncated if longer).
    private func padTo32(_ data: Data) -> Data {
        if data.count >= 32 { return data[data.count - 32..<data.count] }
        var result = Data(repeating: 0, count: 32 - data.count)
        result.append(data)
        return result
    }

    /// Constructs the EIP-712 type string, e.g. "Agent(string source,bytes32 connectionId)".
    private func typeString(type: String, fields: [EIP712Field]) -> String {
        let fieldStrings = fields.map { "\($0.type) \($0.name)" }
        return "\(type)(\(fieldStrings.joined(separator: ",")))"
    }

    /// Encodes an integer value as a 32-byte big-endian Data.
    private func bigEndianPad32(_ value: Int) -> Data {
        var result = Data(repeating: 0, count: 32)
        var v = UInt64(abs(value))
        for i in (0..<8).reversed() {
            result[24 + i] = UInt8(v & 0xFF)
            v >>= 8
        }
        return result
    }

    /// Computes Keccak-256 hash of the given data.
    private func keccak256(_ data: Data) -> Data {
        return Data(SHA3(variant: .keccak256).calculate(for: data.bytes))
    }

    /// Converts an Ethereum address string (with or without "0x" prefix) to raw bytes.
    private func addressToBytes(_ address: String) -> Data {
        let hex = address.hasPrefix("0x") ? String(address.dropFirst(2)) : address
        return Data(hex: hex)
    }

    /// Converts a floating-point value to the wire format used by Hyperliquid.
    ///
    /// Rounds to 8 decimal places, normalizes negative zero to "0", and strips
    /// trailing zeros and unnecessary decimal points for compact representation.
    /// - Parameter x: The floating-point value to convert.
    /// - Returns: A normalized decimal string, e.g. "1.5", "0.00001", "100".
    static func floatToWire(_ x: Double) -> String {
        let rounded = String(format: "%.8f", x)
        guard let value = Double(rounded) else { return "0" }
        if value == 0 && x < 0 { return "0" }
        return normalizeDecimal(value)
    }

    /// Removes trailing zeros and unnecessary decimal points from a number string.
    private static func normalizeDecimal(_ value: Double) -> String {
        let str = String(value)
        if !str.contains(".") { return str }
        var trimmed = str
        while trimmed.hasSuffix("0") && trimmed.suffix(2) != ".0" {
            trimmed = String(trimmed.dropLast())
        }
        if trimmed.hasSuffix(".0") {
            trimmed = String(trimmed.dropLast(2))
        }
        return trimmed.isEmpty ? "0" : trimmed
    }

    /// Converts a USD value to an integer with 6 decimal places of precision.
    ///
    /// Hyperliquid represents USD values as integers scaled by 1,000,000 (e.g. $1.50 → 1500000).
    /// - Parameter x: The USD value as a Double.
    /// - Returns: The value scaled to 6-decimal-place integer precision.
    static func floatToUsdInt(_ x: Double) -> Int {
        return Int(round(x * 1_000_000))
    }

    /// Returns the current timestamp in milliseconds since epoch.
    static func getTimestampMs() -> Int {
        return Int(Date().timeIntervalSince1970 * 1000)
    }
}

/// An action wrapper that preserves explicit key ordering for deterministic MsgPack encoding.
///
/// Hyperliquid's action hashing requires keys to be in a specific order. Swift dictionaries
/// do not guarantee insertion order, so `OrderedAction` stores key-value pairs as an
/// ordered array. This is critical for actions like `placeOrder` where the hash must
/// match exactly what the exchange expects.
public class OrderedAction {
    /// The key-value pairs in the exact order they should be encoded.
    public let orderedPairs: [(String, Any)]

    /// Creates an ordered action from an explicit list of key-value pairs.
    /// - Parameter pairs: Array of (key, value) tuples in the desired encoding order.
    public init(_ pairs: [(String, Any)]) {
        self.orderedPairs = pairs
    }

    /// Creates an ordered action from a dictionary and an explicit key ordering.
    ///
    /// Only keys present in both the dictionary and `orderedKeys` are included,
    /// in the order specified by `orderedKeys`.
    /// - Parameters:
    ///   - dictionary: The source dictionary with action data.
    ///   - orderedKeys: The keys in the desired encoding order.
    public init(dictionary: [String: Any], orderedKeys: [String]) {
        self.orderedPairs = orderedKeys.compactMap { key in
            if let value = dictionary[key] {
                return (key, value)
            }
            return nil
        }
    }
}

/// Internal representation of an EIP-712 typed data payload.
private struct EIP712Payload {
    let domain: EIP712Domain
    let primaryType: String
    let types: [String: [EIP712Field]]
    let message: [String: Any]

    /// All type definitions including the standard EIP712Domain type.
    var allTypes: [String: [EIP712Field]] {
        var result = types
        result["EIP712Domain"] = [
            EIP712Field(name: "name", type: "string"),
            EIP712Field(name: "version", type: "string"),
            EIP712Field(name: "chainId", type: "uint256"),
            EIP712Field(name: "verifyingContract", type: "address")
        ]
        return result
    }

    /// The domain as a dictionary suitable for EIP-712 encoding.
    var domainDict: [String: Any] {
        return [
            "name": domain.name,
            "version": domain.version,
            "chainId": domain.chainId,
            "verifyingContract": domain.verifyingContract
        ]
    }
}

/// EIP-712 domain parameters.
private struct EIP712Domain {
    let name: String
    let version: String
    let chainId: Int
    let verifyingContract: String
}

/// A single field in an EIP-712 type definition.
private struct EIP712Field {
    let name: String
    let type: String
}

/// Low-level secp256k1 ECDSA operations using the system libsecp256k1 library.
///
/// Provides key derivation, signing, and public key serialization needed for
/// Ethereum-compatible cryptographic operations within the Hyperliquid signing flow.
private struct SECP256K1 {
    /// An ECDSA signature with recovery ID for public key recovery.
    struct Signature {
        let r: Data
        let s: Data
        let recoveryId: Int
    }

    /// Signs a 32-byte message hash with the given private key.
    ///
    /// - Parameters:
    ///   - hash: The 32-byte message hash to sign.
    ///   - privateKey: The 32-byte secp256k1 private key.
    /// - Returns: A `Signature` with r, s components and recovery ID, or `nil` if signing fails.
    static func sign(hash: Data, privateKey: Data) -> Signature? {
        guard hash.count == 32, privateKey.count == 32 else { return nil }

        guard let sigCtx = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN)) else { return nil }
        defer { secp256k1_context_destroy(sigCtx) }

        var signature = secp256k1_ecdsa_signature()
        guard secp256k1_ecdsa_sign(sigCtx, &signature, hash.bytes, privateKey.bytes, nil, nil) == 1 else {
            return nil
        }

        var serializedSig = [UInt8](repeating: 0, count: 64)
        secp256k1_ecdsa_signature_serialize_compact(sigCtx, &serializedSig, &signature)

        var recoverableSig = secp256k1_ecdsa_recoverable_signature()
        guard secp256k1_ecdsa_sign_recoverable(sigCtx, &recoverableSig, hash.bytes, privateKey.bytes, nil, nil) == 1 else {
            return nil
        }

        var recoveryId: Int32 = 0
        var recoverableSerialized = [UInt8](repeating: 0, count: 65)
        secp256k1_ecdsa_recoverable_signature_serialize_compact(sigCtx, &recoverableSerialized, &recoveryId, &recoverableSig)

        return Signature(
            r: Data(serializedSig[0..<32]),
            s: Data(serializedSig[32..<64]),
            recoveryId: Int(recoveryId)
        )
    }

    /// Derives the uncompressed public key (65 bytes, 0x04 prefix) from a private key.
    ///
    /// - Parameter privateKey: The 32-byte secp256k1 private key.
    /// - Returns: The 65-byte uncompressed public key, or `nil` if derivation fails.
    static func privateKeyToPublicKey(_ privateKey: Data) -> Data? {
        guard privateKey.count == 32 else { return nil }

        guard let sigCtx = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN)) else { return nil }
        defer { secp256k1_context_destroy(sigCtx) }

        var publicKey = secp256k1_pubkey()
        guard secp256k1_ec_pubkey_create(sigCtx, &publicKey, privateKey.bytes) == 1 else {
            return nil
        }

        var serialized = [UInt8](repeating: 0, count: 65)
        var outputLen: size_t = 65
        secp256k1_ec_pubkey_serialize(sigCtx, &serialized, &outputLen, &publicKey, UInt32(SECP256K1_EC_UNCOMPRESSED))

        return Data(serialized)
    }

    /// Returns the public key data as-is (already uncompressed in this implementation).
    static func uncompressPublicKey(_ compressed: Data) -> Data {
        return compressed
    }
}
