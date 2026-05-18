//
//  HyperliquidInfo.swift
//  SuperHyper
//
//  Created by Ian.Wang on 2026/5/18.
//  Copyright © 2026 Ian.Wang. All rights reserved.
//

import Foundation
import SmartCodable

/// Read-only query API for Hyperliquid market data and user information.
///
/// `HyperliquidInfo` inherits from `HyperliquidAPI` and provides methods for all
/// `/info` endpoint queries. Before using coin-to-asset mapping methods like
/// `nameToAsset` or `szDecimals`, you must call `loadMeta()` to populate the
/// internal asset lookup tables.
///
/// This class is used both directly and as an embedded helper inside
/// `HyperliquidExchange` for resolving coin names to asset indices during
/// order construction.
public class HyperliquidInfo: HyperliquidAPI {

    /// Maps coin names (e.g. "BTC") to their numeric asset indices.
    private var coinToAsset: [String: Int] = [:]

    /// Maps coin names to their canonical coin identifiers.
    private var nameToCoin: [String: String] = [:]

    /// Maps asset indices to their size decimal places (e.g. BTC → 5, ETH → 4).
    private var assetToSzDecimals: [Int: Int] = [:]

    /// Whether market metadata has been loaded via `loadMeta()`.
    private(set) var isMetaLoaded = false

    /// Creates an info instance with the given base URL and timeout.
    ///
    /// - Parameters:
    ///   - baseURL: The Hyperliquid API base URL.
    ///   - timeout: HTTP request timeout in seconds.
    public override init(baseURL: String = HLConstants.mainnetAPIURL, timeout: TimeInterval = 30) {
        super.init(baseURL: baseURL, timeout: timeout)
    }

    /// Loads market metadata (coin universe and size decimals) from the API.
    ///
    /// This populates the internal `coinToAsset`, `nameToCoin`, and `assetToSzDecimals`
    /// lookup tables. It must be called before using `nameToAsset()` or `szDecimals()`.
    /// The `HyperliquidClient` and `HyperliquidExchange` call this automatically during
    /// `connect()`.
    public func loadMeta() async throws {
        let result: [Any] = try await postRaw("/info", ["type": "metaAndAssetCtxs"]) as! [Any]
        guard let metaDict = result.first as? [String: Any],
              let universe = metaDict["universe"] as? [[String: Any]] else {
            print("[HLInfo] loadMeta: unexpected format")
            return
        }
        for (index, assetInfo) in universe.enumerated() {
            guard let name = assetInfo["name"] as? String else { continue }
            let szDecimals = assetInfo["szDecimals"] as? Int ?? 0
            coinToAsset[name] = index
            nameToCoin[name] = name
            assetToSzDecimals[index] = szDecimals
        }
        isMetaLoaded = true
        print("[HLInfo] loadMeta: \(coinToAsset.count) coins loaded")
    }

    /// Returns a dictionary mapping all coin names to their current mid prices.
    public func allMids() async throws -> [String: String] {
        let raw = try await postRaw("/info", ["type": "allMids"])
        guard let dict = raw as? [String: String] else {
            print("[HLInfo] allMids: unexpected format")
            return [:]
        }
        return dict
    }

    /// Returns coin metadata and per-asset context information.
    ///
    /// - Returns: A tuple containing an array of `HLCoinInfo` (name, szDecimals, etc.)
    ///   and an array of `HLAssetCtx` (mark price, funding, open interest, etc.).
    public func metaAndAssetCtxs() async throws -> (meta: [HLCoinInfo], ctxs: [HLAssetCtx]) {
        let raw: Any = try await postRaw("/info", ["type": "metaAndAssetCtxs"])
        guard let array = raw as? [Any], array.count >= 2 else {
            print("[HLInfo] metaAndAssetCtxs: unexpected format, type=\(type(of: raw))")
            throw HLError.decodingError(NSError(domain: "HLInfo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid metaAndAssetCtxs format"]))
        }

        let metaDict = array[0] as? [String: Any] ?? [:]
        let universe = metaDict["universe"] as? [[String: Any]] ?? []
        let ctxsArray = array[1] as? [[String: Any]] ?? []

        var metaList: [HLCoinInfo] = []
        for assetInfo in universe {
            let infoData = try JSONSerialization.data(withJSONObject: assetInfo)
            if let info = HLCoinInfo.deserialize(from: infoData) {
                metaList.append(info)
            }
        }

        var ctxsList: [HLAssetCtx] = []
        for ctxDict in ctxsArray {
            let ctxData = try JSONSerialization.data(withJSONObject: ctxDict)
            if let ctx = HLAssetCtx.deserialize(from: ctxData) {
                ctxsList.append(ctx)
            }
        }

