//
//  HyperliquidClient.swift
//  SuperHyper
//
//  Created by Ian.Wang on 2026/5/18.
//  Copyright © 2026 Ian.Wang. All rights reserved.
//

import Foundation

/// The primary interface for the Hyperliquid SDK.
///
/// `HyperliquidClient` wraps the three core subsystems — `HyperliquidInfo` for read-only queries,
/// `HyperliquidExchange` for signed trading operations, and `HyperliquidWebSocket` for real-time
/// streaming data — into a single convenient entry point.
///
/// Typical usage:
/// ```swift
/// let client = HyperliquidClient(isMainnet: true)
/// try client.connect(privateKey: "0x…")
/// let state = try await client.getUserState()
/// ```
public class HyperliquidClient {

    /// The info subsystem used for read-only queries (market data, user state, etc.).
    public let info: HyperliquidInfo

    /// The exchange subsystem used for signed trading operations.
    /// Available only after calling one of the `connect()` methods.
    public private(set) var exchange: HyperliquidExchange?

    /// The WebSocket subsystem for real-time streaming subscriptions.
    public let ws: HyperliquidWebSocket

    private var _baseURL: String
    private var _mainWallet: String?

    /// Returns `true` if the client is configured to connect to the mainnet API.
    public var isMainnet: Bool {
        return _baseURL == HLConstants.mainnetAPIURL
    }

    /// Creates a client with a boolean network selector.
    ///
    /// - Parameters:
    ///   - isMainnet: Pass `true` for mainnet (default), `false` for testnet.
    ///   - timeout: HTTP request timeout in seconds.
    public convenience init(isMainnet: Bool = true, timeout: TimeInterval = 30) {
        self.init(
            baseURL: isMainnet ? HLConstants.mainnetAPIURL : HLConstants.testnetAPIURL,
            timeout: timeout
        )
    }

    /// Creates a client with a custom base URL.
    ///
    /// - Parameters:
    ///   - baseURL: The Hyperliquid API base URL.
    ///   - timeout: HTTP request timeout in seconds.
    public init(baseURL: String = HLConstants.mainnetAPIURL, timeout: TimeInterval = 30) {
        self._baseURL = baseURL
        self.info = HyperliquidInfo(baseURL: baseURL, timeout: timeout)
        let wsURL = baseURL == HLConstants.mainnetAPIURL ? HLConstants.mainnetWSURL : HLConstants.testnetWSURL
        self.ws = HyperliquidWebSocket(baseURL: wsURL)
    }

    /// Connects to the exchange using a private key and optional vault address.
    ///
    /// After a successful connection the `exchange` property becomes available and
    /// market metadata is loaded asynchronously in the background.
    ///
    /// - Parameters:
    ///   - privateKey: The hex-encoded private key for signing transactions.
    ///   - vaultAddress: An optional vault address to operate on behalf of.
    /// - Throws: `HLError` if the private key is invalid.
    public func connect(privateKey: String, vaultAddress: String? = nil) throws {
        self.exchange = try HyperliquidExchange(
            privateKey: privateKey,
            baseURL: _baseURL,
            vaultAddress: vaultAddress
        )
        self._mainWallet = vaultAddress
        Task {
            do {
                try await self.info.loadMeta()
                try await self.exchange?.info.loadMeta()
            } catch {
                HLLog.error("loadMeta error: \(error)")
            }
        }
    }

    /// Connects to the exchange with a separate main wallet and signing key.
    ///
    /// Use this when the wallet that holds the funds (mainWallet) differs from the
    /// wallet that signs the transactions (privateKey), e.g. API wallet setups.
    ///
    /// - Parameters:
    ///   - mainWallet: The address whose positions/orders are being managed.
    ///   - privateKey: The hex-encoded private key used for signing.
    /// - Throws: `HLError` if the private key is invalid.
    public func connect(mainWallet: String, privateKey: String) throws {
        self.exchange = try HyperliquidExchange(
            privateKey: privateKey,
            baseURL: _baseURL
        )
        self.exchange?.queryAddress = mainWallet
        self._mainWallet = mainWallet
        HLLog.info("connect mainWallet=\(mainWallet), signingAddress=\(exchange?.walletAddress ?? "nil")")
        Task {
            do {
                try await self.info.loadMeta()
                try await self.exchange?.info.loadMeta()
                HLLog.info("meta loaded for both info instances")
            } catch {
                HLLog.error("loadMeta error: \(error)")
            }
        }
    }

