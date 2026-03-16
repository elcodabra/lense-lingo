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
// REST client for LensLingo backend.
// All AI processing happens on the backend via REST API.
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
    case noBackendURL
    case unauthorized
    case serverError(String)
    case invalidResponse

    var errorDescription: String? {
      switch self {
      case .noBackendURL:    return "BACKEND_URL not configured in Info.plist."
      case .unauthorized:    return "Invalid API token."
      case .serverError(let msg): return "Backend error: \(msg)"
      case .invalidResponse: return "Invalid response from backend."
      }
    }
  }

  // MARK: - Properties

  private let backendURL: String
  private let apiToken: String
  private let session: URLSession

  // MARK: - Init

  override init() {
    // Get config from Info.plist
    var url = ""
    var token = ""
    if let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
       let plist = NSDictionary(contentsOfFile: path) {
      url = plist["BACKEND_URL"] as? String ?? ""
      token = plist["BACKEND_API_TOKEN"] as? String ?? ""
    }
    if url.isEmpty {
      url = ProcessInfo.processInfo.environment["BACKEND_URL"] ?? ""
    }
    if token.isEmpty {
      token = ProcessInfo.processInfo.environment["BACKEND_API_TOKEN"] ?? ""
    }
    self.backendURL = url
    self.apiToken = token

    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30
    self.session = URLSession(configuration: config)

    super.init()
  }

  // MARK: - Private helpers

  private func makeRequest(path: String, body: [String: Any]) async throws -> [String: Any] {
    guard !backendURL.isEmpty else {
      throw BackendError.noBackendURL
    }

    let urlString = backendURL.hasSuffix("/") ? "\(backendURL)\(path)" : "\(backendURL)/\(path)"
    guard let url = URL(string: urlString) else {
      throw BackendError.noBackendURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if !apiToken.isEmpty {
      request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw BackendError.invalidResponse
    }

    if httpResponse.statusCode == 401 {
      throw BackendError.unauthorized
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw BackendError.invalidResponse
    }

    if let error = json["error"] as? String {
      throw BackendError.serverError(error)
    }

    return json
  }

  // MARK: - Public API

  /// Generate an AI response for the given text
  func generateResponse(for text: String, language: String = "en", image: UIImage? = nil) async throws -> AIResponse {
    var body: [String: Any] = [
      "text": text,
      "language": language,
    ]

    if let image = image, let imageData = image.jpegData(compressionQuality: 0.8) {
      body["image"] = [
        "base64": imageData.base64EncodedString(),
        "mimeType": "image/jpeg",
      ]
    }

    print("📤 [Backend] generate: \"\(text.prefix(50))\" lang=\(language) hasImage=\(image != nil)")

    let json = try await makeRequest(path: "api/generate", body: body)

    let responseText = json["text"] as? String ?? ""
    let source = json["source"] as? String ?? "unknown"
    let durationMs = json["durationMs"] as? Int ?? 0

    return AIResponse(text: responseText, source: source, durationMs: durationMs)
  }

  /// Check if the user's request needs a camera image
  func checkImageNeeded(for text: String, language: String = "en") async throws -> Bool {
    let body: [String: Any] = [
      "text": text,
      "language": language,
    ]

    print("📤 [Backend] check-image-needed: \"\(text.prefix(50))\"")

    let json = try await makeRequest(path: "api/check-image-needed", body: body)

    return json["imageNeeded"] as? Bool ?? false
  }
}
