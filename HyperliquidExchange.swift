//
//  HyperliquidExchange.swift
//  SuperHyper
//
//  Created by Ian.Wang on 2026/5/18.
//  Copyright © 2026 Ian.Wang. All rights reserved.
//

import Foundation

/// Handles authenticated exchange operations on Hyperliquid (place/cancel orders, update leverage, etc.).
///
/// `HyperliquidExchange` inherits from `HyperliquidAPI` and adds EIP-712 signing via
/// `HyperliquidSigning`. Every exchange action follows the same flow:
/// 1. Build an `OrderedAction` with the required parameters.
/// 2. Sign the action using `signL1Action` (EIP-712 typed data).
/// 3. POST the action + signature + nonce to the `/exchange` endpoint.
///
/// Price formatting is handled automatically by `formatPrice`, which applies the
/// correct number of significant figures and decimal places based on the coin's
/// `szDecimals` from the loaded metadata.
public class HyperliquidExchange: HyperliquidAPI {

    /// The signing utility that holds the private key and performs EIP-712 signatures.
    private let signing: HyperliquidSigning

    /// An embedded `HyperliquidInfo` instance used for metadata lookups during order construction.
    private(set) var info: HyperliquidInfo

    /// Optional expiration timestamp (ms) for orders. When set, orders expire after this time.
    private var expiresAfter: Int?

    /// An optional override address used for querying user state (e.g. when operating on behalf
    /// of a main wallet via an API key).
    public var queryAddress: String?

    /// Creates an exchange instance with the given private key.
    ///
    /// - Parameters:
    ///   - privateKey: The hex-encoded private key for signing L1 actions.
    ///   - baseURL: The Hyperliquid API base URL.
    ///   - vaultAddress: An optional vault address to include in signed payloads.
    ///   - timeout: HTTP request timeout in seconds.
    /// - Throws: `HLError` if the private key is invalid.
    public init(
        privateKey: String,
        baseURL: String = HLConstants.mainnetAPIURL,
        vaultAddress: String? = nil,
        timeout: TimeInterval = 30
    ) throws {
        let isMainnet = baseURL == HLConstants.mainnetAPIURL
        self.signing = try HyperliquidSigning(privateKey: privateKey, isMainnet: isMainnet, vaultAddress: vaultAddress)
        self.info = HyperliquidInfo(baseURL: baseURL, timeout: timeout)
        super.init(baseURL: baseURL, timeout: timeout)
    }

    /// The Ethereum address derived from the signing private key.
    public var walletAddress: String {
        return signing.address
    }

    /// Sets an optional expiration timestamp for subsequent orders.
    ///
    /// - Parameter expiresAfter: Expiration time in milliseconds since epoch, or `nil` to disable.
    public func setExpiresAfter(_ expiresAfter: Int?) {
        self.expiresAfter = expiresAfter
    }

    /// Places a single order (limit, IOC, or trigger) on the exchange.
    ///
    /// The price is automatically formatted using `formatPrice` to comply with Hyperliquid's
    /// significant-figure requirements. The order is submitted as a bulk operation with one entry.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol (e.g. "BTC").
    ///   - isBuy: `true` for a buy order, `false` for a sell order.
    ///   - sz: Order size in base units.
    ///   - limitPx: The limit price (will be formatted automatically).
    ///   - orderType: A dictionary describing the order type (e.g. `["limit": ["tif": "Ioc"]]`
    ///     or `["trigger": ["triggerPx": …, "isMarket": …, "tpsl": …]]`).
    ///   - reduceOnly: Whether the order can only reduce an existing position.
    ///   - builder: Optional builder fee parameters.
    /// - Returns: The order result containing status and fill information.
    public func order(
        coin: String,
        isBuy: Bool,
        sz: Double,
        limitPx: Double,
        orderType: [String: Any],
        reduceOnly: Bool = false,
        builder: [String: Any]? = nil
    ) async throws -> HLOrderResult {
        let formattedPx = formatPrice(coin: coin, price: limitPx)
        let formattedOrderType = formatOrderTypePrices(coin: coin, orderType: orderType)
        let orderRequest: [String: Any] = [
            "coin": coin,
            "is_buy": isBuy,
            "sz": sz,
            "limit_px": formattedPx,
            "order_type": formattedOrderType,
            "reduce_only": reduceOnly
        ]
        return try await bulkOrders([orderRequest], builder: builder)
    }

