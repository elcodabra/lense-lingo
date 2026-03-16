/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// TranslationService.swift
//
// REST client for wordzzz.app translation API.
//

import Foundation
import AVFoundation

// MARK: - Response Models

struct TranslationExample: Decodable {
  let id: Int
  let source: String
  let target: String
}

struct TranslationResponse: Decodable {
  let text: String?
  let translations: [String]?
  let transcription: String?
  let soundUrl: String?
  let from: String?
  let to: String?
  let examples: [TranslationExample]?
  let error: String?
}

// MARK: - Translation Language

enum TranslationLanguage: String, CaseIterable, Identifiable {
  case english = "en"
  case russian = "ru"
  case spanish = "es"
  case french = "fr"
  case german = "de"
  case italian = "it"
  case portuguese = "pt"
  case chinese = "zh"
  case japanese = "ja"
  case korean = "ko"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .english: return "English"
    case .russian: return "Русский"
    case .spanish: return "Español"
    case .french: return "Français"
    case .german: return "Deutsch"
    case .italian: return "Italiano"
    case .portuguese: return "Português"
    case .chinese: return "中文"
    case .japanese: return "日本語"
    case .korean: return "한국어"
    }
  }

  var flag: String {
    switch self {
    case .english: return "🇬🇧"
    case .russian: return "🇷🇺"
    case .spanish: return "🇪🇸"
    case .french: return "🇫🇷"
    case .german: return "🇩🇪"
    case .italian: return "🇮🇹"
    case .portuguese: return "🇵🇹"
    case .chinese: return "🇨🇳"
    case .japanese: return "🇯🇵"
    case .korean: return "🇰🇷"
    }
  }

  var locale: Locale {
    switch self {
    case .english: return Locale(identifier: "en-US")
    case .russian: return Locale(identifier: "ru-RU")
    case .spanish: return Locale(identifier: "es-ES")
    case .french: return Locale(identifier: "fr-FR")
    case .german: return Locale(identifier: "de-DE")
    case .italian: return Locale(identifier: "it-IT")
    case .portuguese: return Locale(identifier: "pt-PT")
    case .chinese: return Locale(identifier: "zh-CN")
    case .japanese: return Locale(identifier: "ja-JP")
    case .korean: return Locale(identifier: "ko-KR")
    }
  }

  var speechLanguageCode: String {
    switch self {
    case .english: return "en-US"
    case .russian: return "ru-RU"
    case .spanish: return "es-ES"
    case .french: return "fr-FR"
    case .german: return "de-DE"
    case .italian: return "it-IT"
    case .portuguese: return "pt-PT"
    case .chinese: return "zh-CN"
    case .japanese: return "ja-JP"
    case .korean: return "ko-KR"
    }
  }
}

// MARK: - TranslationService

class TranslationService {
  static let shared = TranslationService()

  private let baseURL = "https://wordzzz.app/api"
  private let session: URLSession

  private init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 15
    self.session = URLSession(configuration: config)
  }

  /// Translate text using wordzzz.app API
  func translate(text: String, from source: TranslationLanguage, to target: TranslationLanguage) async throws -> TranslationResponse {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw TranslationError.emptyText
    }

    var components = URLComponents(string: baseURL)!
    components.queryItems = [
      URLQueryItem(name: "word", value: text),
      URLQueryItem(name: "from", value: source.rawValue),
      URLQueryItem(name: "to", value: target.rawValue),
    ]

    guard let url = components.url else {
      throw TranslationError.invalidURL
    }

    print("🌐 [Translation] GET \(url.absoluteString)")

    let (data, response) = try await session.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw TranslationError.invalidResponse
    }

    guard httpResponse.statusCode == 200 else {
      throw TranslationError.serverError("HTTP \(httpResponse.statusCode)")
    }

    let result = try JSONDecoder().decode(TranslationResponse.self, from: data)

    if let error = result.error {
      throw TranslationError.serverError(error)
    }

    print("✅ [Translation] Response: \(result.translations?.first ?? result.text ?? "no translation")")
    return result
  }

  /// Download and play audio from soundUrl
  func downloadAudio(from urlString: String) async throws -> Data {
    // Handle relative URLs
    let fullURL: String
    if urlString.hasPrefix("http") {
      fullURL = urlString
    } else {
      fullURL = "https://wordzzz.app\(urlString)"
    }

    guard let url = URL(string: fullURL) else {
      throw TranslationError.invalidURL
    }

    print("🔊 [Translation] Downloading audio from \(fullURL)")
    let (data, response) = try await session.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      throw TranslationError.invalidResponse
    }

    return data
  }

  enum TranslationError: LocalizedError {
    case emptyText
    case invalidURL
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
      switch self {
      case .emptyText: return "Text is empty"
      case .invalidURL: return "Invalid URL"
      case .invalidResponse: return "Invalid response"
      case .serverError(let msg): return "Translation error: \(msg)"
      }
    }
  }
}
