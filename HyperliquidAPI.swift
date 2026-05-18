//
//  HyperliquidAPI.swift
//  SuperHyper
//
//  Created by Ian.Wang on 2026/5/18.
//  Copyright © 2026 Ian.Wang. All rights reserved.
//

import Foundation
import CryptoSwift
import SmartCodable

/// Base HTTP API layer for communicating with the Hyperliquid REST endpoints.
///
/// This class provides three POST variants:
/// - `post<T>`: Decodes the response into a `SmartCodableX`-conforming type.
/// - `postOrderResult`: Parses order-specific responses with rich status information (filled, resting, error).
/// - `postRaw`: Returns the raw JSON object without any type conversion.
///
/// It also handles:
/// - Proxy configuration via `https_proxy` / `HTTPS_PROXY` environment variables.
/// - Network usage tracking through `NetworkUsageTracker`.
/// - Request/response logging for debugging.
public class HyperliquidAPI {

    /// The base URL for all API requests (e.g. `https://api.hyperliquid.xyz`).
    let baseURL: String

    /// HTTP request timeout in seconds.
    let timeout: TimeInterval

    /// The `URLSession` used for all network requests, configured with proxy and timeout settings.
    let session: URLSession

    /// Creates an API instance with the given base URL and timeout.
    ///
    /// If the `https_proxy` or `HTTPS_PROXY` environment variable is set, the session
    /// is configured to route traffic through the specified HTTP/HTTPS proxy.
    ///
    /// - Parameters:
    ///   - baseURL: The Hyperliquid API base URL.
    ///   - timeout: HTTP request timeout in seconds (default 30).
    public init(baseURL: String = HLConstants.mainnetAPIURL, timeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.timeout = timeout

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = true

        // Configure HTTP/HTTPS proxy from environment variables if available
        if let proxyHost = ProcessInfo.processInfo.environment["https_proxy"] ??
            ProcessInfo.processInfo.environment["HTTPS_PROXY"],
           let proxyURL = URL(string: proxyHost) {
            let host = proxyURL.host ?? "127.0.0.1"
            let port = proxyURL.port ?? 8118
            config.connectionProxyDictionary = [
                kCFStreamPropertyHTTPProxy as String: [
                    kCFStreamPropertyHTTPProxyHost as String: host,
                    kCFStreamPropertyHTTPProxyPort as String: port
                ],
                "HTTPSProxy": [
                    kCFStreamPropertyHTTPProxyHost as String: host,
                    kCFStreamPropertyHTTPProxyPort as String: port
                ]
            ]
            print("[HLAPI] Using proxy: \(host):\(port)")
        }

        self.session = URLSession(configuration: config)
    }

    /// Sends a POST request and decodes the response into a `SmartCodableX`-conforming type.
    ///
    /// This is the primary method for typed API responses. The response data is deserialized
    /// using SmartCodable's `deserialize(from:)` and tracked by `NetworkUsageTracker`.
    ///
    /// - Parameters:
    ///   - path: The API path (e.g. `"/info"`).
    ///   - body: The request body as a JSON-serializable dictionary.
    /// - Returns: A decoded instance of type `T`.
    /// - Throws: `HLError.invalidURL` if the URL is malformed,
    ///           `HLError.httpError` for non-200 status codes,
    ///           `HLError.decodingError` if deserialization fails.
    func post<T: SmartCodableX>(_ path: String, _ body: Any) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw HLError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = jsonData

        print("[HLAPI] POST \(path) body=\(String(data: jsonData, encoding: .utf8)?.prefix(300) ?? "nil")")

        let (data, response) = try await session.data(for: request)
        NetworkUsageTracker.shared.addHTTPBytes(data.count)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HLError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let bodyStr = String(data: data.prefix(500), encoding: .utf8) ?? ""
            print("[HLAPI] HTTP \(httpResponse.statusCode) for \(path): \(bodyStr)")
            throw HLError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            guard let result = T.deserialize(from: data) else {
                throw HLError.decodingError(NSError(domain: "HLAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "SmartCodable deserialize returned nil for \(T.self)"]))
            }
            print("[HLAPI] Decoded \(T.self) successfully, \(data.count) bytes")
            return result
        } catch let error as HLError {
            throw error
        } catch {
            let rawStr = String(data: data.prefix(1000), encoding: .utf8) ?? "nil"
            print("[HLAPI] Decode error for \(T.self): \(error.localizedDescription)")
            print("[HLAPI] Raw response (\(data.count) bytes): \(rawStr)")
            throw HLError.decodingError(error)
        }
    }

