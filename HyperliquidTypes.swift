//
//  HyperliquidTypes.swift
//  SuperHyper
//
//  Created by Ian.Wang on 2026/5/18.
//  Copyright © 2026 Ian.Wang. All rights reserved.
//

import Foundation
import SmartCodable

/// Hyperliquid API endpoint constants for mainnet and testnet environments.
public enum HLConstants {
    /// Mainnet REST API base URL.
    public static let mainnetAPIURL = "https://api.hyperliquid.xyz"
    /// Testnet REST API base URL.
    public static let testnetAPIURL = "https://api.hyperliquid-testnet.xyz"
    /// Mainnet WebSocket endpoint.
    public static let mainnetWSURL = "wss://api.hyperliquid.xyz/ws"
    /// Testnet WebSocket endpoint.
    public static let testnetWSURL = "wss://api.hyperliquid-testnet.xyz/ws"
}

/// Errors that can occur when interacting with the Hyperliquid SDK.
public enum HLError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case signingError(String)
    case invalidPrivateKey
    case networkError(Error)

    /// A human-readable description for each error case.
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response from server"
        case .httpError(let code): return "HTTP error: \(code)"
        case .decodingError(let err): return "Decoding error: \(err.localizedDescription)"
        case .signingError(let msg): return "Signing error: \(msg)"
        case .invalidPrivateKey: return "Invalid private key"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}

/// Metadata for a perpetual asset on Hyperliquid.
/// Contains the asset name, size decimals, and leverage constraints.
public struct HLCoinInfo: SmartCodableX {
    /// Ticker symbol, e.g. "BTC", "ETH".
    public var name: String = ""
    /// Number of decimal places for position size.
    public var szDecimals: Int = 0
    /// Maximum allowed leverage for this asset.
    public var maxLeverage: Int?
    /// Whether this asset only supports isolated margin mode.
    public var onlyIsolated: Bool?
    public init() {}
}

/// Real-time market context for a perpetual asset.
/// Includes funding rate, mark price, open interest, and oracle price.
public struct HLAssetCtx: SmartCodableX {
    /// 24-hour notional volume.
    public var dayNtlVlm: String?
    /// Current funding rate (per hour).
    public var funding: String?
    /// Current mark price.
    public var markPx: String?
    /// Current mid price (average of best bid and ask).
    public var midPx: String?
    /// Current open interest in asset units.
    public var openInterest: String?
    /// Oracle price from the Pyth oracle.
    public var oraclePx: String?
    /// Premium relative to the oracle price.
    public var premium: String?
    /// Previous day's closing price.
    public var prevDayPx: String?
    /// Impact prices for bid and ask (used for margin calculations).
    public var impactPxs: [String]?
    public init() {}
}

/// A single price level in the L2 order book.
public struct HLL2Level: SmartCodableX {
    /// Number of orders at this price level.
    public var n: Int = 0
    /// Price as a decimal string.
    public var px: String = ""
    /// Total size at this price level.
    public var sz: String = ""
    public init() {}
}

/// A snapshot of the L2 order book for a single asset.
public struct HLL2Snapshot: SmartCodableX {
    /// Ticker symbol for this order book.
    public var coin: String = ""
    /// Order book levels: index 0 = bids, index 1 = asks.
    public var levels: [[HLL2Level]] = []
    /// Server timestamp of this snapshot (milliseconds).
    public var time: Int = 0
    public init() {}
}

/// A user's open position on a perpetual asset.
public struct HLPosition: SmartCodableX {
    /// Ticker symbol, e.g. "BTC".
    public var coin: String = ""
    /// Average entry price.
    public var entryPx: String?
    /// Current leverage setting for this position.
    public var leverage: HLLeverage = HLLeverage()
    /// Estimated liquidation price.
    public var liquidationPx: String?
    /// Margin currently allocated to this position.
    public var marginUsed: String = ""
    /// Notional value of the position.
    public var positionValue: String = ""
    /// Return on equity as a decimal string.
    public var returnOnEquity: String = ""
    /// Signed size of the position (positive = long, negative = short).
    public var szi: String = ""
    /// Unrealized profit and loss.
    public var unrealizedPnl: String = ""
    public init() {}
}

/// Wraps a position together with its margin type (cross or isolated).
public struct HLPositionEntry: SmartCodableX {
    /// The position details.
    public var position: HLPosition = HLPosition()
    /// Margin type: "crossMargin" or "isolated".
    public var type: String = ""
    public init() {}
}

/// Leverage configuration for a position.
public struct HLLeverage: SmartCodableX {
    /// Leverage type: "cross" or "isolated".
    public var type: String = ""
    /// Leverage value (e.g. 5 for 5×).
    public var value: Int = 0
    /// Raw USD value used for isolated margin calculation.
    public var rawUsd: String?
    public init() {}
}

/// Aggregate margin summary for a user's account.
public struct HLMarginSummary: SmartCodableX {
    /// Total account value in USD.
    public var accountValue: String = ""
    /// Total margin in use across all positions.
    public var totalMarginUsed: String = ""
    /// Total notional position size.
    public var totalNtlPos: String = ""
    /// Total raw USD from isolated positions.
    public var totalRawUsd: String?
    public init() {}
}

