<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%2016%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/CocoaPods-1.8.4-red" alt="CocoaPods">
</p>

# HyperliquidSDK

[English](README.md) | 中文

一个原生 Swift SDK，用于 [Hyperliquid](https://hyperliquid.xyz) 去中心化永续合约交易所。提供完整的类型安全接口，涵盖 REST API 查询、WebSocket 实时数据流、EIP-712 签名交易操作和加密本地存储——无需依赖 web3.js 或任何 JavaScript 桥接。

## 功能特性

- **REST API** — 查询市场数据、用户状态、挂单、成交记录、资金费率历史、L2 订单簿和 OHLCV K线。
- **WebSocket 实时流** — 通过 Starscream 订阅全币对中间价、L2 订单簿、用户事件、订单更新和K线数据。
- **EIP-712 签名交易** — 下单/撤单、调整杠杆、平仓，完整实现 EIP-712 + phantom-agent 签名（基于 secp256k1）。
- **加密本地存储** — 基于加密 MMKV 的持久化键值存储，使用独立 mmap ID 隔离数据。
- **网络流量追踪** — 线程安全的下行流量统计（HTTP + WebSocket），带节流回调。
- **MsgPack 编码** — 确定性 MessagePack 编码器，支持有序映射，确保签名可复现。
- **CocoaPods 支持** — 开箱即用的 CocoaPods 集成，C 库头文件和编译设置已预配置。

## 环境要求

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## 安装

### CocoaPods

在 `Podfile` 中添加：

```ruby
pod 'HyperliquidSDK', :git => 'https://github.com/lforme/HyperliquidSDK.git', :tag => '0.1.0'
```

然后执行：

```bash
pod install
```

### 手动集成

克隆仓库并将 `HyperliquidSDK` 文件夹拖入 Xcode 项目。请确保：

1. 在预处理器宏中添加 `ENABLE_MODULE_RECOVERY=1`。
2. 将 `secp256k1/include` 和 `secp256k1` 目录添加到头文件搜索路径。
3. 链接 `CryptoSwift`、`Starscream`、`SmartCodable` 和 `MMKV`。

## 快速开始

### 1. 创建客户端

```swift
import HyperliquidSDK

let client = HyperliquidClient(isMainnet: true)
```

### 2. 使用私钥连接

```swift
try client.connect(privateKey: "0x_你的私钥")

// 或使用独立的主钱包（API 密钥模式）：
try client.connect(mainWallet: "0x_主钱包地址", privateKey: "0x_签名密钥")
```

### 3. 查询市场数据

```swift
// 获取所有中间价
let mids = try await client.getAllMids()
print("BTC 中间价: \(mids["BTC"] ?? "N/A")")

// 获取币种元数据和资产上下文
let (meta, ctxs) = try await client.getMetaAndAssetCtxs()
for (coin, ctx) in zip(meta, ctxs) {
    print("\(coin.name): 标记价=\(ctx.markPx ?? "N/A") 资金费率=\(ctx.funding ?? "N/A")")
}

// 获取 L2 订单簿
let book = try await client.getL2Snapshot(coin: "BTC")
let bids = book.levels[0]  // 买单
let asks = book.levels[1]  // 卖单
```

### 4. 查询用户状态

```swift
// 账户状态（持仓、保证金、可提取金额）
let state = try await client.getUserState()
for entry in state.assetPositions {
    print("\(entry.position.coin): 仓位=\(entry.position.szi) 未实现盈亏=\(entry.position.unrealizedPnl)")
}

// 挂单列表
let orders = try await client.getOpenOrders()
for order in orders {
    print("\(order.coin) \(order.side) 数量=\(order.sz) 价格=\(order.limitPx)")
}

// 成交记录
let fills = try await client.getUserFills()
```

### 5. 下单与撤单

```swift
// 限价单（GTC）
let result = try await client.placeOrder(
    coin: "BTC",
    isBuy: true,
    sz: 0.001,
    limitPx: 100000.0,
    timeInForce: .gtc
)

// 市价单（IOC + 滑点保护）
let marketResult = try await client.placeMarketOrder(
    coin: "ETH",
    isBuy: true,
    sz: 0.1,
    slippage: 0.05
)

// 止盈/止损触发单
let triggerResult = try await client.placeTriggerOrder(
    coin: "BTC",
    isBuy: false,
    sz: 0.001,
    triggerPx: 95000.0,
    tpsl: .sl
)

// 撤单
let cancelResult = try await client.cancelOrder(coin: "BTC", oid: orderId)

// 全部平仓
let closeResult = try await client.closePosition(coin: "BTC")
```

### 6. 调整杠杆

```swift
let leverageResult = try await client.updateLeverage(
    coin: "BTC",
    leverage: 10,
    isCross: true  // 全仓模式
)
```

### 7. WebSocket 实时数据

```swift
client.ws.delegate = self
client.ws.connect()

// 订阅频道
client.ws.subscribeAllMids()
client.ws.subscribeL2Book(coin: "BTC")
client.ws.subscribeCandle(coin: "ETH", interval: "15m")
client.ws.subscribeUserEvents(address: walletAddress)
client.ws.subscribeOrderUpdates(address: walletAddress)

// 取消订阅
client.ws.unsubscribeL2Book(coin: "BTC")
client.ws.unsubscribeCandle(coin: "ETH", interval: "15m")
```

实现代理方法：

```swift
class MyWSHandler: HyperliquidWebSocketDelegate {
    func onConnected() {
        print("WebSocket 已连接")
    }

    func onDisconnected(error: Error?) {
        print("WebSocket 已断开: \(error?.localizedDescription ?? "正常关闭")")
    }

    func onMessage(data: Data) {
        if let json = try? JSONSerialization.jsonObject(with: data) {
            print("WS 消息: \(json)")
        }
    }

    func onError(error: Error) {
        print("WebSocket 错误: \(error)")
    }
}
```

### 8. 本地存储

```swift
let storage = HyperliquidLocalStorage.shared

storage.setBool(true, forKey: "is_authenticated")
storage.setString("0xABC...", forKey: "wallet_address")
storage.setDouble(1.5, forKey: "leverage_btc")

let auth = storage.bool(forKey: "is_authenticated")
let wallet = storage.string(forKey: "wallet_address")
```

### 9. 网络流量追踪

```swift
let tracker = NetworkUsageTracker.shared

tracker.onUsageUpdate = { totalBytes in
    print("总下载: \(tracker.formattedTotal())")
    print("  HTTP: \(tracker.formattedHTTP())")
    print("  WS:   \(tracker.formattedWS())")
}
```

## 架构

```
HyperliquidClient
├── HyperliquidInfo (REST /info 查询)
│   └── HyperliquidAPI (HTTP 层)
├── HyperliquidExchange (签名交易操作)
│   ├── HyperliquidSigning (EIP-712 + secp256k1)
│   ├── MsgPackEncoder (确定性序列化)
│   └── HyperliquidAPI (HTTP 层)
├── HyperliquidWebSocket (实时数据流)
│   └── Starscream
├── HyperliquidLocalStorage (加密 MMKV)
└── NetworkUsageTracker (流量监控)
```

## API 参考

### HyperliquidClient

| 方法 | 说明 |
|------|------|
| `connect(privateKey:vaultAddress:)` | 使用私钥连接 |
| `connect(mainWallet:privateKey:)` | 使用独立钱包和签名密钥连接 |
| `getAllMids()` | 获取所有中间价 |
| `getMetaAndAssetCtxs()` | 获取币种元数据和资产上下文 |
| `getUserState()` | 获取账户状态（持仓、保证金） |
| `getOpenOrders()` | 获取挂单列表 |
| `getUserFills()` | 获取成交记录 |
| `getUserFillsByTime(startTime:endTime:)` | 按时间范围获取成交记录 |
| `getUserFunding(startTime:)` | 获取资金费率支付记录 |
| `getUserNonFundingLedgerUpdates(startTime:)` | 获取账本更新 |
| `getUserVaultEquities()` | 获取金库权益 |
| `getDelegatorSummary()` | 获取质押委托摘要 |
| `getSpotState()` | 获取现货余额 |
| `getExtraAgents()` | 获取 API 钱包配置 |
| `getPortfolio()` | 获取投资组合历史 |
| `getL2Snapshot(coin:)` | 获取 L2 订单簿 |
| `placeOrder(coin:isBuy:sz:limitPx:timeInForce:)` | 下限价/IOC 单 |
| `placeMarketOrder(coin:isBuy:sz:slippage:)` | 下市价单 |
| `placeTriggerOrder(coin:isBuy:sz:triggerPx:limitPx:isMarket:tpsl:reduceOnly:)` | 下止盈/止损单 |
| `closePosition(coin:slippage:)` | 全部平仓 |
| `cancelOrder(coin:oid:)` | 撤单 |
| `updateLeverage(coin:leverage:isCross:)` | 调整杠杆 |

### HyperliquidWebSocket

| 方法 | 说明 |
|------|------|
| `connect()` | 建立 WebSocket 连接 |
| `disconnect()` | 断开 WebSocket 连接 |
| `subscribeAllMids()` | 订阅全币对中间价 |
| `subscribeL2Book(coin:nSigFigs:)` | 订阅 L2 订单簿 |
| `subscribeCandle(coin:interval:)` | 订阅K线数据 |
| `subscribeUserEvents(address:)` | 订阅用户事件 |
| `subscribeOrderUpdates(address:)` | 订阅订单更新 |
| `unsubscribeAllMids()` | 取消订阅全币对中间价 |
| `unsubscribeL2Book(coin:)` | 取消订阅 L2 订单簿 |
| `unsubscribeCandle(coin:interval:)` | 取消订阅K线数据 |

## 错误处理

所有 SDK 方法均抛出 `HLError`：

```swift
do {
    let state = try await client.getUserState()
} catch HLError.signingError(let msg) {
    print("签名错误: \(msg)")
} catch HLError.httpError(let code) {
    print("HTTP 错误: \(code)")
} catch HLError.decodingError(let err) {
    print("解码错误: \(err)")
} catch {
    print("未知错误: \(error)")
}
```

## 依赖

| 库 | 版本 | 用途 |
|----|------|------|
| [CryptoSwift](https://github.com/krzyzanowskim/CryptoSwift) | 1.8.4 | Keccak-256 哈希 |
| [Starscream](https://github.com/daltoniam/Starscream) | 4.0.8 | WebSocket 客户端 |
| [SmartCodable](https://github.com/mqq1024/SmartCodable) | 6.0.8 | JSON 反序列化 |
| [MMKV](https://github.com/Tencent/MMKV) | 2.4.0 | 加密键值存储 |

## 许可证

HyperliquidSDK 基于 MIT 许可证发布。详见 [LICENSE](LICENSE)。

## 作者

Ian.Wang — [lformus18@gmail.com](mailto:lformus18@gmail.com)

## 免责声明

本 SDK 为独立社区项目，与 Hyperliquid 官方无关。使用风险自负。永续合约交易涉及重大财务风险。
