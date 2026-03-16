/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamView.swift
//
// Main UI for video streaming from Meta wearable devices using the DAT SDK.
// This view demonstrates the complete streaming API: video streaming with real-time display, photo capture,
// and error handling.
//

import MWDATCore
import SwiftUI

struct StreamView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  var onSwitchToTranslation: (() -> Void)?

  var body: some View {
    ZStack {
      // Black background for letterboxing/pillarboxing
      Color.black
        .edgesIgnoringSafeArea(.all)

      // Video backdrop - only show if shouldShowVideoDisplay is enabled
      if viewModel.shouldShowVideoDisplay {
        if let videoFrame = viewModel.currentVideoFrame, viewModel.hasReceivedFirstFrame {
          GeometryReader { geometry in
            Image(uiImage: videoFrame)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: geometry.size.width, height: geometry.size.height)
              .clipped()
          }
          .edgesIgnoringSafeArea(.all)
        } else {
          ProgressView()
            .scaleEffect(1.5)
            .foregroundColor(.white)
        }
      } else {
        // Video display disabled - show black screen to save energy
        Color.black
          .edgesIgnoringSafeArea(.all)
      }

      // Top controls layer with language selector and stop button
      VStack {
        HStack {
          // Language selector
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
            HStack(spacing: 4) {
              Image(systemName: "globe")
                .font(.system(size: 12))
              Text(wearablesVM.selectedLanguage.displayName)
                .font(.system(size: 12))
            }
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.5))
            .cornerRadius(6)
          }
          .padding(.top, 8)
          .padding(.leading, 24)

          // Translation mode button
          if let onSwitch = onSwitchToTranslation {
            Button {
              onSwitch()
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "textformat.abc")
                  .font(.system(size: 11))
                Text("Translate")
                  .font(.system(size: 11, weight: .medium))
              }
              .foregroundColor(.white.opacity(0.8))
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(Color.purple.opacity(0.5))
              .cornerRadius(14)
            }
            .padding(.top, 8)
          }

          Spacer()

          // Stop streaming button (X icon) in top right corner
          Button {
            Task {
              await viewModel.stopSession()
            }
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(.white)
              .frame(width: 36, height: 36)
              .background(Color.red.opacity(0.8))
              .clipShape(Circle())
          }
          .padding(.top, 8)
          .padding(.trailing, 24)
        }
        
        Spacer()
      }

      // Bottom controls layer
      VStack {
        Spacer()
        
        // Auto listening switch and manual send buttons
        VStack(spacing: 12) {
          // Voice Recognition Status - show when autolistening is enabled OR during manual send
          if viewModel.isStreaming && (viewModel.autolistening || viewModel.isManualSending) {
            HStack(spacing: 4) {
              Image(systemName: (viewModel.isSpeechRecognitionActive || viewModel.isManualSending) ? "mic.fill" : "mic.slash.fill")
                .font(.system(size: 12))
                .foregroundColor((viewModel.isSpeechRecognitionActive || viewModel.isManualSending) ? .green : .orange)
              Text((viewModel.isSpeechRecognitionActive || viewModel.isManualSending) ? "Listening..." : "Voice recognition starting...")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6))
            .cornerRadius(8)
          }
          
          // Auto listening toggle
          HStack {
            Toggle(isOn: Binding(
              get: { viewModel.autolistening },
              set: { _ in viewModel.toggleAutolistening() }
            )) {
              HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                  .font(.system(size: 14))
                Text("Auto Listening")
                  .font(.system(size: 14, weight: .medium))
              }
              .foregroundColor(.white)
            }
            .toggleStyle(SwitchToggleStyle(tint: .green))
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(Color.black.opacity(0.6))
          .cornerRadius(12)
          
          // Manual send buttons
          HStack(spacing: 12) {
            // Start/Stop button for manual audio send
            Button {
              viewModel.manualSendAudio()
            } label: {
              HStack(spacing: 8) {
                Image(systemName: viewModel.shouldShowStopButton ? "stop.circle.fill" : "mic.circle.fill")
                  .font(.system(size: 16))
                Text(viewModel.shouldShowStopButton ? "Stop" : "Start")
                  .font(.system(size: 15, weight: .semibold))
              }
              .foregroundColor(.white)
              .frame(maxWidth: .infinity)
              .frame(height: 48)
              .background(viewModel.shouldShowStopButton ? Color.red : Color.blue)
              .cornerRadius(24)
            }
            .disabled(!viewModel.isStreaming)
            .opacity(viewModel.isStreaming ? 1.0 : 0.6)
            
            // Send Screen button for manual screen/image send
            Button {
              viewModel.manualSendScreen()
            } label: {
              HStack(spacing: 8) {
                Image(systemName: "photo.circle.fill")
                  .font(.system(size: 16))
                Text("Send Screen")
                  .font(.system(size: 15, weight: .semibold))
              }
              .foregroundColor(.white)
              .frame(maxWidth: .infinity)
              .frame(height: 48)
              .background(Color.purple)
              .cornerRadius(24)
            }
            .disabled(!viewModel.isStreaming || viewModel.currentVideoFrame == nil)
            .opacity(viewModel.isStreaming && viewModel.currentVideoFrame != nil ? 1.0 : 0.6)
          }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
      }
      .padding(.all, 24)
      // Chat messages display area (above controls, not overlapping)
      VStack {
        Spacer()
        VStack(spacing: 8) {
          // Image being sent to AI (thumbnail)
          if let aiImage = viewModel.currentAIImage {
            VStack(spacing: 4) {
              Text("Sending to AI:")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
              Image(uiImage: aiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 90)
                .cornerRadius(8)
                .overlay(
                  RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow, lineWidth: 2)
                )
                .shadow(color: .yellow.opacity(0.5), radius: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)
            .padding(.horizontal, 24)
          }
          
          // Recognized Text - display each line separately
          if !viewModel.recognizedLines.isEmpty || !viewModel.currentPartialText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              // Display finalized lines with Gemini responses
              ForEach(Array(viewModel.recognizedLines.enumerated()), id: \.offset) { index, line in
                VStack(alignment: .leading, spacing: 4) {
                  // User's voice text
                  HStack {
                    Image(systemName: "mic.fill")
                      .font(.system(size: 10))
                      .foregroundColor(.blue)
                    Text(line)
                      .font(.system(size: 14))
                      .foregroundColor(.white)
                  }
                  
                  // AI response (Gemini or ChatGPT)
                  if let aiResponse = viewModel.aiResponses[line] {
                    let source = viewModel.responseSources[line] ?? "unknown"
                    let iconName = source == "chatgpt" ? "message.fill" : "sparkles"
                    let color: Color = source == "chatgpt" ? .green : .yellow
                    let sourceLabel = source == "chatgpt" ? "ChatGPT" : "Gemini"
                    
                    HStack(alignment: .top, spacing: 4) {
                      Image(systemName: iconName)
                        .font(.system(size: 10))
                        .foregroundColor(color)
                        .padding(.top, 2)
                      VStack(alignment: .leading, spacing: 2) {
                        Text(aiResponse)
                          .font(.system(size: 13))
                          .foregroundColor(color.opacity(0.9))
                          .italic()
                        if source != "error" {
                          Text("via \(sourceLabel)")
                            .font(.system(size: 10))
                            .foregroundColor(color.opacity(0.6))
                        }
                      }
                    }
                    .padding(.leading, 14)
                  } else if index == viewModel.recognizedLines.count - 1 && viewModel.isGeneratingResponse {
                    HStack(alignment: .top, spacing: 4) {
                      ProgressView()
                        .scaleEffect(0.6)
                        .padding(.leading, 14)
                        .padding(.top, 2)
                      Text("Thinking...")
                        .font(.system(size: 12))
                        .foregroundColor(.yellow.opacity(0.7))
                        .italic()
                    }
                    .padding(.leading, 14)
                  }
                }
              }
              // Display current partial text (being spoken) if it exists
              if !viewModel.currentPartialText.isEmpty {
                HStack {
                  Image(systemName: "mic.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.blue.opacity(0.7))
                  Text(viewModel.currentPartialText)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .italic()
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.7))
            .cornerRadius(8)
            .padding(.horizontal, 24)
          }
          
          // Timer display
          if viewModel.activeTimeLimit.isTimeLimited && viewModel.remainingTime > 0 {
            Text("Streaming ending in \(viewModel.remainingTime.formattedCountdown)")
              .font(.system(size: 15))
              .foregroundColor(.white)
          }
        }
        .padding(.bottom, 200) // Increased padding to ensure it doesn't overlap with controls
      }
    }
    .onDisappear {
      Task {
        if viewModel.streamingStatus != .stopped {
          await viewModel.stopSession()
        }
      }
    }
    // Show captured photos from DAT SDK in a preview sheet
    .sheet(isPresented: $viewModel.showPhotoPreview) {
      if let photo = viewModel.capturedPhoto {
        PhotoPreviewView(
          photo: photo,
          onDismiss: {
            viewModel.dismissPhotoPreview()
          }
        )
      }
    }
  }
}

