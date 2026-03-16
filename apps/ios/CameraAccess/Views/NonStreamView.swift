/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// NonStreamView.swift
//
// Default screen to show getting started tips after app connection
// Initiates streaming
//

import MWDATCore
import SwiftUI

struct NonStreamView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  @Binding var appMode: AppMode
  @State private var sheetHeight: CGFloat = 300
  @State private var pulseAnimation = false

  var body: some View {
    ZStack {
      // Gradient background
      LinearGradient(
        colors: [
          Color(red: 0.07, green: 0.07, blue: 0.15),
          Color(red: 0.10, green: 0.08, blue: 0.22),
          Color(red: 0.05, green: 0.05, blue: 0.12),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .edgesIgnoringSafeArea(.all)

      // Subtle radial glow behind icon
      RadialGradient(
        colors: [
          Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.15),
          Color.clear,
        ],
        center: .center,
        startRadius: 20,
        endRadius: 200
      )
      .offset(y: -60)
      .edgesIgnoringSafeArea(.all)

      VStack(spacing: 0) {
        // Top bar
        HStack {
          // Language selector (for AI mode)
          if appMode == .assistant {
            Menu {
              ForEach(AppLanguage.allCases.filter { $0 != .system }) { language in
                Button {
                  wearablesVM.selectedLanguage = language
                } label: {
                  HStack {
                    Text(language.displayName)
                    if wearablesVM.selectedLanguage == language {
                      Image(systemName: "checkmark")
                    }
                  }
                }
              }
            } label: {
              HStack(spacing: 5) {
                Image(systemName: "globe")
                  .font(.system(size: 13))
                Text(wearablesVM.selectedLanguage.displayName)
                  .font(.system(size: 13, weight: .medium))
              }
              .foregroundColor(.white.opacity(0.85))
              .padding(.horizontal, 12)
              .padding(.vertical, 7)
              .background(Color.white.opacity(0.12))
              .cornerRadius(20)
            }
          } else {
            // Placeholder for alignment
            Color.clear.frame(width: 1, height: 1)
          }

          Spacer()

          Menu {
            Button("Disconnect", role: .destructive) {
              wearablesVM.disconnectGlasses()
            }
            .disabled(wearablesVM.registrationState != .registered)
          } label: {
            Image(systemName: "gearshape")
              .font(.system(size: 18))
              .foregroundColor(.white.opacity(0.7))
              .frame(width: 36, height: 36)
              .background(Color.white.opacity(0.08))
              .cornerRadius(18)
          }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)

        Spacer()

        // Main content
        VStack(spacing: 20) {
          // Animated icon
          ZStack {
            // Pulse ring
            Circle()
              .stroke(Color(red: 0.4, green: 0.6, blue: 1.0).opacity(0.2), lineWidth: 1.5)
              .frame(width: 140, height: 140)
              .scaleEffect(pulseAnimation ? 1.15 : 1.0)
              .opacity(pulseAnimation ? 0 : 0.6)
              .animation(
                .easeInOut(duration: 2.0).repeatForever(autoreverses: false),
                value: pulseAnimation
              )

            Circle()
              .fill(Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.1))
              .frame(width: 120, height: 120)

            Image(.cameraAccessIcon)
              .resizable()
              .renderingMode(.template)
              .foregroundStyle(
                LinearGradient(
                  colors: [
                    Color(red: 0.5, green: 0.7, blue: 1.0),
                    Color(red: 0.3, green: 0.5, blue: 0.9),
                  ],
                  startPoint: .top,
                  endPoint: .bottom
                )
              )
              .aspectRatio(contentMode: .fit)
              .frame(width: 70)
          }
          .onAppear { pulseAnimation = true }

          // Title
          Text("LensLingo")
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(
              LinearGradient(
                colors: [.white, Color(red: 0.7, green: 0.8, blue: 1.0)],
                startPoint: .leading,
                endPoint: .trailing
              )
            )

          Text(appMode == .assistant ? "AI-Powered Smart Glasses" : "Real-time Translation")
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(.white.opacity(0.9))

          Text(appMode == .assistant
            ? "Ask questions, describe what you see,\nand get instant AI answers."
            : "Speak or capture text to translate\nbetween languages in real time."
          )
            .font(.system(size: 14))
            .multilineTextAlignment(.center)
            .foregroundColor(.white.opacity(0.5))
            .lineSpacing(3)
        }
        .padding(.horizontal, 32)

        Spacer()

        // Status & controls
        VStack(spacing: 16) {
          // Connection status
          if !viewModel.hasActiveDevice {
            HStack(spacing: 8) {
              Image(systemName: "iphone")
                .font(.system(size: 13))
              Text("No glasses connected — will use iPhone camera")
                .font(.system(size: 13))
            }
            .foregroundColor(.white.opacity(0.5))
            .transition(.opacity)
          }

          // Mode picker
          modePicker

          // Video display toggle
          HStack {
            Toggle(isOn: Binding(
              get: { viewModel.shouldShowVideoDisplay },
              set: { viewModel.shouldShowVideoDisplay = $0 }
            )) {
              HStack(spacing: 8) {
                Image(systemName: "video.fill")
                  .font(.system(size: 13))
                Text("Show camera display")
                  .font(.system(size: 14, weight: .medium))
              }
              .foregroundColor(.white.opacity(0.85))
            }
            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.3, green: 0.7, blue: 0.5)))
          }
          .padding(.horizontal, 18)
          .padding(.vertical, 12)
          .background(Color.white.opacity(0.08))
          .cornerRadius(16)

          // Start button
          Button {
            Task {
              await viewModel.handleStartStreaming()
            }
          } label: {
            Text(viewModel.hasActiveDevice ? "Start streaming" : "Start with iPhone camera")
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(.white)
              .frame(maxWidth: .infinity)
              .frame(height: 56)
              .background(
                LinearGradient(
                  colors: [
                    Color(red: 0.25, green: 0.5, blue: 1.0),
                    Color(red: 0.35, green: 0.4, blue: 0.95),
                  ],
                  startPoint: .leading,
                  endPoint: .trailing
                )
              )
              .cornerRadius(28)
              .shadow(color: Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.3), radius: 12, y: 4)
          }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
      }
    }
    .sheet(isPresented: $wearablesVM.showGettingStartedSheet) {
      if #available(iOS 16.0, *) {
        GettingStartedSheetView(height: $sheetHeight)
          .presentationDetents([.height(sheetHeight)])
          .presentationDragIndicator(.visible)
      } else {
        GettingStartedSheetView(height: $sheetHeight)
      }
    }
  }

  // MARK: - Mode Picker

  private var modePicker: some View {
    HStack(spacing: 0) {
      ForEach(AppMode.allCases) { mode in
        Button {
          withAnimation(.easeInOut(duration: 0.2)) {
            appMode = mode
          }
        } label: {
          HStack(spacing: 6) {
            Image(systemName: mode.icon)
              .font(.system(size: 12))
            Text(mode.displayName)
              .font(.system(size: 13, weight: .medium))
          }
          .foregroundColor(appMode == mode ? .white : .white.opacity(0.5))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
          .background(
            appMode == mode
              ? Color.white.opacity(0.15)
              : Color.clear
          )
          .cornerRadius(12)
        }
      }
    }
    .padding(3)
    .background(Color.white.opacity(0.08))
    .cornerRadius(14)
  }
}

