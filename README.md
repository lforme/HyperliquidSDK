<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%2016%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/CocoaPods-1.8.4-red" alt="CocoaPods">
</p>

# HyperliquidSDK

English | [中文](README_zh.md)

<p align="center">
  <img src="demo.gif" alt="Demo" width="200">
</p>

A native Swift SDK for the [Hyperliquid](https://hyperliquid.xyz) decentralized perpetual exchange. It provides a complete, type-safe interface for REST API querying, WebSocket real-time streaming, EIP-712 signed trading operations, and encrypted local storage — all without relying on web3.js or any JavaScript bridge.

## Features

- **REST API** — Query market data, user state, open orders, fills, funding history, L2 order book, and OHLCV candles.
- **WebSocket Streaming** — Subscribe to real-time all-mids, L2 book, user events, order updates, and candlestick data via Starscream.
- **EIP-712 Signed Trading** — Place/cancel orders, update leverage, and close positions with full EIP-712 + phantom-agent signing on secp256k1.
- **Encrypted Local Storage** — Persistent key-value storage backed by encrypted MMKV, isolated under a dedicated mmap ID.
- **Network Usage Tracking** — Thread-safe downstream traffic counter for both HTTP and WebSocket, with throttled callbacks.
- **Structured Logging** — Centralized `HLLog` utility with level filtering, `[HLSDK]` prefix for easy console filtering, enabled by default with toggle support.
- **MsgPack Encoding** — Deterministic MessagePack encoder for action hashing, with ordered-map support for signature reproducibility.
- **CocoaPods Support** — Ready to integrate via CocoaPods with all C-library headers and build settings preconfigured.

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## Installation

### CocoaPods

Add the following to your `Podfile`:

```ruby
pod 'HyperliquidSDK', :git => 'https://github.com/lforme/HyperliquidSDK.git', :tag => '0.1.0'
```

Then run:

```bash
pod install
```

### Manual

Clone the repository and drag the `HyperliquidSDK` folder into your Xcode project. Make sure to:

1. Add `ENABLE_MODULE_RECOVERY=1` to your preprocessor macros.
2. Add the `secp256k1/include` and `secp256k1` directories to your header search paths.
3. Link against `CryptoSwift`, `Starscream`, `SmartCodable`, and `MMKV`.

## Quick Start

### 1. Create a Client

```swift
import HyperliquidSDK

let client = HyperliquidClient(isMainnet: true)
```

### 2. Connect with a Private Key

```swift
try client.connect(privateKey: "0x_your_private_key")

// Or with a separate main wallet (API key setup):
try client.connect(mainWallet: "0x_main_wallet", privateKey: "0x_signing_key")
```

### 3. Query Market Data

```swift
// Get all mid prices
let mids = try await client.getAllMids()
print("BTC mid: \(mids["BTC"] ?? "N/A")")

// Get coin metadata and asset contexts
let (meta, ctxs) = try await client.getMetaAndAssetCtxs()
for (coin, ctx) in zip(meta, ctxs) {
    print("\(coin.name): mark=\(ctx.markPx ?? "N/A") funding=\(ctx.funding ?? "N/A")")
}

// Get L2 order book
let book = try await client.getL2Snapshot(coin: "BTC")
let bids = book.levels[0]
let asks = book.levels[1]
```

### 4. Query User State

```swift
// Account state (positions, margin, withdrawable)
let state = try await client.getUserState()
for entry in state.assetPositions {
    print("\(entry.position.coin): size=\(entry.position.szi) PnL=\(entry.position.unrealizedPnl)")
}

// Open orders
let orders = try await client.getOpenOrders()
for order in orders {
    print("\(order.coin) \(order.side) sz=\(order.sz) px=\(order.limitPx)")
}

// Fill history
let fills = try await client.getUserFills()
```

### 5. Place & Cancel Orders

```swift
// Limit order (GTC)
let result = try await client.placeOrder(
    coin: "BTC",
    isBuy: true,
    sz: 0.001,
    limitPx: 100000.0,
    timeInForce: .gtc
)

// Market order (IOC with slippage)
let marketResult = try await client.placeMarketOrder(
    coin: "ETH",
    isBuy: true,
    sz: 0.1,
    slippage: 0.05
)

// Take-profit / Stop-loss trigger order
let triggerResult = try await client.placeTriggerOrder(
    coin: "BTC",
    isBuy: false,
    sz: 0.001,
    triggerPx: 95000.0,
    tpsl: .sl
)

// Cancel an order
let cancelResult = try await client.cancelOrder(coin: "BTC", oid: orderId)

// Close entire position
let closeResult = try await client.closePosition(coin: "BTC")
```

### 6. Update Leverage

```swift
let leverageResult = try await client.updateLeverage(
    coin: "BTC",
    leverage: 10,
    isCross: true
)
```

### 7. WebSocket Real-Time Data

```swift
client.ws.delegate = self
client.ws.connect()

// Subscribe to channels
client.ws.subscribeAllMids()
client.ws.subscribeL2Book(coin: "BTC")
client.ws.subscribeCandle(coin: "ETH", interval: "15m")
client.ws.subscribeUserEvents(address: walletAddress)
client.ws.subscribeOrderUpdates(address: walletAddress)

// Unsubscribe
client.ws.unsubscribeL2Book(coin: "BTC")
client.ws.unsubscribeCandle(coin: "ETH", interval: "15m")
```

Implement the delegate:

```swift
class MyWSHandler: HyperliquidWebSocketDelegate {
    func onConnected() {
        print("WebSocket connected")
    }

    func onDisconnected(error: Error?) {
        print("WebSocket disconnected: \(error?.localizedDescription ?? "clean close")")
    }

    func onMessage(data: Data) {
        // Parse the JSON message
        if let json = try? JSONSerialization.jsonObject(with: data) {
            print("WS message: \(json)")
        }
    }

    func onError(error: Error) {
        print("WebSocket error: \(error)")
    }
}
```

### 8. Local Storage

```swift
let storage = HyperliquidLocalStorage.shared

storage.setBool(true, forKey: "is_authenticated")
storage.setString("0xABC...", forKey: "wallet_address")
storage.setDouble(1.5, forKey: "leverage_btc")

let auth = storage.bool(forKey: "is_authenticated")
let wallet = storage.string(forKey: "wallet_address")
```

### 9. Network Usage Tracking

```swift
let tracker = NetworkUsageTracker.shared

tracker.onUsageUpdate = { totalBytes in
    print("Total download: \(tracker.formattedTotal())")
    print("  HTTP: \(tracker.formattedHTTP())")
    print("  WS:   \(tracker.formattedWS())")
}
```

### 10. Logging

All SDK operations are logged through `HLLog` with the `[HLSDK]` prefix for easy console filtering. Logging is enabled by default.

```swift
// Disable all SDK logs
HLLog.enabled = false

// Re-enable with level filtering (only warnings and errors)
HLLog.enabled = true
HLLog.level = .warning

// Available levels: .debug, .info, .warning, .error
HLLog.level = .debug  // Show everything (default)
```

Console output format:

```
[HLSDK] [INFO] [HyperliquidAPI.swift:post(_:_:)] POST /info body=...
[HLSDK] [ERROR] [HyperliquidInfo.swift:loadMeta()] loadMeta: unexpected format
[HLSDK] [DEBUG] [HyperliquidSigning.swift:signL1Action(action:nonce:expiresAfter:)] actionHash: 0x...
```

## Architecture

```
HyperliquidClient
├── HyperliquidInfo (REST /info queries)
│   └── HyperliquidAPI (HTTP layer)
├── HyperliquidExchange (Signed trading operations)
│   ├── HyperliquidSigning (EIP-712 + secp256k1)
│   ├── MsgPackEncoder (Deterministic serialization)
│   └── HyperliquidAPI (HTTP layer)
├── HyperliquidWebSocket (Real-time streaming)
│   └── Starscream
├── HyperliquidLocalStorage (Encrypted MMKV)
├── NetworkUsageTracker (Traffic monitoring)
└── HLLog (Structured logging)
```

## API Reference

### HyperliquidClient

| Method | Description |
|--------|-------------|
| `connect(privateKey:vaultAddress:)` | Connect with a private key |
| `connect(mainWallet:privateKey:)` | Connect with separate wallet and signing key |
| `getAllMids()` | Get all mid prices |
| `getMetaAndAssetCtxs()` | Get coin metadata and asset contexts |
| `getUserState()` | Get account state (positions, margin) |
| `getOpenOrders()` | Get open orders |
| `getUserFills()` | Get fill history |
| `getUserFillsByTime(startTime:endTime:)` | Get fills by time range |
| `getUserFunding(startTime:)` | Get funding payment records |
| `getUserNonFundingLedgerUpdates(startTime:)` | Get ledger updates |
| `getUserVaultEquities()` | Get vault equities |
| `getDelegatorSummary()` | Get staking delegator summary |
| `getSpotState()` | Get spot balances |
| `getExtraAgents()` | Get API wallet configs |
| `getPortfolio()` | Get portfolio history |
| `getL2Snapshot(coin:)` | Get L2 order book |
| `placeOrder(coin:isBuy:sz:limitPx:timeInForce:)` | Place a limit/IOC order |
| `placeMarketOrder(coin:isBuy:sz:slippage:)` | Place a market order |
| `placeTriggerOrder(coin:isBuy:sz:triggerPx:limitPx:isMarket:tpsl:reduceOnly:)` | Place TP/SL order |
| `closePosition(coin:slippage:)` | Close entire position |
| `cancelOrder(coin:oid:)` | Cancel an order |
| `updateLeverage(coin:leverage:isCross:)` | Update leverage |

### HyperliquidWebSocket

| Method | Description |
|--------|-------------|
| `connect()` | Open WebSocket connection |
| `disconnect()` | Close WebSocket connection |
| `subscribeAllMids()` | Subscribe to all mid prices |
| `subscribeL2Book(coin:nSigFigs:)` | Subscribe to L2 book |
| `subscribeCandle(coin:interval:)` | Subscribe to candlestick data |
| `subscribeUserEvents(address:)` | Subscribe to user events |
| `subscribeOrderUpdates(address:)` | Subscribe to order updates |
| `unsubscribeAllMids()` | Unsubscribe from all mids |
| `unsubscribeL2Book(coin:)` | Unsubscribe from L2 book |
| `unsubscribeCandle(coin:interval:)` | Unsubscribe from candle data |

## Error Handling

All SDK methods throw `HLError`:

```swift
do {
    let state = try await client.getUserState()
} catch HLError.signingError(let msg) {
    print("Signing error: \(msg)")
} catch HLError.httpError(let code) {
    print("HTTP error: \(code)")
} catch HLError.decodingError(let err) {
    print("Decoding error: \(err)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Dependencies

| Library | Version | Purpose |
|---------|---------|---------|
| [CryptoSwift](https://github.com/krzyzanowskim/CryptoSwift) | 1.8.4 | Keccak-256 hashing |
| [Starscream](https://github.com/daltoniam/Starscream) | 4.0.8 | WebSocket client |
| [SmartCodable](https://github.com/mqq1024/SmartCodable) | 6.0.8 | JSON deserialization |
| [MMKV](https://github.com/Tencent/MMKV) | 2.4.0 | Encrypted key-value storage |

## License

HyperliquidSDK is released under the MIT license. See [LICENSE](LICENSE) for details.

## Author

Ian.Wang — [lformus18@gmail.com](mailto:lformus18@gmail.com)

## Disclaimer

This SDK is an independent community project and is not affiliated with or endorsed by Hyperliquid. Use at your own risk. Trading perpetual contracts involves significant financial risk.