/// Full state of a user's account, including positions and margin info.
public struct HLUserState: SmartCodableX {
    /// All open position entries (both cross and isolated margin).
    public var assetPositions: [HLPositionEntry] = []
    /// Cross-margin summary (aggregate across all cross positions).
    public var crossMarginSummary: HLMarginSummary = HLMarginSummary()
    /// Margin summary for the account.
    public var marginSummary: HLMarginSummary = HLMarginSummary()
    /// Amount available for withdrawal (in USD).
    public var withdrawable: String = ""
    /// Server timestamp of this state snapshot.
    public var time: Int?
    public init() {}
}

/// A single funding rate payment record.
public struct HLFundingRecord: SmartCodableX {
    /// The funding rate delta details.
    public var delta: HLFundingDelta?
    /// Timestamp of this funding event (milliseconds).
    public var time: Int = 0
    public init() {}
}

/// Details of a funding rate payment for a specific asset.
public struct HLFundingDelta: SmartCodableX {
    /// Ticker symbol for this funding payment.
    public var coin: String?
    /// Hourly funding rate at the time of payment.
    public var fundingRate: String?
    /// USDC amount paid or received.
    public var usdc: String?
    /// Signed position size at the time of payment.
    public var szi: String?
    /// Type of funding event.
    public var type: String?
    public init() {}
}

/// A single ledger update event on the user's account.
public struct HLLedgerUpdate: SmartCodableX {
    /// The ledger delta details.
    public var delta: HLLedgerDelta?
    /// Timestamp of this ledger update (milliseconds).
    public var time: Int = 0
    public init() {}
}

/// Details of a balance change in the user's ledger.
public struct HLLedgerDelta: SmartCodableX {
    /// Type of ledger event (e.g. "deposit", "withdrawal", "funding").
    public var type: String?
    /// USDC amount change (signed).
    public var usdc: String?
    public init() {}
}

/// Equity and position info for a vault the user participates in.
public struct HLVaultEquity: SmartCodableX {
    /// Vault metadata.
    public var vault: VaultInfo?
    /// Current equity in the vault (USD).
    public var equity: String?
    /// Notional position size of the vault.
    public var ntlPos: String?
    public init() {}
}

/// Basic metadata identifying a Hyperliquid vault.
public struct VaultInfo: SmartCodableX {
    /// On-chain address of the vault.
    public var vaultAddress: String?
    /// Human-readable vault name.
    public var name: String?
    public init() {}
}

/// Summary of a user's delegation status in a vault.
public struct HLDelegatorSummary: SmartCodableX {
    /// Amount currently delegated to the vault.
    public var delegated: String?
    /// Amount not delegated (available in the user's account).
    public var undelegated: String?
    /// Total amount pending withdrawal from the vault.
    public var totalPendingWithdrawal: String?
    /// Number of pending withdrawal requests.
    public var nPendingWithdrawals: Int?
    public init() {}
}

/// An agent wallet authorized to act on behalf of the user.
public struct HLAgentWallet: SmartCodableX {
    /// Display name of the agent.
    public var name: String?
    /// Ethereum address of the agent wallet.
    public var address: String?
    /// Expiration timestamp for this agent's authorization.
    public var validUntil: Int?
    public init() {}
}

/// Portfolio performance data for a specific time period.
public struct HLPortfolioPeriod {
    /// Period identifier, e.g. "30d", "90d", "allTime".
    public var period: String
    /// Historical account value over time.
    public var accountValueHistory: [(time: Int, value: Double)]
    /// Historical PnL over time.
    public var pnlHistory: [(time: Int, pnl: Double)]
    /// Total trading volume in this period (USD).
    public var volume: Double
}

/// Spot asset balances for a user's account.
public struct HLSpotState: SmartCodableX {
    /// List of spot token balances.
    public var balances: [HLSpotBalance] = []
    public init() {}
}

/// Balance of a single spot token.
public struct HLSpotBalance: SmartCodableX {
    /// Token symbol, e.g. "USDC", "PURR".
    public var coin: String = ""
    /// Total balance including held amounts.
    public var total: String = ""
    /// Amount held by open orders.
    public var hold: String = ""
    /// Notional entry value in USD.
    public var entryNtl: String = ""
    public init() {}
}

/// An open (resting) order placed by the user.
public struct HLOpenOrder: SmartCodableX {
    /// Ticker symbol for the order.
    public var coin: String = ""
    /// Limit price of the order.
    public var limitPx: String = ""
    /// Unique order identifier.
    public var oid: Int = 0
    /// Order side: "B" for buy, "S" for sell, "A" for trigger.
    public var side: String = ""
    /// Remaining size of the order.
    public var sz: String = ""
    /// Timestamp when the order was placed (milliseconds).
    public var timestamp: Int = 0
    /// Original order size at placement time.
    public var origSz: String?
    /// Order type, e.g. "limit", "trigger".
    public var orderType: String?
    /// Whether this order can only reduce an existing position.
    public var reduceOnly: Bool?
    /// Trigger price for stop/trigger orders.
    public var triggerPx: String?
    /// Time-in-force setting for the order.
    public var tif: String?
    /// Returns `true` if this is a trigger/stop order (side == "A").
    public var isTriggerOrder: Bool {
        return side == "A"
    }
    public init() {}
}