    /// Sends a POST request and parses the response as an `HLOrderResult`.
    ///
    /// Unlike `post<T>`, this method performs custom JSON parsing to extract the
    /// order status hierarchy (filled/resting/success/error) from the response.
    /// Used exclusively by exchange operations (place order, cancel, update leverage).
    ///
    /// - Parameters:
    ///   - path: The API path (typically `"/exchange"`).
    ///   - body: The request body including action, nonce, and signature.
    /// - Returns: A parsed `HLOrderResult` with status, response details, and optional error.
    /// - Throws: `HLError.invalidURL`, `HLError.httpError`, or `HLError.decodingError`.
    func postOrderResult(_ path: String, _ body: Any) async throws -> HLOrderResult {
        guard let url = URL(string: baseURL + path) else {
            throw HLError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = jsonData

        print("[HLAPI] POST order \(path) body=\(String(data: jsonData, encoding: .utf8)?.prefix(300) ?? "nil")")

        let (data, response) = try await session.data(for: request)
        NetworkUsageTracker.shared.addHTTPBytes(data.count)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HLError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let bodyStr = String(data: data.prefix(500), encoding: .utf8) ?? ""
            print("[HLAPI] HTTP \(httpResponse.statusCode) for \(path): \(bodyStr)")
            throw HLError.httpError(statusCode: httpResponse.statusCode)
        }

        let rawStr = String(data: data.prefix(2000), encoding: .utf8) ?? ""
        print("[HLAPI] Order response (\(data.count) bytes): \(rawStr)")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HLError.decodingError(NSError(domain: "HLAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"]))
        }

        let result = parseOrderResult(json)
        print("[HLAPI] Parsed result: status=\(result.status), error=\(result.error ?? "nil"), isSuccess=\(result.isSuccess)")
        if let resp = result.response, let dataObj = resp.data, let statuses = dataObj.statuses {
            for (i, s) in statuses.enumerated() {
                switch s {
                case .filled(let f): print("[HLAPI]   status[\(i)]: filled totalSz=\(f.totalSz) avgPx=\(f.avgPx ?? "nil")")
                case .resting(let r): print("[HLAPI]   status[\(i)]: resting oid=\(r.oid)")
                case .success(let msg): print("[HLAPI]   status[\(i)]: success=\(msg)")
                case .error(let e): print("[HLAPI]   status[\(i)]: error=\(e)")
                }
            }
        }
        return result
    }

    /// Parses a raw JSON dictionary into an `HLOrderResult`.
    ///
    /// Handles the Hyperliquid-specific response format where errors may appear as
    /// top-level keys alongside `"status"`, and order statuses are nested under
    /// `response.data.statuses` as either `filled`, `resting`, `error`, or `success`.
    private func parseOrderResult(_ json: [String: Any]) -> HLOrderResult {
        let status = json["status"] as? String ?? ""
        var error = json["error"] as? String

        // Extract error from non-standard keys when status is "err"
        if status == "err" && error == nil {
            for (key, value) in json {
                if key != "status" && key != "response" {
                    if let strVal = value as? String {
                        error = "\(key): \(strVal)"
                    } else if let dictVal = value as? [String: Any] {
                        error = "\(key): \(dictVal)"
                    }
                }
            }
            if error == nil {
                error = "Unknown error: \(json)"
            }
        }

        var response: HLOrderResponse?
        if let respDict = json["response"] as? [String: Any] {
            let type = respDict["type"] as? String ?? ""
            var data: HLOrderStatusData?
            if let dataDict = respDict["data"] as? [String: Any],
               let statusesRaw = dataDict["statuses"] as? [Any] {
                var statuses: [HLOrderStatus] = []
                for item in statusesRaw {
                    if let dict = item as? [String: Any] {
                        if let restingDict = dict["resting"] as? [String: Any],
                           let oid = restingDict["oid"] as? Int {
                            statuses.append(.resting(HLOrderResting(oid: oid)))
                        } else if let filledDict = dict["filled"] as? [String: Any],
                                  let totalSz = filledDict["totalSz"] as? String {
                            let avgPx = filledDict["avgPx"] as? String
                            let oid = filledDict["oid"] as? Int
                            statuses.append(.filled(HLOrderFilled(totalSz: totalSz, avgPx: avgPx, oid: oid)))
                        } else if let errMsg = dict["error"] as? String {
                            statuses.append(.error(errMsg))
                        }
                    } else if let strVal = item as? String {
                        if strVal == "success" {
                            statuses.append(.success(strVal))
                        } else {
                            statuses.append(.error(strVal))
                        }
                    }
                }
                data = HLOrderStatusData(statuses: statuses.isEmpty ? nil : statuses)
            }
            response = HLOrderResponse(type: type, data: data)
        }

        return HLOrderResult(status: status, response: response, error: error)
    }

    /// Sends a POST request and returns the raw JSON response without type conversion.
    ///
    /// Use this when the response structure is dynamic or does not map cleanly to a
    /// `SmartCodableX`-conforming type (e.g. `allMids`, `candleSnapshot`, `portfolio`).
    ///
    /// - Parameters:
    ///   - path: The API path (e.g. `"/info"`).
    ///   - body: The request body as a JSON-serializable dictionary.
    /// - Returns: The deserialized JSON object (array, dictionary, or primitive).
    /// - Throws: `HLError.invalidURL`, `HLError.httpError`, or JSON serialization errors.
    func postRaw(_ path: String, _ body: Any) async throws -> Any {
        guard let url = URL(string: baseURL + path) else {
            throw HLError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = jsonData

        print("[HLAPI] POST raw \(path) body=\(String(data: jsonData, encoding: .utf8)?.prefix(300) ?? "nil")")

        let (data, response) = try await session.data(for: request)
        NetworkUsageTracker.shared.addHTTPBytes(data.count)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HLError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let bodyStr = String(data: data.prefix(500), encoding: .utf8) ?? ""
            print("[HLAPI] HTTP \(httpResponse.statusCode) for \(path): \(bodyStr)")
            throw HLError.httpError(statusCode: httpResponse.statusCode)
        }

        let rawStr = String(data: data.prefix(500), encoding: .utf8) ?? ""
        print("[HLAPI] Raw response (\(data.count) bytes): \(rawStr)")

        return try JSONSerialization.jsonObject(with: data)
    }
}
