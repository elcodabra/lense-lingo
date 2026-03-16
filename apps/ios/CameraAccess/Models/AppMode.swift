/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// AppMode.swift
//
// Defines the two operating modes: AI Assistant and Translation.
//

import Foundation

enum AppMode: String, CaseIterable, Identifiable {
  case assistant = "assistant"
  case translation = "translation"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .assistant: return "AI Assistant"
    case .translation: return "Translation"
    }
  }

  var icon: String {
    switch self {
    case .assistant: return "sparkles"
    case .translation: return "textformat.abc"
    }
  }
}
