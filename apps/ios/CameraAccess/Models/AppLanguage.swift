/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// AppLanguage.swift
//
// Language model for speech recognition and AI responses
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
  case russian = "ru"
  case english = "en"
  case spanish = "es"
  case system = "system"
  
  var id: String { rawValue }
  
  var displayName: String {
    switch self {
    case .russian:
      return "Русский"
    case .english:
      return "English"
    case .spanish:
      return "Español"
    case .system:
      return "System"
    }
  }
  
  var locale: Locale {
    switch self {
    case .russian:
      return Locale(identifier: "ru-RU")
    case .english:
      return Locale(identifier: "en-US")
    case .spanish:
      return Locale(identifier: "es-ES")
    case .system:
      return Locale.current
    }
  }
  
  static var defaultLanguage: AppLanguage {
    let systemLanguage = Locale.current.language.languageCode?.identifier ?? "en"
    if systemLanguage == "ru" {
      return .russian
    } else if systemLanguage == "es" {
      return .spanish
    }
    return .english
  }
}