    /// The wallet address used for queries — either the vault address, main wallet, or signing address.
    public var walletAddress: String? {
        return _mainWallet ?? exchange?.walletAddress
    }

    /// The Ethereum address derived from the signing private key.
    public var signingAddress: String? {
        return exchange?.walletAddress
    }

    /// Explicitly loads market metadata (coin universe, size decimals, etc.).
    ///
    /// This is called automatically during `connect()`, but can be invoked manually
    /// if you need to refresh the metadata.
    public func loadMeta() async throws {
        try await info.loadMeta()
    }

    /// Returns a dictionary mapping coin names to their current mid prices.
    public func getAllMids() async throws -> [String: String] {
        return try await info.allMids()
    }

    /// Returns coin metadata and asset contexts (mark price, funding, open interest, etc.).
    public func getMetaAndAssetCtxs() async throws -> (meta: [HLCoinInfo], ctxs: [HLAssetCtx]) {
        return try await info.metaAndAssetCtxs()
    }

    /// Retrieves the full user state (positions, margin, cross-chain info) for the connected wallet.
    ///
    /// - Throws: `HLError.signingError` if the client is not connected.
    public func getUserState() async throws -> HLUserState {
        guard let address = walletAddress else {
            throw HLError.signingError("Not connected")
        }
        HLLog.info("getUserState address=\(address)")
        return try await info.userState(address: address)
    }

    /// Retrieves all open orders for the connected wallet.
    ///
    /// - Throws: `HLError.signingError` if the client is not connected.
    public func getOpenOrders() async throws -> [HLOpenOrder] {
        guard let address = walletAddress else {
            throw HLError.signingError("Not connected")
        }
        HLLog.info("getOpenOrders address=\(address)")
        return try await info.openOrders(address: address)
    }

    /// Retrieves all open orders including trigger/TP/SL orders with full metadata.
    ///
    /// Unlike `getOpenOrders()`, this uses the `frontendOpenOrders` endpoint which
    /// returns `triggerPx`, `isTrigger`, `orderType` (with nested trigger info),
    /// and other fields needed to identify TP/SL orders.
    ///
    /// - Throws: `HLError.signingError` if the client is not connected.
    public func getFrontendOpenOrders() async throws -> [HLOpenOrder] {
        guard let address = walletAddress else {
            throw HLError.signingError("Not connected")
        }
        HLLog.info("getFrontendOpenOrders address=\(address)")
        return try await info.frontendOpenOrders(address: address)
    }

    /// Retrieves all fills for the connected wallet.
    ///
    /// - Throws: `HLError.signingError` if the client is not connected.
    public func getUserFills() async throws -> [HLUserFill] {
        guard let address = walletAddress else {
            throw HLError.signingError("Not connected")
        }
        HLLog.info("getUserFills address=\(address)")
        return try await info.userFills(address: address)
    }

    /// Retrieves fills for the connected wallet filtered by time range.
    ///
    /// - Parameters:
    ///   - startTime: Start of the time window (milliseconds since epoch).
    ///   - endTime: Optional end of the time window (milliseconds since epoch).
    /// - Throws: `HLError.signingError` if the client is not connected.
    public func getUserFillsByTime(startTime: Int, endTime: Int? = nil) async throws -> [HLUserFill] {
        guard let address = walletAddress else {
            throw HLError.signingError("Not connected")
        }
        HLLog.info("getUserFillsByTime address=\(address) startTime=\(startTime)")
        return try await info.userFillsByTime(address: address, startTime: startTime, endTime: endTime)
    }

    /// Retrieves funding payment records for the connected wallet.
    ///
    /// - Parameter startTime: Start of the time window (milliseconds since epoch).
    /// - Throws: `HLError.signingError` if the client is not connected.
    public func getUserFunding(startTime: Int) async throws -> [HLFundingRecord] {
        guard let address = walletAddress else {
            throw HLError.signingError("Not connected")
        }
        return try await info.userFunding(address: address, startTime: startTime)
    }

