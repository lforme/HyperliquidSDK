//
//  HyperliquidLocalStorage.swift
//  SuperHyper
//
//  Created by Ian.Wang on 2026/5/18.
//  Copyright © 2026 Ian.Wang. All rights reserved.
//

import Foundation
import MMKV

/// A key-value persistence layer backed by encrypted MMKV for the Hyperliquid SDK.
///
/// Uses the singleton pattern to provide a single shared storage instance.
/// Data is persisted using MMKV, a high-performance key-value storage engine
/// that uses mmap for efficient I/O. The storage is isolated under the
/// "HyperliquidSDK" mmap ID with AES encryption to avoid conflicts with
/// other MMKV instances and protect sensitive data.
///
/// MMKV is initialized lazily on first access. Callers do not need to
/// call `MMKV.initialize()` beforehand — it is handled internally.
public class HyperliquidLocalStorage {

    /// Shared singleton instance.
    public static let shared = HyperliquidLocalStorage()

    /// The underlying MMKV instance scoped to "HyperliquidSDK" with encryption.
    private let sdkKV: MMKV?

    private static let cryptKey = "HLSDK2026CRYPTKEY"

    private init() {
        MMKV.initialize(rootDir: nil)
        let keyData = Data(HyperliquidLocalStorage.cryptKey.utf8)
        self.sdkKV = MMKV(mmapID: "HyperliquidSDK", cryptKey: keyData)
    }

    // MARK: - Bool

    /// Stores a boolean value for the given key.
    public func setBool(_ value: Bool, forKey key: String) {
        sdkKV?.set(value, forKey: key)
    }

    /// Returns the boolean value for the given key, or the default if not found.
    public func bool(forKey key: String, defaultValue: Bool = false) -> Bool {
        sdkKV?.bool(forKey: key) ?? defaultValue
    }

    // MARK: - Int32

    /// Stores a 32-bit integer value for the given key.
    public func setInt32(_ value: Int32, forKey key: String) {
        sdkKV?.set(value, forKey: key)
    }

    /// Returns the 32-bit integer value for the given key, or the default if not found.
    public func int32(forKey key: String, defaultValue: Int32 = 0) -> Int32 {
        sdkKV?.int32(forKey: key) ?? defaultValue
    }

    // MARK: - Double

    /// Stores a double value for the given key.
    public func setDouble(_ value: Double, forKey key: String) {
        sdkKV?.set(value, forKey: key)
    }

    /// Returns the double value for the given key, or the default if not found.
    public func double(forKey key: String, defaultValue: Double = 0) -> Double {
        sdkKV?.double(forKey: key) ?? defaultValue
    }

    // MARK: - String

    /// Stores a string value for the given key.
    public func setString(_ value: String, forKey key: String) {
        sdkKV?.set(value, forKey: key)
    }

    /// Returns the string value for the given key, or nil if not found.
    public func string(forKey key: String) -> String? {
        sdkKV?.string(forKey: key)
    }

    // MARK: - Data

    /// Stores raw data for the given key.
    public func setData(_ value: Data, forKey key: String) {
        sdkKV?.set(value, forKey: key)
    }

    /// Returns the data stored for the given key, or nil if not found.
    public func data(forKey key: String) -> Data? {
        sdkKV?.data(forKey: key)
    }

    // MARK: - Existence & Removal

    /// Returns whether a value exists for the given key.
    public func contains(key: String) -> Bool {
        sdkKV?.contains(key: key) ?? false
    }

    /// Removes the value for the given key.
    public func remove(forKey key: String) {
        sdkKV?.removeValue(forKey: key)
    }
}
