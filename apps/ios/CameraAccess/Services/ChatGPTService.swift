/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// ChatGPTService.swift
//
// Service for interacting with OpenAI ChatGPT API as a fallback when Gemini fails
//

import Foundation
import UIKit

class ChatGPTService {
  static let shared = ChatGPTService()
  
  private let apiKey: String
  private let baseURL = "https://api.openai.com/v1/chat/completions"
  
  init() {
    // Get API key from Info.plist
    if let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
       let plist = NSDictionary(contentsOfFile: path),
       let key = plist["CHATGPT_API_KEY"] as? String, !key.isEmpty {
      self.apiKey = key
    } else {
      // Fallback to environment variable or empty string
      self.apiKey = ProcessInfo.processInfo.environment["CHATGPT_API_KEY"] ?? ""
    }
  }
  
  func generateResponse(for text: String) async throws -> String {
    guard !apiKey.isEmpty else {
      print("🔴 [ChatGPT] API key not found")
      throw ChatGPTError.apiKeyNotFound
    }
    
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      print("🔴 [ChatGPT] Empty input text")
      throw ChatGPTError.emptyInput
    }
    
    guard let url = URL(string: baseURL) else {
      print("🔴 [ChatGPT] Invalid URL: \(baseURL)")
      throw ChatGPTError.invalidURL
    }
    
    let requestBody: [String: Any] = [
      "model": "gpt-3.5-turbo",
      "messages": [
        [
          "role": "user",
          "content": text
        ]
      ],
      "max_tokens": 150,
      "temperature": 0.7
    ]
    
    // Log request
    print("📤 [ChatGPT] Sending request")
    print("   URL: \(baseURL)")
    print("   Method: POST")
    if let requestBodyJson = try? JSONSerialization.data(withJSONObject: requestBody, options: .prettyPrinted),
       let requestBodyString = String(data: requestBodyJson, encoding: .utf8) {
      print("   Request Body:\n\(requestBodyString)")
    }
    print("   Input text: \"\(text)\"")
    print("   Model: gpt-3.5-turbo")
    print("   Max tokens: 150")
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
    print("   Authorization: Bearer \(apiKey.prefix(10))...") // Log partial key for debugging
    
    let startTime = Date()
    let (data, response) = try await URLSession.shared.data(for: request)
    let duration = Date().timeIntervalSince(startTime)
    
    // Log response
    if let httpResponse = response as? HTTPURLResponse {
      print("📥 [ChatGPT] Received response")
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
      print("🔴 [ChatGPT] Invalid response type")
      throw ChatGPTError.invalidResponse
    }
    
    guard (200...299).contains(httpResponse.statusCode) else {
      print("🔴 [ChatGPT] HTTP error: \(httpResponse.statusCode)")
      if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let error = errorData["error"] as? [String: Any],
         let message = error["message"] as? String {
        print("   Error message: \(message)")
        print("   Full error: \(error)")
        throw ChatGPTError.apiError(message)
      }
      throw ChatGPTError.httpError(httpResponse.statusCode)
    }
    
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = json["choices"] as? [[String: Any]],
          let firstChoice = choices.first,
          let message = firstChoice["message"] as? [String: Any],
          let content = message["content"] as? String else {
      print("🔴 [ChatGPT] Failed to parse response JSON")
      if let jsonString = String(data: data, encoding: .utf8) {
        print("   Raw response: \(jsonString)")
      }
      throw ChatGPTError.invalidResponse
    }
    
    let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Log usage if available
    if let usage = json["usage"] as? [String: Any] {
      print("   Token usage: \(usage)")
    }
    
    print("✅ [ChatGPT] Successfully generated response")
    print("   Generated text: \"\(trimmedContent)\"")
    print("   Response length: \(trimmedContent.count) characters")
    
    return trimmedContent
  }
  
  func generateResponse(for text: String, with image: UIImage) async throws -> String {
    guard !apiKey.isEmpty else {
      print("🔴 [ChatGPT] API key not found")
      throw ChatGPTError.apiKeyNotFound
    }
    
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      print("🔴 [ChatGPT] Empty input text")
      throw ChatGPTError.emptyInput
    }
    
    guard let url = URL(string: baseURL) else {
      print("🔴 [ChatGPT] Invalid URL: \(baseURL)")
      throw ChatGPTError.invalidURL
    }
    
    // Convert image to base64
    guard let imageData = image.jpegData(compressionQuality: 0.8) else {
      print("🔴 [ChatGPT] Failed to convert image to JPEG")
      throw ChatGPTError.invalidImage
    }
    let base64Image = imageData.base64EncodedString()
    
    // Use gpt-4o model which supports vision
    let requestBody: [String: Any] = [
      "model": "gpt-4o",
      "messages": [
        [
          "role": "user",
          "content": [
            [
              "type": "text",
              "text": text
            ],
            [
              "type": "image_url",
              "image_url": [
                "url": "data:image/jpeg;base64,\(base64Image)"
              ]
            ]
          ]
        ]
      ],
      "max_tokens": 300,
      "temperature": 0.7
    ]
    
    // Log request
    print("📤 [ChatGPT] Sending request with image")
    print("   URL: \(baseURL)")
    print("   Model: gpt-4o")
    print("   Image size: \(imageData.count) bytes")
    print("   Input text: \"\(text)\"")
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
    
    let startTime = Date()
    let (data, response) = try await URLSession.shared.data(for: request)
    let duration = Date().timeIntervalSince(startTime)
    
    // Log response
    if let httpResponse = response as? HTTPURLResponse {
      print("📥 [ChatGPT] Received response")
      print("   Status Code: \(httpResponse.statusCode)")
      print("   Duration: \(String(format: "%.2f", duration))s")
    }
    
    guard let httpResponse = response as? HTTPURLResponse else {
      print("🔴 [ChatGPT] Invalid response type")
      throw ChatGPTError.invalidResponse
    }
    
    guard (200...299).contains(httpResponse.statusCode) else {
      print("🔴 [ChatGPT] HTTP error: \(httpResponse.statusCode)")
      if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let error = errorData["error"] as? [String: Any],
         let message = error["message"] as? String {
        print("   Error message: \(message)")
        throw ChatGPTError.apiError(message)
      }
      throw ChatGPTError.httpError(httpResponse.statusCode)
    }
    
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = json["choices"] as? [[String: Any]],
          let firstChoice = choices.first,
          let message = firstChoice["message"] as? [String: Any],
          let content = message["content"] as? String else {
      print("🔴 [ChatGPT] Failed to parse response JSON")
      throw ChatGPTError.invalidResponse
    }
    
    let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
    
    print("✅ [ChatGPT] Successfully generated response with image")
    print("   Generated text: \"\(trimmedContent)\"")
    
    return trimmedContent
  }
}

enum ChatGPTError: LocalizedError {
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
      return "ChatGPT API key not found. Please set CHATGPT_API_KEY in Info.plist or environment variables."
    case .emptyInput:
      return "Input text is empty."
    case .invalidURL:
      return "Invalid API URL."
    case .invalidResponse:
      return "Invalid response from ChatGPT API."
    case .httpError(let code):
      return "HTTP error: \(code)"
    case .apiError(let message):
      return "ChatGPT API error: \(message)"
    case .invalidImage:
      return "Invalid image data."
    }
  }
}
