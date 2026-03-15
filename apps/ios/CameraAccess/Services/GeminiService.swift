/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// GeminiService.swift
//
// Service for interacting with Google Gemini API to generate responses to voice text
//

import Foundation
import UIKit

class GeminiService {
  static let shared = GeminiService()
  
  private let apiKey: String
  private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
  
  init() {
    // Get API key from Info.plist
    if let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
       let plist = NSDictionary(contentsOfFile: path),
       let key = plist["GEMINI_API_KEY"] as? String, !key.isEmpty {
      self.apiKey = key
    } else {
      // Fallback to environment variable or empty string
      self.apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
    }
  }
  
  func generateResponse(for text: String) async throws -> String {
    guard !apiKey.isEmpty else {
      print("🔴 [Gemini] API key not found")
      throw GeminiError.apiKeyNotFound
    }
    
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      print("🔴 [Gemini] Empty input text")
      throw GeminiError.emptyInput
    }
    
    guard let url = URL(string: baseURL) else {
      print("🔴 [Gemini] Invalid URL: \(baseURL)")
      throw GeminiError.invalidURL
    }
    
    let requestBody: [String: Any] = [
      "contents": [
        [
          "parts": [
            [
              "text": text
            ]
          ]
        ]
      ]
    ]
    
    // Log request
    print("📤 [Gemini] Sending request")
    print("   URL: \(baseURL)")
    print("   Method: POST")
    print("   Model: gemini-2.0-flash")
    print("   API Key: \(apiKey.prefix(10))...")
    if let requestBodyJson = try? JSONSerialization.data(withJSONObject: requestBody, options: .prettyPrinted),
       let requestBodyString = String(data: requestBodyJson, encoding: .utf8) {
      print("   Request Body:\n\(requestBodyString)")
    }
    print("   Input text: \"\(text)\"")
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "X-goog-api-key")
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
    
    let startTime = Date()
    let (data, response) = try await URLSession.shared.data(for: request)
    let duration = Date().timeIntervalSince(startTime)
    
    // Log response
    if let httpResponse = response as? HTTPURLResponse {
      print("📥 [Gemini] Received response")
      print("   Status Code: \(httpResponse.statusCode)")
      print("   Duration: \(String(format: "%.2f", duration))s")
      print("   Response Size: \(data.count) bytes")
      
      if let responseString = String(data: data, encoding: .utf8) {
        // Log full response for debugging (may be long)
        if responseString.count > 500 {
          print("   Response Body (first 500 chars): \(String(responseString.prefix(500)))...")
        } else {
          print("   Response Body:\n\(responseString)")
        }
      }
    }
    
    guard let httpResponse = response as? HTTPURLResponse else {
      print("🔴 [Gemini] Invalid response type")
      throw GeminiError.invalidResponse
    }
    
    guard (200...299).contains(httpResponse.statusCode) else {
      print("🔴 [Gemini] HTTP error: \(httpResponse.statusCode)")
      if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let error = errorData["error"] as? [String: Any],
         let message = error["message"] as? String {
        print("   Error message: \(message)")
        print("   Full error: \(error)")
        throw GeminiError.apiError(message)
      }
      throw GeminiError.httpError(httpResponse.statusCode)
    }
    
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let candidates = json["candidates"] as? [[String: Any]],
          let firstCandidate = candidates.first,
          let content = firstCandidate["content"] as? [String: Any],
          let parts = content["parts"] as? [[String: Any]],
          let firstPart = parts.first,
          let generatedText = firstPart["text"] as? String else {
      print("🔴 [Gemini] Failed to parse response JSON")
      if let jsonString = String(data: data, encoding: .utf8) {
        print("   Raw response: \(jsonString)")
      }
      throw GeminiError.invalidResponse
    }
    
    print("✅ [Gemini] Successfully generated response")
    print("   Generated text: \"\(generatedText)\"")
    print("   Response length: \(generatedText.count) characters")
    
    return generatedText
  }
  
  func generateResponse(for text: String, with image: UIImage) async throws -> String {
    guard !apiKey.isEmpty else {
      print("🔴 [Gemini] API key not found")
      throw GeminiError.apiKeyNotFound
    }
    
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      print("🔴 [Gemini] Empty input text")
      throw GeminiError.emptyInput
    }
    
    guard let url = URL(string: baseURL) else {
      print("🔴 [Gemini] Invalid URL: \(baseURL)")
      throw GeminiError.invalidURL
    }
    
    // Convert image to base64
    guard let imageData = image.jpegData(compressionQuality: 0.8) else {
      print("🔴 [Gemini] Failed to convert image to JPEG")
      throw GeminiError.invalidImage
    }
    let base64Image = imageData.base64EncodedString()
    
    let requestBody: [String: Any] = [
      "contents": [
        [
          "parts": [
            [
              "text": text
            ],
            [
              "inline_data": [
                "mime_type": "image/jpeg",
                "data": base64Image
              ]
            ]
          ]
        ]
      ]
    ]
    
    // Log request
    print("📤 [Gemini] Sending request with image")
    print("   URL: \(baseURL)")
    print("   Method: POST")
    print("   Model: gemini-2.0-flash")
    print("   Image size: \(imageData.count) bytes")
    print("   Input text: \"\(text)\"")
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "X-goog-api-key")
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
    
    let startTime = Date()
    let (data, response) = try await URLSession.shared.data(for: request)
    let duration = Date().timeIntervalSince(startTime)
    
    // Log response
    if let httpResponse = response as? HTTPURLResponse {
      print("📥 [Gemini] Received response")
      print("   Status Code: \(httpResponse.statusCode)")
      print("   Duration: \(String(format: "%.2f", duration))s")
    }
    
    guard let httpResponse = response as? HTTPURLResponse else {
      print("🔴 [Gemini] Invalid response type")
      throw GeminiError.invalidResponse
    }
    
    guard (200...299).contains(httpResponse.statusCode) else {
      print("🔴 [Gemini] HTTP error: \(httpResponse.statusCode)")
      if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let error = errorData["error"] as? [String: Any],
         let message = error["message"] as? String {
        print("   Error message: \(message)")
        throw GeminiError.apiError(message)
      }
      throw GeminiError.httpError(httpResponse.statusCode)
    }
    
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let candidates = json["candidates"] as? [[String: Any]],
          let firstCandidate = candidates.first,
          let content = firstCandidate["content"] as? [String: Any],
          let parts = content["parts"] as? [[String: Any]],
          let firstPart = parts.first,
          let generatedText = firstPart["text"] as? String else {
      print("🔴 [Gemini] Failed to parse response JSON")
      throw GeminiError.invalidResponse
    }
    
    print("✅ [Gemini] Successfully generated response with image")
    print("   Generated text: \"\(generatedText)\"")
    
    return generatedText
  }
}

enum GeminiError: LocalizedError {
  case apiKeyNotFound
  case emptyInput
  case invalidURL
  case invalidResponse
  case httpError(Int)
  case apiError(String)
  case invalidImage
  
  var errorDescription: String? {
    switch self {
    case .apiKeyNotFound:
      return "Gemini API key not found. Please set GEMINI_API_KEY in Info.plist or environment variables."
    case .emptyInput:
      return "Input text is empty."
    case .invalidURL:
      return "Invalid API URL."
    case .invalidResponse:
      return "Invalid response from Gemini API."
    case .httpError(let code):
      return "HTTP error: \(code)"
    case .apiError(let message):
      return "Gemini API error: \(message)"
    case .invalidImage:
      return "Invalid image data."
    }
  }
}