    /// Submits multiple orders in a single signed request.
    ///
    /// Each order is converted to the wire format required by the Hyperliquid L1 action
    /// specification, signed with EIP-712, and posted to the exchange endpoint.
    ///
    /// - Parameters:
    ///   - orderRequests: An array of order dictionaries (each must contain `coin`, `is_buy`,
    ///     `sz`, `limit_px`, `order_type`, and `reduce_only`).
    ///   - builder: Optional builder fee parameters.
    ///   - grouping: Order grouping strategy (default `"na"`).
    /// - Returns: The order result containing status and fill information for all orders.
    public func bulkOrders(
        _ orderRequests: [[String: Any]],
        builder: [String: Any]? = nil,
        grouping: String = "na"
    ) async throws -> HLOrderResult {
        if !info.isMetaLoaded { try await info.loadMeta() }
        let orderWires = orderRequests.map { req -> OrderedAction in
            let asset = info.nameToAsset(req["coin"] as? String ?? "")
            return OrderedAction([
                ("a", asset as Any),
                ("b", req["is_buy"] as Any),
                ("p", HyperliquidSigning.floatToWire(req["limit_px"] as? Double ?? 0) as Any),
                ("s", HyperliquidSigning.floatToWire(req["sz"] as? Double ?? 0) as Any),
                ("r", req["reduce_only"] as Any),
                ("t", orderTypeToWire(req["order_type"] as? [String: Any] ?? [:]) as Any)
            ])
        }

        let timestamp = HyperliquidSigning.getTimestampMs()

        // Build the L1 action for EIP-712 signing (uses OrderedAction for deterministic key order)
        let orderAction = OrderedAction([
            ("type", "order"),
            ("orders", orderWires as Any),
            ("grouping", grouping)
        ])

        let signature = try signing.signL1Action(
            action: orderAction,
            nonce: timestamp,
            expiresAfter: expiresAfter
        )

        // Build the JSON payload for the HTTP request (uses plain dictionaries)
        let orderWiresDict = orderRequests.map { req -> [String: Any] in
            let asset = info.nameToAsset(req["coin"] as? String ?? "")
            return [
                "a": asset,
                "b": req["is_buy"] as? Bool ?? false,
                "p": HyperliquidSigning.floatToWire(req["limit_px"] as? Double ?? 0),
                "s": HyperliquidSigning.floatToWire(req["sz"] as? Double ?? 0),
                "r": req["reduce_only"] as? Bool ?? false,
                "t": orderTypeToWireDict(req["order_type"] as? [String: Any] ?? [:])
            ]
        }
        let actionDict: [String: Any] = [
            "type": "order",
            "orders": orderWiresDict,
            "grouping": grouping
        ]
        return try await postAction(actionDict, signature: signature, nonce: timestamp)
    }

    /// Opens a market position with a slippage-protected limit order.
    ///
    /// The limit price is derived from the current mid price ± slippage, then formatted
    /// and submitted as an IOC limit order.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol.
    ///   - isBuy: `true` for a buy, `false` for a sell.
    ///   - sz: Order size in base units.
    ///   - slippage: Slippage tolerance as a fraction (default 5%).
    /// - Returns: The order result containing status and fill information.
    public func marketOpen(
        coin: String,
        isBuy: Bool,
        sz: Double,
        slippage: Double = 0.05
    ) async throws -> HLOrderResult {
        let px = try await slippagePrice(coin: coin, isBuy: isBuy, slippage: slippage)
        return try await order(
            coin: coin,
            isBuy: isBuy,
            sz: sz,
            limitPx: px,
            orderType: ["limit": ["tif": "Ioc"]]
        )
    }

    /// Closes an existing position with a market order.
    ///
    /// The position size and direction are automatically determined from the current user state.
    /// If `sz` is not provided, the full position is closed.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol of the position to close.
    ///   - sz: Optional partial close size. If `nil`, the entire position is closed.
    ///   - slippage: Slippage tolerance as a fraction (default 5%).
    /// - Returns: The order result containing status and fill information.
    /// - Throws: `HLError.signingError` if no position exists for the given coin.
    public func marketClose(
        coin: String,
        sz: Double? = nil,
        slippage: Double = 0.05
    ) async throws -> HLOrderResult {
        let queryAddr = queryAddress ?? signing.vaultAddress ?? signing.address
        let userState = try await info.userState(address: queryAddr)
        var targetSize = sz
        var isBuy = true

        for positionEntry in userState.assetPositions {
            let pos = positionEntry.position
            if pos.coin != coin { continue }
            let szi = Double(pos.szi) ?? 0
            if targetSize == nil {
                targetSize = abs(szi)
            }
            isBuy = szi < 0
            break
        }

        guard let closeSize = targetSize, closeSize > 0 else {
            throw HLError.signingError("No position to close for \(coin)")
        }

        let px = try await slippagePrice(coin: coin, isBuy: isBuy, slippage: slippage)
        return try await order(
            coin: coin,
            isBuy: isBuy,
            sz: closeSize,
            limitPx: px,
            orderType: ["limit": ["tif": "Ioc"]],
            reduceOnly: true
        )
    }