/// A fill (trade execution) record for the user.
public struct HLUserFill: SmartCodableX {
    /// Realized PnL when this fill closed a position.
    public var closedPnl: String = ""
    /// Ticker symbol for the filled asset.
    public var coin: String = ""
    /// Whether this fill was a taker order (crossed the spread).
    public var crossed: Bool = false
    /// Direction of the fill, e.g. "Open Long", "Close Short".
    public var dir: String = ""
    /// Transaction hash on L1.
    public var hash: String = ""
    /// Order ID that was filled.
    public var oid: Int = 0
    /// Fill price.
    public var px: String = ""
    /// Fill side: "B" for buy, "S" for sell.
    public var side: String = ""
    /// Position size before this fill.
    public var startPosition: String = ""
    /// Size of this fill.
    public var sz: String = ""
    /// Timestamp of the fill (milliseconds).
    public var time: Int = 0
    /// Fee charged for this fill.
    public var fee: String?
    /// Token in which the fee was charged.
    public var feeToken: String?
    public init() {}
}

/// A single OHLCV candlestick for charting.
public struct HLCandle {
    /// Opening time of the candle (milliseconds).
    public let openTime: Int
    /// Closing time of the candle (milliseconds).
    public let closeTime: Int
    /// Ticker symbol.
    public let coin: String
    /// Candle interval, e.g. "1m", "5m", "1h", "1d".
    public let interval: String
    /// Opening price.
    public let open: Double
    /// Closing price.
    public let close: Double
    /// Highest price in the period.
    public let high: Double
    /// Lowest price in the period.
    public let low: Double
    /// Trading volume in the period.
    public let volume: Double
    /// Number of trades in the period.
    public let numTrades: Int
}

/// Result returned after placing an order on Hyperliquid.
/// Contains the overall status and optional response details.
public struct HLOrderResult {
    /// Top-level status string, typically "ok" or "err".
    public let status: String
    /// Detailed response data when the order was accepted.
    public let response: HLOrderResponse?
    /// Error message when the order was rejected.
    public let error: String?

    /// Returns `true` if the order was successfully placed and all
    /// individual status entries indicate success (filled, resting, or success).
    public var isSuccess: Bool {
        guard status == "ok", error == nil else { return false }
        if let resp = response, let data = resp.data, let statuses = data.statuses {
            return statuses.allSatisfy { s in
                switch s {
                case .filled, .resting, .success: return true
                case .error: return false
                }
            }
        }
        return true
    }

    /// Returns the first error message found in the order result,
    /// either from the top-level `error` field or from individual status entries.
    public var errorMessage: String? {
        if let err = error { return err }
        guard let resp = response, let data = resp.data, let statuses = data.statuses else { return nil }
        for s in statuses {
            if case .error(let msg) = s { return msg }
        }
        return nil
    }
}

/// Wrapper for the exchange response after order placement.
public struct HLOrderResponse {
    /// Response type identifier.
    public let type: String
    /// Detailed status data for the placed order(s).
    public let data: HLOrderStatusData?
}

/// Contains a list of individual order statuses returned by the exchange.
public struct HLOrderStatusData {
    /// Per-order status entries (one per order in the batch).
    public let statuses: [HLOrderStatus]?
}

/// Individual status of a placed order.
/// Can represent a resting (open) order, a filled order, a generic success, or an error.
public enum HLOrderStatus {
    /// Order is resting (open) on the book.
    case resting(HLOrderResting)
    /// Order has been fully filled.
    case filled(HLOrderFilled)
    /// Generic success acknowledgment with a message.
    case success(String)
    /// Order placement failed with an error message.
    case error(String)
}

/// Details for an order that is resting (open) on the order book.
public struct HLOrderResting {
    /// The order ID of the resting order.
    public let oid: Int
}

/// Details for an order that has been fully filled.
public struct HLOrderFilled {
    /// Total filled size.
    public let totalSz: String
    /// Average fill price (may be nil if not yet available).
    public let avgPx: String?
    /// The order ID that was filled.
    public let oid: Int?
}

/// Details for an order that is partially filling.
public struct HLOrderFilling {
    /// The order ID being filled.
    public let oid: Int
    /// Total size being filled.
    public let totalSz: String
    /// Average fill price so far.
    public let avgPx: String?
}

/// Time-in-force options for order placement.
public enum HLTimeInForce: String {
    /// Good-til-cancelled: the order remains active until filled or cancelled.
    case gtc = "Gtc"
    /// Immediate-or-cancel: fill what can be filled immediately, cancel the rest.
    case ioc = "Ioc"
    /// Add-liquidity-only: the order will only be placed if it would add liquidity (post-only).
    case alo = "Alo"
}

/// Take-profit / stop-loss order type.
public enum HLTPSL: String {
    /// Take-profit order.
    case tp = "tp"
    /// Stop-loss order.
    case sl = "sl"
}
