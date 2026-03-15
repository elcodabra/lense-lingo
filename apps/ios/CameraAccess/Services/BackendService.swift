/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// BackendService.swift
//
// WebSocket client for LensLingo backend using Socket.IO protocol.
// Replaces direct Gemini/ChatGPT API calls — all AI processing happens on the backend.
//

import Foundation
import UIKit

class BackendService: NSObject {
  static let shared = BackendService()

  // MARK: - Types

  struct AIResponse {
    let text: String
    let source: String   // "gemini" or "chatgpt"
    let durationMs: Int
  }

  enum BackendError: LocalizedError {
    case notConnected
    case noBackendURL
    case timeout
    case serverError(String)
    case invalidResponse

    var errorDescription: String? {
      switch self {
      case .notConnected:    return "Not connected to backend server."
      case .noBackendURL:    return "BACKEND_URL not configured in Info.plist."
      case .timeout:         return "Backend request timed out."
      case .serverError(let msg): return "Backend error: \(msg)"
      case .invalidResponse: return "Invalid response from backend."
      }
    }
  }

  // MARK: - Properties

  private let backendURL: String
  private var webSocketTask: URLSessionWebSocketTask?
  private var urlSession: URLSession!
  private var sid: String?
  private var pingTimer: Timer?
  private var pendingCallbacks: [String: (Result<[String: Any], Error>) -> Void] = [:]
  private var requestCounter = 0
  private(set) var isConnected = false
  private var reconnectAttempts = 0
  private let maxReconnectAttempts = 5

  // MARK: - Init

  override init() {
    // Get backend URL from Info.plist
    if let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
       let plist = NSDictionary(contentsOfFile: path),
       let url = plist["BACKEND_URL"] as? String, !url.isEmpty {
      self.backendURL = url
    } else {
      self.backendURL = ProcessInfo.processInfo.environment["BACKEND_URL"] ?? ""
    }
    super.init()
    self.urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
  }

  // MARK: - Connection

  func connect() {
    guard !backendURL.isEmpty else {
      print("🔴 [Backend] No BACKEND_URL configured")
      return
    }
    guard !isConnected else { return }

    // Connect directly via WebSocket (skip polling handshake)
    let wsBase = backendURL
      .replacingOccurrences(of: "http://", with: "ws://")
      .replacingOccurrences(of: "https://", with: "wss://")

    let wsURLString = "\(wsBase)/socket.io/?EIO=4&transport=websocket"
    guard let wsURL = URL(string: wsURLString) else {
      print("🔴 [Backend] Invalid WebSocket URL: \(wsURLString)")
      return
    }

    print("🔌 [Backend] Connecting WebSocket: \(wsURLString)")

    webSocketTask = urlSession.webSocketTask(with: wsURL)
    webSocketTask?.resume()
    listenForMessages()
  }

  func disconnect() {
    webSocketTask?.cancel(with: .normalClosure, reason: nil)
    webSocketTask = nil
    isConnected = false
    sid = nil
    reconnectAttempts = 0

    // Fail all pending callbacks
    let pending = pendingCallbacks
    pendingCallbacks.removeAll()
    for (_, callback) in pending {
      callback(.failure(BackendError.notConnected))
    }

    print("🔌 [Backend] Disconnected")
  }