    /// Retrieves non-funding ledger updates (deposits, withdrawals, transfers) for the connected wallet.
    ///
    /// - Parameter startTime: Start of the time window (milliseconds since epoch).
    /// - Throws: `HLError.signingError` if the client is not connected.
    public func getUserNonFundingLedgerUpdates(startTime: Int) async throws -> [HLLedgerUpdate] {
        guard let address = walletAddress else {
            throw HLError.signingError("Not connected")
        }
        return try await info.userNonFundingLedgerUpdates(address: address, startTime: startTime)
    }

    /// Retrieves vault equity information for the connected wallet.
    ///
    /// - Throws: `HLError.signingError` if the client is not connected.
    public func getUserVaultEquities() async throws -> [HLVaultEquity] {
        guard let address = walletAddress else {
            throw HLError.signingError("Not connected")
        }
        return try await info.userVaultEquities(address: address)
    }

    /// Retrieves the staking delegator summary for the connected wallet.
    ///
    /// - Throws: `HLError.signingError` if the client is not connected.
    public func getDelegatorSummary() async throws -> HLDelegatorSummary {
        guard let address = walletAddress else {
            throw HLError.signingError("Not connected")
        }
        return try await info.delegatorSummary(address: address)
    }

    /// Retrieves the spot clearinghouse state for the connected wallet.
    ///
    /// - Throws: `HLError.signingError` if the client is not connected.
    public func getSpotState() async throws -> HLSpotState {
        guard let address = walletAddress else {
            throw HLError.signingError("Not connected")
        }
        return try await info.spotState(address: address)
    }

    /// Retrieves extra agent (API wallet) configurations for the connected wallet.
    ///
    /// - Throws: `HLError.signingError` if the client is not connected.
    public func getExtraAgents() async throws -> [HLAgentWallet] {
        guard let address = walletAddress else {
            throw HLError.signingError("Not connected")
        }
        return try await info.extraAgents(address: address)
    }

    /// Retrieves extra agent (API wallet) configurations for a specific address.
    ///
    /// - Parameter address: The wallet address to query.
    public func getExtraAgentsForAddress(_ address: String) async throws -> [HLAgentWallet] {
        return try await info.extraAgents(address: address)
    }

    /// Retrieves portfolio history (account value, PnL, volume) for the connected wallet.
    ///
    /// - Throws: `HLError.signingError` if the client is not connected.
    public func getPortfolio() async throws -> [HLPortfolioPeriod] {
        guard let address = walletAddress else {
            throw HLError.signingError("Not connected")
        }
        return try await info.portfolio(address: address)
    }

    /// Retrieves the L2 order book snapshot for a given coin.
    ///
    /// - Parameter coin: The coin symbol (e.g. "BTC", "ETH").
    public func getL2Snapshot(coin: String) async throws -> HLL2Snapshot {
        return try await info.l2Snapshot(coin: coin)
    }

    /// Returns the number of size decimals for a given coin (e.g. BTC → 5, ETH → 4).
    ///
    /// - Parameter coin: The coin symbol.
    public func szDecimals(for coin: String) -> Int {
        let asset = info.nameToAsset(coin)
        return info.szDecimals(for: asset)
    }

    /// Places a limit or IOC order on the exchange.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol (e.g. "BTC").
    ///   - isBuy: `true` for a buy order, `false` for a sell order.
    ///   - sz: Order size in base units.
    ///   - limitPx: Limit price.
    ///   - timeInForce: Time-in-force policy (default `.ioc`).
    /// - Returns: The order result containing status and fill information.
    /// - Throws: `HLError.signingError` if the client is not connected.
    public func placeOrder(
        coin: String,
        isBuy: Bool,
        sz: Double,
        limitPx: Double,
        timeInForce: HLTimeInForce = .ioc
    ) async throws -> HLOrderResult {
        guard let exchange = exchange else {
            throw HLError.signingError("Not connected")
        }
        return try await exchange.order(
            coin: coin,
            isBuy: isBuy,
            sz: sz,
            limitPx: limitPx,
            orderType: ["limit": ["tif": timeInForce.rawValue]]
        )
    }