    /// Cancels a single open order.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol of the order.
    ///   - oid: The order ID to cancel.
    /// - Returns: The order result containing cancellation status.
    public func cancel(coin: String, oid: Int) async throws -> HLOrderResult {
        return try await bulkCancel([["coin": coin, "oid": oid]])
    }

    /// Cancels multiple open orders in a single signed request.
    ///
    /// - Parameter cancelRequests: An array of dictionaries, each containing `coin` and `oid`.
    /// - Returns: The order result containing cancellation status for all orders.
    public func bulkCancel(_ cancelRequests: [[String: Any]]) async throws -> HLOrderResult {
        if !info.isMetaLoaded { try await info.loadMeta() }
        let timestamp = HyperliquidSigning.getTimestampMs()
        let cancels = cancelRequests.map { req -> OrderedAction in
            return OrderedAction([
                ("a", info.nameToAsset(req["coin"] as? String ?? "") as Any),
                ("o", req["oid"] as Any)
            ])
        }
        let cancelAction = OrderedAction([
            ("type", "cancel"),
            ("cancels", cancels as Any)
        ])
        let signature = try signing.signL1Action(
            action: cancelAction,
            nonce: timestamp,
            expiresAfter: expiresAfter
        )
        let cancelsDict = cancelRequests.map { req -> [String: Any] in
            return [
                "a": info.nameToAsset(req["coin"] as? String ?? ""),
                "o": req["oid"] as? Int ?? 0
            ]
        }
        let actionDict: [String: Any] = [
            "type": "cancel",
            "cancels": cancelsDict
        ]
        return try await postAction(actionDict, signature: signature, nonce: timestamp)
    }

    /// Updates the leverage for a given coin.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol.
    ///   - leverage: The desired leverage value.
    ///   - isCross: `true` for cross margin (default), `false` for isolated margin.
    /// - Returns: The order result containing the update status.
    public func updateLeverage(coin: String, leverage: Int, isCross: Bool = true) async throws -> HLOrderResult {
        if !info.isMetaLoaded { try await info.loadMeta() }
        let timestamp = HyperliquidSigning.getTimestampMs()
        let action = OrderedAction([
            ("type", "updateLeverage"),
            ("asset", info.nameToAsset(coin) as Any),
            ("isCross", isCross),
            ("leverage", leverage)
        ])
        let signature = try signing.signL1Action(
            action: action,
            nonce: timestamp,
            expiresAfter: expiresAfter
        )
        let actionDict: [String: Any] = [
            "type": "updateLeverage",
            "asset": info.nameToAsset(coin),
            "isCross": isCross,
            "leverage": leverage
        ]
        return try await postAction(actionDict, signature: signature, nonce: timestamp)
    }

    /// Updates the isolated margin for a given coin.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol.
    ///   - amount: The margin adjustment amount in USD.
    /// - Returns: The order result containing the update status.
    public func updateIsolatedMargin(coin: String, amount: Double) async throws -> HLOrderResult {
        let timestamp = HyperliquidSigning.getTimestampMs()
        let action = OrderedAction([
            ("type", "updateIsolatedMargin"),
            ("asset", info.nameToAsset(coin) as Any),
            ("isBuy", true),
            ("ntli", HyperliquidSigning.floatToUsdInt(amount))
        ])
        let signature = try signing.signL1Action(
            action: action,
            nonce: timestamp,
            expiresAfter: expiresAfter
        )
        let actionDict: [String: Any] = [
            "type": "updateIsolatedMargin",
            "asset": info.nameToAsset(coin),
            "isBuy": true,
            "ntli": HyperliquidSigning.floatToUsdInt(amount)
        ]
        return try await postAction(actionDict, signature: signature, nonce: timestamp)
    }

    /// Posts a signed action to the exchange endpoint.
    ///
    /// This is the common submission path for all exchange operations. It assembles the
    /// action, nonce, signature, and optional vault address into the final HTTP payload.
    ///
    /// - Parameters:
    ///   - action: The action dictionary (e.g. order, cancel, updateLeverage).
    ///   - signature: The EIP-712 signature produced by `signL1Action`.
    ///   - nonce: The nonce used during signing.
    /// - Returns: The parsed order result.
    private func postAction(_ action: [String: Any], signature: [String: Any], nonce: Int) async throws -> HLOrderResult {
        let payload: [String: Any]
        if let vault = signing.vaultAddress {
            payload = [
                "action": action,
                "nonce": nonce,
                "signature": signature,
                "vaultAddress": vault
            ]
        } else {
            payload = [
                "action": action,
                "nonce": nonce,
                "signature": signature
            ]
        }
        return try await postOrderResult("/exchange", payload)
    }

