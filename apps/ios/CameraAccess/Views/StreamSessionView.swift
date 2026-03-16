/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamSessionView.swift
//
//

import MWDATCore
import SwiftUI

struct StreamSessionView: View {
  let wearables: WearablesInterface
  @ObservedObject private var wearablesViewModel: WearablesViewModel
  @StateObject private var viewModel: StreamSessionViewModel
  @StateObject private var translationVM = TranslationViewModel()
  @State private var appMode: AppMode = {
    let saved = UserDefaults.standard.string(forKey: "appMode") ?? "assistant"
    return AppMode(rawValue: saved) ?? .assistant
  }()

  init(wearables: WearablesInterface, wearablesVM: WearablesViewModel) {
    self.wearables = wearables
    self.wearablesViewModel = wearablesVM
    self._viewModel = StateObject(wrappedValue: StreamSessionViewModel(wearables: wearables, selectedLanguage: wearablesVM.selectedLanguage))
  }

  var body: some View {
    ZStack {
      if viewModel.isStreaming {
        switch appMode {
        case .assistant:
          StreamView(viewModel: viewModel, wearablesVM: wearablesViewModel, onSwitchToTranslation: { appMode = .translation })
        case .translation:
          TranslationStreamView(
            translationVM: translationVM,
            streamVM: viewModel,
            wearablesVM: wearablesViewModel,
            onSwitchToAssistant: { appMode = .assistant }
          )
        }
      } else {
        NonStreamView(
          viewModel: viewModel,
          wearablesVM: wearablesViewModel,
          appMode: $appMode
        )
      }
    }
    .onChange(of: wearablesViewModel.selectedLanguage) { oldValue, newValue in
      Task {
        await viewModel.updateLanguage(newValue)
      }
    }
    .onChange(of: appMode) { _, newMode in
      UserDefaults.standard.set(newMode.rawValue, forKey: "appMode")
    }
    .alert("Error", isPresented: $viewModel.showError) {
      Button("OK") {
        viewModel.dismissError()
      }
    } message: {
      Text(viewModel.errorMessage)
    }
  }
}