  private func scheduleReconnect() {
    guard reconnectAttempts < maxReconnectAttempts else {
      print("🔴 [Backend] Max reconnect attempts reached")
      return
    }
    reconnectAttempts += 1
    let delay = Double(min(reconnectAttempts * 2, 10))
    print("🔄 [Backend] Reconnecting in \(delay)s (attempt \(reconnectAttempts))")
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      self?.connect()
    }
  }

  // MARK: - Socket.IO messaging

  private func send(raw text: String) {
    print("📤 [Backend] WS send: \(text.prefix(120))")
    webSocketTask?.send(.string(text)) { error in
      if let error = error {
        print("🔴 [Backend] Send error: \(error.localizedDescription)")
      }
    }
  }

  /// Emit a Socket.IO event with JSON payload
  private func emit(_ event: String, data: [String: Any]) {
    // Build the Socket.IO packet: 42["eventName",{...data...}]
    let array: [Any] = [event, data]
    guard let jsonData = try? JSONSerialization.data(withJSONObject: array),
          let jsonStr = String(data: jsonData, encoding: .utf8) else {
      print("🔴 [Backend] Failed to serialize event data")
      return
    }
    let packet = "42\(jsonStr)"
    send(raw: packet)
  }

  private func listenForMessages() {
    webSocketTask?.receive { [weak self] result in
      guard let self = self else { return }

      switch result {
      case .success(let message):
        switch message {
        case .string(let text):
          self.handleMessage(text)
        case .data(let data):
          if let text = String(data: data, encoding: .utf8) {
            self.handleMessage(text)
          }
        @unknown default:
          break
        }
        // Continue listening
        self.listenForMessages()

      case .failure(let error):
        print("🔴 [Backend] WebSocket receive error: \(error.localizedDescription)")
        self.isConnected = false
        self.scheduleReconnect()
      }
    }
  }

  private func handleMessage(_ text: String) {
    print("📥 [Backend] WS recv: \(text.prefix(200))")
    // EIO4 packet types: 0=open, 1=close, 2=ping, 3=pong, 4=message
    // Socket.IO packet types (after 4): 0=connect, 1=disconnect, 2=event, 3=ack

    // EIO4 open packet: 0{"sid":"...","upgrades":[],...}
    if text.hasPrefix("0{") {
      if let jsonData = String(text.dropFirst()).data(using: .utf8),
         let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
         let sid = json["sid"] as? String {
        self.sid = sid
        let pingInterval = (json["pingInterval"] as? Int) ?? 25000
        print("✅ [Backend] Got session ID: \(sid), pingInterval: \(pingInterval)ms")

        // Send Socket.IO connect to "/" namespace
        send(raw: "40")
      }
      return
    }

    if text == "3probe" {
      send(raw: "5")
      send(raw: "40")
      return
    }

    if text == "2" {
      // EIO ping, respond with pong
      send(raw: "3")
      return
    }

    if text == "3" {
      // EIO pong
      return
    }

    if text.hasPrefix("40") {
      // Socket.IO connect acknowledgment
      isConnected = true
      reconnectAttempts = 0
      print("✅ [Backend] Socket.IO connected to namespace")
      return
    }

    if text.hasPrefix("42") {
      // Socket.IO event message: 42["eventName", {data}]
      let jsonPart = String(text.dropFirst(2))
      guard let jsonData = jsonPart.data(using: .utf8),
            let arr = try? JSONSerialization.jsonObject(with: jsonData) as? [Any],
            let eventName = arr.first as? String else {
        return
      }

      let eventData = arr.count > 1 ? arr[1] as? [String: Any] : nil
      handleEvent(eventName, data: eventData ?? [:])
      return
    }
  }

  private func handleEvent(_ event: String, data: [String: Any]) {
    print("📥 [Backend] Event: \(event), keys: \(data.keys.sorted()), pendingCallbacks: \(pendingCallbacks.keys.sorted())")

    // Route to pending callback by requestId
    guard let requestId = data["requestId"] as? String else { return }

    switch event {
    case "generate:result":
      pendingCallbacks[requestId]?(.success(data))
      pendingCallbacks.removeValue(forKey: requestId)

    case "generate:error":
      let errorMsg = data["error"] as? String ?? "Unknown error"
      pendingCallbacks[requestId]?(.failure(BackendError.serverError(errorMsg)))
      pendingCallbacks.removeValue(forKey: requestId)

    case "check-image-needed:result":
      pendingCallbacks[requestId]?(.success(data))
      pendingCallbacks.removeValue(forKey: requestId)

    case "check-image-needed:error":
      let errorMsg = data["error"] as? String ?? "Unknown error"
      pendingCallbacks[requestId]?(.failure(BackendError.serverError(errorMsg)))
      pendingCallbacks.removeValue(forKey: requestId)

    default:
      break
    }
  }

  // MARK: - Public API

  /// Generate an AI response for the given text
  func generateResponse(for text: String, language: String = "en", image: UIImage? = nil) async throws -> AIResponse {
    guard isConnected else {
      throw BackendError.notConnected
    }

    requestCounter += 1
    let requestId = "ios-\(requestCounter)"

    var payload: [String: Any] = [
      "text": text,
      "language": language,
      "requestId": requestId,
    ]

    if let image = image, let imageData = image.jpegData(compressionQuality: 0.8) {
      payload["image"] = [
        "base64": imageData.base64EncodedString(),
        "mimeType": "image/jpeg",
      ]
    }

    print("📤 [Backend] generate: \"\(text.prefix(50))\" lang=\(language) hasImage=\(image != nil)")

    return try await withCheckedThrowingContinuation { continuation in
      // Set timeout
      let timeoutItem = DispatchWorkItem { [weak self] in
        self?.pendingCallbacks.removeValue(forKey: requestId)
        continuation.resume(throwing: BackendError.timeout)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeoutItem)

      pendingCallbacks[requestId] = { result in
        timeoutItem.cancel()
        switch result {
        case .success(let data):
          let text = data["text"] as? String ?? ""
          let source = data["source"] as? String ?? "unknown"
          let durationMs = data["durationMs"] as? Int ?? 0
          continuation.resume(returning: AIResponse(text: text, source: source, durationMs: durationMs))

        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }

      emit("generate", data: payload)
    }
  }

  /// Check if the user's request needs a camera image
  func checkImageNeeded(for text: String, language: String = "en") async throws -> Bool {
    guard isConnected else {
      throw BackendError.notConnected
    }

    requestCounter += 1
    let requestId = "ios-\(requestCounter)"

    let payload: [String: Any] = [
      "text": text,
      "language": language,
      "requestId": requestId,
    ]

    print("📤 [Backend] check-image-needed: \"\(text.prefix(50))\"")

    return try await withCheckedThrowingContinuation { continuation in
      let timeoutItem = DispatchWorkItem { [weak self] in
        self?.pendingCallbacks.removeValue(forKey: requestId)
        continuation.resume(throwing: BackendError.timeout)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeoutItem)

      pendingCallbacks[requestId] = { result in
        timeoutItem.cancel()
        switch result {
        case .success(let data):
          let needed = data["imageNeeded"] as? Bool ?? false
          continuation.resume(returning: needed)
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }

      emit("check-image-needed", data: payload)
    }
  }
}

// MARK: - URLSessionWebSocketDelegate

extension BackendService: URLSessionWebSocketDelegate {
  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                  didOpenWithProtocol protocol: String?) {
    print("✅ [Backend] WebSocket connection opened")
  }

  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                  didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    print("🔌 [Backend] WebSocket closed: \(closeCode)")
    isConnected = false
    scheduleReconnect()
  }
}
