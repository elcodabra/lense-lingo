/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// TranslationStreamView.swift
//
// Translation mode overlaid on the glasses video stream.
// Combines streaming video with real-time translation.
//

import SwiftUI

struct TranslationStreamView: View {
  @ObservedObject var translationVM: TranslationViewModel
  @ObservedObject var streamVM: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  var onSwitchToAssistant: () -> Void

  var body: some View {
    ZStack {
      // Video background
      if streamVM.shouldShowVideoDisplay {
        if let videoFrame = streamVM.currentVideoFrame, streamVM.hasReceivedFirstFrame {
          GeometryReader { geometry in
            Image(uiImage: videoFrame)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: geometry.size.width, height: geometry.size.height)
              .clipped()
          }
          .edgesIgnoringSafeArea(.all)
        } else {
          Color.black.edgesIgnoringSafeArea(.all)
          ProgressView()
            .scaleEffect(1.5)
            .foregroundColor(.white)
        }
      } else {
        Color.black.edgesIgnoringSafeArea(.all)
      }

      // Dimming overlay for readability
      Color.black.opacity(0.4)
        .edgesIgnoringSafeArea(.all)

      VStack(spacing: 0) {
        // Top bar
        topBar
          .padding(.top, 8)

        // Language selector
        languageBar
          .padding(.top, 10)
          .padding(.horizontal, 16)

        // Translation results
        translationList
          .padding(.top, 4)

        Spacer(minLength: 0)

        // Bottom controls
        bottomControls
      }
    }
    .onDisappear {
      translationVM.cleanup()
    }
  }

  // MARK: - Top Bar

  private var topBar: some View {
    HStack {
      // Mode switcher
      Button {
        translationVM.cleanup()
        onSwitchToAssistant()
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "sparkles")
            .font(.system(size: 11))
          Text("AI Mode")
            .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.8))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.15))
        .cornerRadius(14)
      }

      Spacer()

      Text("Translation")
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.white)

      Spacer()

      // Stop streaming
      Button {
        translationVM.cleanup()
        Task { await streamVM.stopSession() }
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.white)
          .frame(width: 32, height: 32)
          .background(Color.red.opacity(0.8))
          .clipShape(Circle())
      }
    }
    .padding(.horizontal, 16)
  }

  // MARK: - Language Bar

  private var languageBar: some View {
    HStack(spacing: 8) {
      languagePill(selection: $translationVM.sourceLanguage)

      Button {
        translationVM.swapLanguages()
      } label: {
        Image(systemName: "arrow.left.arrow.right")
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(.white.opacity(0.9))
          .frame(width: 30, height: 30)
          .background(Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.5))
          .clipShape(Circle())
      }

      languagePill(selection: $translationVM.targetLanguage)
    }
  }

  private func languagePill(selection: Binding<TranslationLanguage>) -> some View {
    Menu {
      ForEach(TranslationLanguage.allCases) { lang in
        Button {
          selection.wrappedValue = lang
        } label: {
          HStack {
            Text("\(lang.flag) \(lang.displayName)")
            if selection.wrappedValue == lang {
              Image(systemName: "checkmark")
            }
          }
        }
      }
    } label: {
      HStack(spacing: 4) {
        Text(selection.wrappedValue.flag)
          .font(.system(size: 13))
        Text(selection.wrappedValue.displayName)
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.white)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .background(Color.black.opacity(0.5))
      .cornerRadius(10)
    }
  }

  // MARK: - Translation List

  private var translationList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 8) {
          ForEach(translationVM.entries) { entry in
            translationCard(entry)
              .id(entry.id)
          }

          // Partial text
          if !translationVM.currentPartialText.isEmpty {
            HStack(spacing: 6) {
              Image(systemName: "mic.fill")
                .font(.system(size: 10))
                .foregroundColor(.blue)
              Text(translationVM.currentPartialText)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .italic()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.black.opacity(0.5))
            .cornerRadius(10)
          }

          // Loading
          if translationVM.isTranslating || translationVM.isTranslatingImage {
            HStack(spacing: 6) {
              ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.6)))
                .scaleEffect(0.6)
              Text(translationVM.isTranslatingImage ? "Reading image..." : "Translating...")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
            }
            .padding(8)
          }

          // Error
          if let error = translationVM.errorMessage {
            Text(error)
              .font(.system(size: 11))
              .foregroundColor(.orange)
              .padding(8)
              .background(Color.orange.opacity(0.1))
              .cornerRadius(6)
          }

          // Image preview
          if let img = translationVM.currentImage {
            Image(uiImage: img)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(maxHeight: 100)
              .cornerRadius(8)
              .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.purple.opacity(0.5), lineWidth: 1))
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
      }
      .onChange(of: translationVM.entries.count) { _, _ in
        if let last = translationVM.entries.last {
          withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
      }
    }
  }

  private func translationCard(_ entry: TranslationEntry) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      // Source
      Text(entry.sourceText)
        .font(.system(size: 13))
        .foregroundColor(.white.opacity(0.7))

      // Translation
      Text(entry.translatedText)
        .font(.system(size: 16, weight: .medium))
        .foregroundColor(.white)

      // Transcription
      if let tr = entry.transcription, !tr.isEmpty {
        Text("[\(tr)]")
          .font(.system(size: 11))
          .foregroundColor(.white.opacity(0.4))
      }

      // Action buttons
      HStack(spacing: 8) {
        if let soundUrl = entry.soundUrl, !soundUrl.isEmpty {
          Button {
            translationVM.playSoundUrl(soundUrl)
          } label: {
            Image(systemName: "speaker.wave.2.fill")
              .font(.system(size: 11))
              .foregroundColor(.cyan)
              .padding(6)
              .background(Color.cyan.opacity(0.15))
              .cornerRadius(8)
          }
        }

        Button {
          translationVM.speakTranslation(entry.translatedText)
        } label: {
          Image(systemName: "mouth.fill")
            .font(.system(size: 11))
            .foregroundColor(.purple)
            .padding(6)
            .background(Color.purple.opacity(0.12))
            .cornerRadius(8)
        }

        // Examples toggle
        if !entry.examples.isEmpty {
          ExamplesView(examples: entry.examples)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Color.black.opacity(0.6))
    .cornerRadius(12)
  }

  // MARK: - Bottom Controls

  private var bottomControls: some View {
    VStack(spacing: 12) {
      // Listening status
      if translationVM.autoListening || translationVM.isListening {
        HStack(spacing: 4) {
          Image(systemName: translationVM.isSpeechRecognitionActive ? "mic.fill" : "mic.slash.fill")
            .font(.system(size: 12))
            .foregroundColor(translationVM.isSpeechRecognitionActive ? .green : .orange)
          Text(translationVM.isSpeechRecognitionActive
            ? "Listening in \(translationVM.sourceLanguage.displayName)..."
            : "Voice recognition starting...")
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
          get: { translationVM.autoListening },
          set: { _ in translationVM.toggleAutoListening() }
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

      // Manual buttons
      HStack(spacing: 12) {
        // Start/Stop button — one-shot manual listen + translate
        Button {
          translationVM.toggleListening()
        } label: {
          HStack(spacing: 8) {
            Image(systemName: translationVM.isListening && !translationVM.autoListening ? "stop.circle.fill" : "mic.circle.fill")
              .font(.system(size: 16))
            Text(translationVM.isListening && !translationVM.autoListening ? "Stop" : "Start")
              .font(.system(size: 15, weight: .semibold))
          }
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 48)
          .background(translationVM.isListening && !translationVM.autoListening ? Color.red : Color.blue)
          .cornerRadius(24)
        }

        // Camera translate button
        Button {
          if let frame = streamVM.currentVideoFrame {
            translationVM.translateImage(frame)
          }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "camera.fill")
              .font(.system(size: 16))
            Text("Translate")
              .font(.system(size: 15, weight: .semibold))
          }
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 48)
          .background(Color.purple)
          .cornerRadius(24)
        }
        .disabled(streamVM.currentVideoFrame == nil || translationVM.isTranslatingImage)
        .opacity(streamVM.currentVideoFrame != nil && !translationVM.isTranslatingImage ? 1.0 : 0.6)
      }
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 12)
    .padding(.top, 8)
    .background(
      LinearGradient(
        colors: [Color.clear, Color.black.opacity(0.5)],
        startPoint: .top,
        endPoint: .bottom
      )
      .edgesIgnoringSafeArea(.bottom)
    )
  }
}