struct GettingStartedSheetView: View {
  @Environment(\.dismiss) var dismiss
  @Binding var height: CGFloat

  var body: some View {
    VStack(spacing: 24) {
      Text("Getting started")
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(.primary)

      VStack(spacing: 12) {
        TipItemView(
          resource: .videoIcon,
          text: "First, Camera Access needs permission to use your glasses camera."
        )
        TipItemView(
          resource: .tapIcon,
          text: "Capture photos by tapping the camera button."
        )
        TipItemView(
          resource: .smartGlassesIcon,
          text: "The capture LED lets others know when you're capturing content or going live."
        )
      }
      .padding(.bottom, 16)

      CustomButton(
        title: "Continue",
        style: .primary,
        isDisabled: false
      ) {
        dismiss()
      }
    }
    .padding(.all, 24)
    .background(
      GeometryReader { geo -> Color in
        DispatchQueue.main.async {
          height = geo.size.height
        }
        return Color.clear
      }
    )
  }
}

struct TipItemView: View {
  let resource: ImageResource
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(resource)
        .resizable()
        .renderingMode(.template)
        .foregroundColor(.primary)
        .aspectRatio(contentMode: .fit)
        .frame(width: 24)
        .padding(.leading, 4)
        .padding(.top, 4)

      Text(text)
        .font(.system(size: 15))
        .foregroundColor(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