    /// Places a market order with a slippage tolerance.
    ///
    /// The limit price is automatically derived from the current mid price plus slippage.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol.
    ///   - isBuy: `true` for a buy order, `false` for a sell order.
    ///   - sz: Order size in base units.
    ///   - slippage: Slippage tolerance as a fraction (default 5%).
    /// - Returns: The order result containing status and fill information.
    /// - Throws: `HLError.signingError` if the client is not connected.
    public func placeMarketOrder(
        coin: String,
        isBuy: Bool,
        sz: Double,
        slippage: Double = 0.05
    ) async throws -> HLOrderResult {
        guard let exchange = exchange else {
            throw HLError.signingError("Not connected")
        }
        return try await exchange.marketOpen(coin: coin, isBuy: isBuy, sz: sz, slippage: slippage)
    }

    /// Places a trigger (take-profit / stop-loss) order.
    ///
    /// If `limitPx` is not provided, it is derived from the trigger price:
    /// - For market trigger orders, a 0.5% slippage buffer is applied.
    /// - For limit trigger orders, the limit price equals the trigger price.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol.
    ///   - isBuy: `true` for a buy trigger, `false` for a sell trigger.
    ///   - sz: Order size in base units.
    ///   - triggerPx: The price at which the order activates.
    ///   - limitPx: Optional limit price once triggered.
    ///   - isMarket: Whether this is a market trigger order (default `false`).
    ///   - tpsl: `.tp` for take-profit, `.sl` for stop-loss (default `.sl`).
    ///   - reduceOnly: Whether the order can only reduce an existing position.
    /// - Returns: The order result containing status and fill information.
    /// - Throws: `HLError.signingError` if the client is not connected.
    public func placeTriggerOrder(
        coin: String,
        isBuy: Bool,
        sz: Double,
        triggerPx: Double,
        limitPx: Double? = nil,
        isMarket: Bool = false,
        tpsl: HLTPSL = .sl,
        reduceOnly: Bool = false
    ) async throws -> HLOrderResult {
        guard let exchange = exchange else {
            throw HLError.signingError("Not connected")
        }
        let px: Double
        if let limitPx {
            px = limitPx
        } else if isMarket {
            let slippage = 0.005
            px = isBuy ? triggerPx * (1 + slippage) : triggerPx * (1 - slippage)
        } else {
            px = triggerPx
        }
        return try await exchange.order(
            coin: coin,
            isBuy: isBuy,
            sz: sz,
            limitPx: px,
            orderType: [
                "trigger": [
                    "triggerPx": triggerPx,
                    "isMarket": isMarket,
                    "tpsl": tpsl.rawValue
                ]
            ],
            reduceOnly: reduceOnly
        )
    }

    /// Closes the entire position for a coin using a market order with slippage.
    ///
    /// The position size and direction are automatically determined from the current user state.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol of the position to close.
    ///   - slippage: Slippage tolerance as a fraction (default 5%).
    /// - Returns: The order result containing status and fill information.
    /// - Throws: `HLError.signingError` if the client is not connected or no position exists.
    public func closePosition(coin: String, slippage: Double = 0.05) async throws -> HLOrderResult {
        guard let exchange = exchange else {
            throw HLError.signingError("Not connected")
        }
        return try await exchange.marketClose(coin: coin, slippage: slippage)
    }

    /// Cancels an open order by coin and order ID.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol of the order.
    ///   - oid: The order ID to cancel.
    /// - Returns: The order result containing cancellation status.
    /// - Throws: `HLError.signingError` if the client is not connected.
    public func cancelOrder(coin: String, oid: Int) async throws -> HLOrderResult {
        guard let exchange = exchange else {
            throw HLError.signingError("Not connected")
        }
        return try await exchange.cancel(coin: coin, oid: oid)
    }

    /// Updates the leverage for a given coin.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol.
    ///   - leverage: The desired leverage value.
    ///   - isCross: `true` for cross margin (default), `false` for isolated margin.
    /// - Returns: The order result containing the update status.
    /// - Throws: `HLError.signingError` if the client is not connected.
    public func updateLeverage(coin: String, leverage: Int, isCross: Bool = true) async throws -> HLOrderResult {
        guard let exchange = exchange else {
            throw HLError.signingError("Not connected")
        }
        return try await exchange.updateLeverage(coin: coin, leverage: leverage, isCross: isCross)
    }
}