        print("[HLInfo] Decoded \(metaList.count) coins, \(ctxsList.count) ctxs")
        return (meta: metaList, ctxs: ctxsList)
    }

    /// Retrieves the full perpetual clearinghouse state for a user.
    ///
    /// Includes positions, margin information, cross-chain details, and account values.
    ///
    /// - Parameter address: The user's Ethereum address.
    public func userState(address: String) async throws -> HLUserState {
        return try await post("/info", ["type": "clearinghouseState", "user": address])
    }

    /// Retrieves the spot clearinghouse state for a user.
    ///
    /// - Parameter address: The user's Ethereum address.
    public func spotState(address: String) async throws -> HLSpotState {
        return try await post("/info", ["type": "spotClearinghouseState", "user": address])
    }

    /// Retrieves all open orders for a user.
    ///
    /// - Parameter address: The user's Ethereum address.
    public func openOrders(address: String) async throws -> [HLOpenOrder] {
        return try await post("/info", ["type": "openOrders", "user": address])
    }

    /// Retrieves frontend open orders for a user (includes additional display metadata).
    ///
    /// - Parameter address: The user's Ethereum address.
    public func frontendOpenOrders(address: String) async throws -> [HLOpenOrder] {
        return try await post("/info", ["type": "frontendOpenOrders", "user": address])
    }

    /// Retrieves all fills (trade history) for a user.
    ///
    /// - Parameter address: The user's Ethereum address.
    public func userFills(address: String) async throws -> [HLUserFill] {
        return try await post("/info", ["type": "userFills", "user": address])
    }

    /// Retrieves fills for a user filtered by time range.
    ///
    /// - Parameters:
    ///   - address: The user's Ethereum address.
    ///   - startTime: Start of the time window (milliseconds since epoch).
    ///   - endTime: Optional end of the time window (milliseconds since epoch).
    public func userFillsByTime(address: String, startTime: Int, endTime: Int? = nil) async throws -> [HLUserFill] {
        var body: [String: Any] = [
            "type": "userFillsByTime",
            "user": address,
            "startTime": startTime
        ]
        if let endTime = endTime {
            body["endTime"] = endTime
        }
        return try await post("/info", body)
    }

    /// Retrieves the L2 order book snapshot for a coin.
    ///
    /// - Parameter coin: The coin symbol (e.g. "BTC").
    public func l2Snapshot(coin: String) async throws -> HLL2Snapshot {
        return try await post("/info", ["type": "l2Book", "coin": coin])
    }

    /// Retrieves candle (OHLCV) data for a coin within an optional time range.
    ///
    /// The response is manually parsed because candle fields may be returned as
    /// either strings or numbers depending on the API version.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol.
    ///   - interval: Candle interval (e.g. "1m", "5m", "1h", "1d").
    ///   - startTime: Optional start time (milliseconds since epoch).
    ///   - endTime: Optional end time (milliseconds since epoch).
    public func candleSnapshot(coin: String, interval: String, startTime: Int? = nil, endTime: Int? = nil) async throws -> [HLCandle] {
        var req: [String: Any] = [
            "coin": coin,
            "interval": interval
        ]
        if let startTime = startTime {
            req["startTime"] = startTime
        }
        if let endTime = endTime {
            req["endTime"] = endTime
        }
        let body: [String: Any] = [
            "type": "candleSnapshot",
            "req": req
        ]
        let raw: Any = try await postRaw("/info", body)
        guard let array = raw as? [[String: Any]] else {
            print("[HLInfo] candleSnapshot: unexpected format")
            return []
        }
        var candles: [HLCandle] = []
        for item in array {
            guard let t = item["t"] as? Int,
                  let T = item["T"] as? Int,
                  let s = item["s"] as? String,
                  let i = item["i"] as? String,
                  let n = item["n"] as? Int else { continue }
            let o = item["o"]
            let openValue = (o as? String).flatMap(Double.init) ?? (o as? Double) ?? 0
            let c = item["c"]
            let closeValue = (c as? String).flatMap(Double.init) ?? (c as? Double) ?? 0
            let h = item["h"]
            let highValue = (h as? String).flatMap(Double.init) ?? (h as? Double) ?? 0
            let l = item["l"]
            let lowValue = (l as? String).flatMap(Double.init) ?? (l as? Double) ?? 0
            let v = item["v"]
            let volumeValue = (v as? String).flatMap(Double.init) ?? (v as? Double) ?? 0
            candles.append(HLCandle(
                openTime: t,
                closeTime: T,
                coin: s,
                interval: i,
                open: openValue,
                close: closeValue,
                high: highValue,
                low: lowValue,
                volume: volumeValue,
                numTrades: n
            ))
        }
        return candles
    }

    /// Retrieves funding rate history for a coin.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol.
    ///   - startTime: Start of the time window (milliseconds since epoch).
    ///   - endTime: Optional end of the time window.
    /// - Returns: Raw JSON response (structure varies by API version).
    public func fundingHistory(coin: String, startTime: Int, endTime: Int? = nil) async throws -> Any {
        var body: [String: Any] = [
            "type": "fundingHistory",
            "coin": coin,
            "startTime": startTime
        ]
        if let endTime = endTime {
            body["endTime"] = endTime
        }
        return try await postRaw("/info", body)
    }

    /// Retrieves funding payment records for a user.
    ///
    /// - Parameters:
    ///   - address: The user's Ethereum address.
    ///   - startTime: Start of the time window (milliseconds since epoch).
    public func userFunding(address: String, startTime: Int) async throws -> [HLFundingRecord] {
        var body: [String: Any] = [
            "type": "userFunding",
            "user": address,
            "startTime": startTime
        ]
        return try await post("/info", body)
    }

    /// Retrieves non-funding ledger updates (deposits, withdrawals, transfers) for a user.
    ///
    /// - Parameters:
    ///   - address: The user's Ethereum address.
    ///   - startTime: Start of the time window (milliseconds since epoch).
    public func userNonFundingLedgerUpdates(address: String, startTime: Int) async throws -> [HLLedgerUpdate] {
        var body: [String: Any] = [
            "type": "userNonFundingLedgerUpdates",
            "user": address,
            "startTime": startTime
        ]
        return try await post("/info", body)
    }

    /// Retrieves vault equity information for a user.
    ///
    /// - Parameter address: The user's Ethereum address.
    public func userVaultEquities(address: String) async throws -> [HLVaultEquity] {
        return try await post("/info", ["type": "userVaultEquities", "user": address])
    }

    /// Retrieves the staking delegator summary for a user.
    ///
    /// - Parameter address: The user's Ethereum address.
    public func delegatorSummary(address: String) async throws -> HLDelegatorSummary {
        return try await post("/info", ["type": "delegatorSummary", "user": address])
    }

    /// Retrieves extra agent (API wallet) configurations for a user.
    ///
    /// - Parameter address: The user's Ethereum address.
    public func extraAgents(address: String) async throws -> [HLAgentWallet] {
        return try await post("/info", ["type": "extraAgents", "user": address])
    }

    /// Retrieves portfolio history (account value, PnL, volume) for a user.
    ///
    /// The raw response is manually parsed because the portfolio data structure
    /// contains nested arrays with mixed types that don't map cleanly to SmartCodable.
    ///
    /// - Parameter address: The user's Ethereum address.
    public func portfolio(address: String) async throws -> [HLPortfolioPeriod] {
        let raw: Any = try await postRaw("/info", ["type": "portfolio", "user": address])
        guard let array = raw as? [[Any]] else {
            print("[HLInfo] portfolio: unexpected format")
            return []
        }

        var result: [HLPortfolioPeriod] = []
        for item in array {
            guard item.count >= 2,
                  let period = item[0] as? String,
                  let data = item[1] as? [String: Any] else { continue }

            var avHistory: [(time: Int, value: Double)] = []
            if let avArray = data["accountValueHistory"] as? [[Any]] {
                for point in avArray {
                    guard point.count >= 2,
                          let t = point[0] as? Int,
                          let v = point[1] as? String else { continue }
                    avHistory.append((time: t, value: Double(v) ?? 0))
                }
            }

            var pnlHistory: [(time: Int, pnl: Double)] = []
            if let pnlArray = data["pnlHistory"] as? [[Any]] {
                for point in pnlArray {
                    guard point.count >= 2,
                          let t = point[0] as? Int,
                          let p = point[1] as? String else { continue }
                    pnlHistory.append((time: t, pnl: Double(p) ?? 0))
                }
            }

            let vlm = data["vlm"] as? Double ?? 0

            result.append(HLPortfolioPeriod(
                period: period,
                accountValueHistory: avHistory,
                pnlHistory: pnlHistory,
                volume: vlm
            ))
        }
        return result
    }

    /// Maps a coin name to its numeric asset index.
    ///
    /// Returns 0 if metadata has not been loaded or the coin is not found.
    /// This method is used internally by `HyperliquidExchange` for wire-format construction.
    ///
    /// - Parameter name: The coin symbol (e.g. "BTC").
    func nameToAsset(_ name: String) -> Int {
        if !isMetaLoaded {
            return 0
        }
        return coinToAsset[name] ?? 0
    }

    /// Returns the number of size decimal places for a given asset index.
    ///
    /// Returns 0 if metadata has not been loaded or the asset is not found.
    ///
    /// - Parameter asset: The numeric asset index.
    func szDecimals(for asset: Int) -> Int {
        return assetToSzDecimals[asset] ?? 0
    }
}
