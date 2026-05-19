//
//  HyperliquidWebSocket.swift
//  SuperHyper
//
//  Created by Ian.Wang on 2026/5/18.
//  Copyright © 2026 Ian.Wang. All rights reserved.
//

import Foundation
import Starscream

/// Delegate protocol for receiving WebSocket connection events and messages.
///
/// Implement this protocol to handle real-time data from the Hyperliquid WebSocket API.
/// All methods are called on the main queue.
public protocol HyperliquidWebSocketDelegate: AnyObject {

    /// Called when the WebSocket connection is established.
    func onConnected()

    /// Called when the WebSocket connection is closed.
    ///
    /// - Parameter error: An error describing the disconnection reason, or `nil` for a clean close.
    func onDisconnected(error: Error?)

    /// Called when a WebSocket message is received.
    ///
    /// - Parameter data: The raw message data.
    func onMessage(data: Data)

    /// Called when a WebSocket error occurs.
    ///
    /// - Parameter error: The error that occurred.
    func onError(error: Error)
}

/// WebSocket client for the Hyperliquid real-time streaming API.
///
/// Uses the Starscream library for WebSocket communication. Supports subscribing
/// and unsubscribing to various data channels:
/// - **allMids**: All mid-price updates.
/// - **l2Book**: L2 order book snapshots.
/// - **userEvents**: User-specific events (fills, etc.).
/// - **orderUpdates**: Real-time order status changes.
/// - **candle**: OHLCV candlestick data.
///
/// Usage:
/// ```swift
/// let ws = HyperliquidWebSocket()
/// ws.delegate = self
/// ws.connect()
/// ws.subscribeL2Book(coin: "BTC")
/// ```
public class HyperliquidWebSocket {

    /// The underlying Starscream WebSocket instance.
    private(set) var socket: WebSocket?

    /// The WebSocket server URL.
    private let baseURL: String

    /// The delegate to receive connection and message events.
    weak var delegate: HyperliquidWebSocketDelegate?

    /// Creates a WebSocket client with the given URL.
    ///
    /// - Parameters:
    ///   - baseURL: The WebSocket server URL (e.g. `wss://api.hyperliquid.xyz/ws`).
    ///   - delegate: An optional delegate to receive events immediately.
    public init(baseURL: String = HLConstants.mainnetWSURL, delegate: HyperliquidWebSocketDelegate? = nil) {
        self.baseURL = baseURL
        self.delegate = delegate
    }

    /// Opens the WebSocket connection.
    ///
    /// If a connection already exists, it is replaced. The `onConnected` delegate
    /// method is called once the handshake completes.
    public func connect() {
        guard let url = URL(string: baseURL) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
        HLLog.info("Connecting to \(baseURL)")
    }

    /// Closes the WebSocket connection.
    public func disconnect() {
        socket?.disconnect()
    }

    /// Subscribes to the `allMids` channel for real-time mid-price updates across all coins.
    public func subscribeAllMids() {
        let payload: [String: Any] = ["method": "subscribe", "subscription": ["type": "allMids"]]
        sendSubscription(payload)
        HLLog.info("Subscribe allMids")
    }

    /// Subscribes to the `l2Book` channel for real-time L2 order book updates.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol (e.g. "BTC").
    ///   - nSigFigs: Optional number of significant figures for price levels.
    public func subscribeL2Book(coin: String, nSigFigs: Int? = nil) {
        var subscription: [String: Any] = ["type": "l2Book", "coin": coin]
        if let nSigFigs = nSigFigs {
            subscription["nSigFigs"] = nSigFigs
        }
        let payload: [String: Any] = ["method": "subscribe", "subscription": subscription]
        sendSubscription(payload)
        HLLog.info("Subscribe l2Book coin=\(coin)")
    }

    /// Subscribes to the `userEvents` channel for real-time user-specific events.
    ///
    /// - Parameter address: The user's Ethereum address.
    public func subscribeUserEvents(address: String) {
        let payload: [String: Any] = ["method": "subscribe", "subscription": ["type": "userEvents", "user": address]]
        sendSubscription(payload)
        HLLog.info("Subscribe userEvents address=\(address)")
    }

    /// Subscribes to the `orderUpdates` channel for real-time order status changes.
    ///
    /// - Parameter address: The user's Ethereum address.
    public func subscribeOrderUpdates(address: String) {
        let payload: [String: Any] = ["method": "subscribe", "subscription": ["type": "orderUpdates", "user": address]]
        sendSubscription(payload)
        HLLog.info("Subscribe orderUpdates address=\(address)")
    }

    /// Subscribes to the `candle` channel for real-time OHLCV candlestick updates.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol (e.g. "BTC").
    ///   - interval: Candle interval (e.g. "1m", "5m", "1h"). Default is "1m".
    public func subscribeCandle(coin: String, interval: String = "1m") {
        let payload: [String: Any] = [
            "method": "subscribe",
            "subscription": ["type": "candle", "coin": coin, "interval": interval]
        ]
        sendSubscription(payload)
    }

    /// Unsubscribes from the `allMids` channel.
    public func unsubscribeAllMids() {
        sendSubscription(["method": "unsubscribe", "subscription": ["type": "allMids"]])
    }

    /// Unsubscribes from the `l2Book` channel for a specific coin.
    ///
    /// - Parameter coin: The coin symbol to unsubscribe from.
    public func unsubscribeL2Book(coin: String) {
        sendSubscription([
            "method": "unsubscribe",
            "subscription": ["type": "l2Book", "coin": coin]
        ])
    }

    /// Unsubscribes from the `candle` channel for a specific coin and interval.
    ///
    /// - Parameters:
    ///   - coin: The coin symbol to unsubscribe from.
    ///   - interval: The candle interval (default "1m").
    public func unsubscribeCandle(coin: String, interval: String = "1m") {
        sendSubscription([
            "method": "unsubscribe",
            "subscription": ["type": "candle", "coin": coin, "interval": interval]
        ])
    }

    /// Serializes a subscription payload to JSON and sends it over the WebSocket.
    ///
    /// - Parameter payload: The subscription/unsubscription dictionary to send.
    private func sendSubscription(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else { return }
        socket?.write(string: string)
    }
}

// MARK: - WebSocketDelegate

extension HyperliquidWebSocket: WebSocketDelegate {

    /// Handles WebSocket events from Starscream and forwards them to the delegate.
    ///
    /// Tracks network usage for both text and binary messages via `NetworkUsageTracker`.
    public func didReceive(event: Starscream.WebSocketEvent, client: Starscream.WebSocketClient) {
        switch event {
        case .connected:
            HLLog.info("Connected!")
            delegate?.onConnected()
        case .disconnected(let reason, let code):
            HLLog.warning("Disconnected code=\(code) reason=\(reason)")
            let error = NSError(domain: "HyperliquidWS", code: Int(code), userInfo: [NSLocalizedDescriptionKey: reason])
            delegate?.onDisconnected(error: error)
        case .text(let string):
            if let data = string.data(using: .utf8) {
                NetworkUsageTracker.shared.addWSBytes(data.count)
                delegate?.onMessage(data: data)
            }
        case .binary(let data):
            NetworkUsageTracker.shared.addWSBytes(data.count)
            delegate?.onMessage(data: data)
        case .error(let error):
            HLLog.error("Error: \(error?.localizedDescription ?? "nil")")
            delegate?.onError(error: error ?? NSError(domain: "HyperliquidWS", code: -1, userInfo: nil))
        case .ping, .pong, .viabilityChanged, .reconnectSuggested:
            break
        case .cancelled:
            delegate?.onDisconnected(error: nil)
        default:
            break
        }
    }
}