    /// Formats a price to comply with Hyperliquid's significant-figure and decimal-place rules.
    ///
    /// The logic works in two steps:
    /// 1. **Decimal rounding**: Rounds to `max(6 - szDecimals, 0)` decimal places.
    /// 2. **Significant-figure rounding**: Rounds to 5 significant figures.
    ///
    /// For example, if `szDecimals = 5` (BTC), the price is rounded to 1 decimal place
    /// and 5 significant figures.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol used to look up `szDecimals`.
    ///   - price: The raw price value.
    /// - Returns: The formatted price.
    private func formatPrice(coin: String, price: Double) -> Double {
        let szDecimals = info.szDecimals(for: info.nameToAsset(coin))
        let decimals = max(6 - szDecimals, 0)
        let multiplier = pow(10.0, Double(decimals))
        let rounded = round(price * multiplier) / multiplier
        let absPrice = abs(rounded)
        if absPrice == 0 { return 0 }
        let sigFigs = 5
        let magnitude = floor(log10(absPrice)) + 1
        let sigMultiplier = pow(10.0, Double(sigFigs) - magnitude)
        let sigRounded = round(rounded * sigMultiplier) / sigMultiplier
        return round(sigRounded * multiplier) / multiplier
    }

    /// Formats trigger prices within an order type dictionary using `formatPrice`.
    ///
    /// Only processes `trigger` order types; `limit` order types are returned unchanged.
    private func formatOrderTypePrices(coin: String, orderType: [String: Any]) -> [String: Any] {
        var result = orderType
        if let trigger = orderType["trigger"] as? [String: Any],
           let triggerPx = trigger["triggerPx"] as? Double {
            var formattedTrigger = trigger
            formattedTrigger["triggerPx"] = formatPrice(coin: coin, price: triggerPx)
            result["trigger"] = formattedTrigger
        }
        return result
    }

    /// Calculates a slippage-adjusted price from the current mid price.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol.
    ///   - isBuy: `true` adds slippage upward, `false` subtracts downward.
    ///   - slippage: Slippage tolerance as a fraction.
    ///   - px: An optional override mid price; if `nil`, fetched from `allMids`.
    /// - Returns: The formatted slippage-adjusted price.
    private func slippagePrice(coin: String, isBuy: Bool, slippage: Double, px: Double? = nil) async throws -> Double {
        var price = px
        if price == nil {
            let mids = try await info.allMids()
            guard let midStr = mids[coin], let mid = Double(midStr) else {
                throw HLError.signingError("Cannot get mid price for \(coin)")
            }
            price = mid
        }
        var adjusted = price!
        adjusted *= isBuy ? (1 + slippage) : (1 - slippage)
        return formatPrice(coin: coin, price: adjusted)
    }

    /// Converts an order type dictionary to the `OrderedAction` wire format for EIP-712 signing.
    ///
    /// Ensures deterministic key ordering, which is critical for signature reproducibility.
    private func orderTypeToWire(_ orderType: [String: Any]) -> Any {
        if let limit = orderType["limit"] as? [String: Any] {
            return OrderedAction([
                ("limit", OrderedAction([
                    ("tif", limit["tif"] as Any)
                ]) as Any)
            ])
        } else if let trigger = orderType["trigger"] as? [String: Any] {
            return OrderedAction([
                ("trigger", OrderedAction([
                    ("isMarket", trigger["isMarket"] as Any),
                    ("triggerPx", HyperliquidSigning.floatToWire(trigger["triggerPx"] as? Double ?? 0) as Any),
                    ("tpsl", trigger["tpsl"] as Any)
                ]) as Any)
            ])
        }
        return orderType
    }

    /// Converts an order type dictionary to a plain dictionary wire format for the HTTP payload.
    private func orderTypeToWireDict(_ orderType: [String: Any]) -> [String: Any] {
        if let limit = orderType["limit"] as? [String: Any] {
            return ["limit": limit]
        } else if let trigger = orderType["trigger"] as? [String: Any] {
            var wire: [String: Any] = [
                "isMarket": trigger["isMarket"] as? Bool ?? false,
                "tpsl": trigger["tpsl"] as? String ?? "sl"
            ]
            if let triggerPx = trigger["triggerPx"] as? Double {
                wire["triggerPx"] = HyperliquidSigning.floatToWire(triggerPx)
            }
            return ["trigger": wire]
        }
        return orderType
    }
}
