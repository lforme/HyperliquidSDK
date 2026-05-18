//
//  NetworkUsageTracker.swift
//  SuperHyper
//
//  Created by Ian.Wang on 2026/5/18.
//  Copyright © 2026 Ian.Wang. All rights reserved.
//

import Foundation

/// Tracks downstream network traffic from both HTTP and WebSocket connections.
///
/// Uses a thread-safe design with `NSLock` to protect atomic counters, and a
/// throttled callback mechanism that fires `onUsageUpdate` at most once per second
/// to avoid overwhelming the UI with rapid updates.
///
/// Usage:
/// ```swift
/// NetworkUsageTracker.shared.onUsageUpdate = { totalBytes in
///     print("Total: \(totalBytes) bytes")
/// }
/// ```
public class NetworkUsageTracker {
    /// Shared singleton instance.
    public static let shared = NetworkUsageTracker()

    /// Total bytes received across all sources.
    private var totalBytes: Int64 = 0
    /// Bytes received via HTTP responses.
    private var httpBytes: Int64 = 0
    /// Bytes received via WebSocket messages.
    private var wsBytes: Int64 = 0
    /// Lock for thread-safe access to counters and scheduling state.
    private let lock = NSLock()

    /// Callback invoked when network usage is updated.
    /// Throttled to fire at most once per `minNotifyInterval` (1 second).
    /// Always called on the main thread.
    public var onUsageUpdate: ((Int64) -> Void)?

    /// Timestamp of the last callback invocation.
    private var lastNotifyTime: CFAbsoluteTime = 0
    /// Pending delayed notification work item (if within the throttle window).
    private var pendingNotify: DispatchWorkItem?

    /// Minimum interval between consecutive callback invocations (in seconds).
    private let minNotifyInterval: Double = 1.0

    private init() {}

    /// Records bytes received from an HTTP response.
    ///
    /// Updates both the HTTP-specific and total counters, then schedules a
    /// throttled notification to `onUsageUpdate`.
    /// - Parameter count: Number of bytes received.
    public func addHTTPBytes(_ count: Int) {
        lock.lock()
        httpBytes += Int64(count)
        totalBytes += Int64(count)
        let current = totalBytes
        lock.unlock()
        scheduleNotify(current)
    }

    /// Records bytes received from a WebSocket message.
    ///
    /// Updates both the WebSocket-specific and total counters, then schedules a
    /// throttled notification to `onUsageUpdate`.
    /// - Parameter count: Number of bytes received.
    public func addWSBytes(_ count: Int) {
        lock.lock()
        wsBytes += Int64(count)
        totalBytes += Int64(count)
        let current = totalBytes
        lock.unlock()
        scheduleNotify(current)
    }

    /// Returns the total bytes received across all sources (thread-safe).
    public func getTotalBytes() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return totalBytes
    }

    /// Returns the total bytes received via HTTP (thread-safe).
    public func getHTTPBytes() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return httpBytes
    }

    /// Returns the total bytes received via WebSocket (thread-safe).
    public func getWSBytes() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return wsBytes
    }

    /// Resets all byte counters and cancels any pending notifications.
    public func reset() {
        lock.lock()
        totalBytes = 0
        httpBytes = 0
        wsBytes = 0
        lock.unlock()
        lock.lock()
        pendingNotify?.cancel()
        pendingNotify = nil
        lastNotifyTime = 0
        lock.unlock()
    }

    /// Returns a human-readable string for total bytes (e.g. "1.50 MB").
    public func formattedTotal() -> String {
        formatBytes(getTotalBytes())
    }

    /// Returns a human-readable string for HTTP bytes (e.g. "512.0 KB").
    public func formattedHTTP() -> String {
        formatBytes(getHTTPBytes())
    }

    /// Returns a human-readable string for WebSocket bytes (e.g. "256 B").
    public func formattedWS() -> String {
        formatBytes(getWSBytes())
    }

    /// Formats a byte count into a human-readable string with appropriate units.
    /// Uses B, KB, MB, or GB depending on magnitude.
    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
        } else {
            return String(format: "%.2f GB", Double(bytes) / (1024.0 * 1024.0 * 1024.0))
        }
    }

    /// Schedules a throttled notification to `onUsageUpdate`.
    ///
    /// If enough time has elapsed since the last notification (≥ `minNotifyInterval`),
    /// the callback fires immediately. Otherwise, a delayed dispatch is scheduled
    /// for the remaining throttle duration, replacing any previously pending notification.
    private func scheduleNotify(_ current: Int64) {
        lock.lock()
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastNotifyTime

        if elapsed >= minNotifyInterval {
            lastNotifyTime = now
            pendingNotify?.cancel()
            pendingNotify = nil
            lock.unlock()
            fireNotify(current)
        } else {
            pendingNotify?.cancel()
            let delay = minNotifyInterval - elapsed
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.lastNotifyTime = CFAbsoluteTimeGetCurrent()
                self.lock.unlock()
                self.fireNotify(self.getTotalBytes())
            }
            pendingNotify = item
            lock.unlock()
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    /// Invokes the `onUsageUpdate` callback on the main thread.
    private func fireNotify(_ current: Int64) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onUsageUpdate?(current)
        }
    }
}
