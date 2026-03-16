/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// TranslationView.swift
//
// Translation mode UI — language pickers, speech input, translation results,
// and audio playback controls. Works both standalone and with glasses streaming.
//

import SwiftUI

struct TranslationView: View {
  @ObservedObject var viewModel: TranslationViewModel
  var currentVideoFrame: UIImage?
  var onBack: () -> Void

  var body: some View {
    ZStack {
      // Background
      LinearGradient(
        colors: [
          Color(red: 0.05, green: 0.10, blue: 0.18),
          Color(red: 0.08, green: 0.06, blue: 0.20),
          Color(red: 0.04, green: 0.04, blue: 0.12),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .edgesIgnoringSafeArea(.all)

      VStack(spacing: 0) {
        // Top bar
        topBar

        // Language selector
        languageBar
          .padding(.top, 12)

        // Translation list
        translationList
          .padding(.top, 8)

        Spacer(minLength: 0)

        // Bottom controls
        bottomControls
      }
    }
  }

  // MARK: - Top Bar

  private var topBar: some View {
    HStack {
      Button {
        viewModel.cleanup()
        onBack()
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.white.opacity(0.85))
          .frame(width: 36, height: 36)
          .background(Color.white.opacity(0.1))
          .cornerRadius(18)
      }

      Spacer()

      Text("Translation")
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(.white)

      Spacer()

      // Clear history
      Button {
        viewModel.clearHistory()
      } label: {
        Image(systemName: "trash")
          .font(.system(size: 14))
          .foregroundColor(.white.opacity(0.6))
          .frame(width: 36, height: 36)
          .background(Color.white.opacity(0.08))
          .cornerRadius(18)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 12)
  }

  // MARK: - Language Bar

  private var languageBar: some View {
    HStack(spacing: 12) {
      // Source language picker
      languagePicker(
        selection: $viewModel.sourceLanguage,
        label: "From"
      )

      // Swap button
      Button {
        viewModel.swapLanguages()
      } label: {
        Image(systemName: "arrow.left.arrow.right")
          .font(.system(size: 14, weight: .bold))
          .foregroundColor(.white)
          .frame(width: 36, height: 36)
          .background(
            Circle()
              .fill(Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.5))
          )
      }

      // Target language picker
      languagePicker(
        selection: $viewModel.targetLanguage,
        label: "To"
      )
    }
    .padding(.horizontal, 20)
  }

  private func languagePicker(selection: Binding<TranslationLanguage>, label: String) -> some View {
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
      VStack(spacing: 2) {
        Text(label)
          .font(.system(size: 10))
          .foregroundColor(.white.opacity(0.5))
        HStack(spacing: 4) {
          Text(selection.wrappedValue.flag)
            .font(.system(size: 14))
          Text(selection.wrappedValue.displayName)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .background(Color.white.opacity(0.1))
      .cornerRadius(12)
    }
  }

  // MARK: - Translation List

  private var translationList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 12) {
          ForEach(viewModel.entries) { entry in
            TranslationEntryCard(entry: entry, viewModel: viewModel)
              .id(entry.id)
          }

          // Current partial text
          if !viewModel.currentPartialText.isEmpty {
            HStack {
              Image(systemName: "mic.fill")
                .font(.system(size: 10))
                .foregroundColor(.blue.opacity(0.7))
              Text(viewModel.currentPartialText)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .italic()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.06))
            .cornerRadius(12)
          }

          // Translating indicator
          if viewModel.isTranslating || viewModel.isTranslatingImage {
            HStack(spacing: 8) {
              ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.6)))
                .scaleEffect(0.7)
              Text(viewModel.isTranslatingImage ? "Reading image..." : "Translating...")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
            }
            .padding(12)
          }

          // Error
          if let error = viewModel.errorMessage {
            HStack(spacing: 6) {
              Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)
              Text(error)
                .font(.system(size: 12))
                .foregroundColor(.orange.opacity(0.9))
            }
            .padding(10)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
          }

          // Image being translated
          if let img = viewModel.currentImage {
            Image(uiImage: img)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(maxHeight: 120)
              .cornerRadius(8)
              .overlay(
                RoundedRectangle(cornerRadius: 8)
                  .stroke(Color.purple.opacity(0.6), lineWidth: 1.5)
              )
              .padding(.horizontal, 4)
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
      }
      .onChange(of: viewModel.entries.count) { _, _ in
        if let last = viewModel.entries.last {
          withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
      }
    }
  }

  // MARK: - Bottom Controls

  private var bottomControls: some View {
    VStack(spacing: 12) {
      // Auto listening toggle
      HStack {
        Toggle(isOn: Binding(
          get: { viewModel.autoListening },
          set: { _ in viewModel.toggleAutoListening() }
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
      .background(Color.white.opacity(0.08))
      .cornerRadius(12)

      // Listening indicator
      if viewModel.isListening {
        HStack(spacing: 6) {
          Circle()
            .fill(Color.green)
            .frame(width: 8, height: 8)
          Text("Listening in \(viewModel.sourceLanguage.displayName)...")
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.7))
        }
      }

      HStack(spacing: 12) {
        // Mic button (manual)
        Button {
          viewModel.toggleListening()
        } label: {
          HStack(spacing: 8) {
            Image(systemName: viewModel.isListening ? "mic.slash.fill" : "mic.fill")
              .font(.system(size: 16))
            Text(viewModel.isListening ? "Stop" : "Listen")
              .font(.system(size: 15, weight: .semibold))
          }
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 50)
          .background(
            LinearGradient(
              colors: viewModel.isListening
                ? [Color.red.opacity(0.8), Color.red.opacity(0.8)]
                : [Color(red: 0.25, green: 0.5, blue: 1.0), Color(red: 0.35, green: 0.4, blue: 0.95)],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .cornerRadius(25)
        }

        // Camera button (translate from image)
        if currentVideoFrame != nil {
          Button {
            if let frame = currentVideoFrame {
              viewModel.translateImage(frame)
            }
          } label: {
            Image(systemName: "photo.fill")
              .font(.system(size: 16))
              .foregroundColor(.white)
              .frame(width: 50, height: 50)
              .background(Color.purple.opacity(0.8))
              .cornerRadius(25)
          }
          .disabled(viewModel.isTranslatingImage)
          .opacity(viewModel.isTranslatingImage ? 0.5 : 1.0)
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 28)
    .padding(.top, 8)
    .background(
      LinearGradient(
        colors: [Color.clear, Color.black.opacity(0.3)],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }
}

// MARK: - Translation Entry Card

struct TranslationEntryCard: View {
  let entry: TranslationEntry
  @ObservedObject var viewModel: TranslationViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Source text
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "text.bubble")
          .font(.system(size: 11))
          .foregroundColor(.blue.opacity(0.7))
          .padding(.top, 2)
        Text(entry.sourceText)
          .font(.system(size: 14))
          .foregroundColor(.white.opacity(0.8))
      }

      // Translated text
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "text.book.closed")
          .font(.system(size: 11))
          .foregroundColor(.green.opacity(0.8))
          .padding(.top, 2)
        VStack(alignment: .leading, spacing: 4) {
          Text(entry.translatedText)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)

          // Transcription
          if let transcription = entry.transcription, !transcription.isEmpty {
            Text("[\(transcription)]")
              .font(.system(size: 12))
              .foregroundColor(.white.opacity(0.4))
          }
        }
      }

      // Audio buttons
      HStack(spacing: 12) {
        // Play sound from API
        if let soundUrl = entry.soundUrl, !soundUrl.isEmpty {
          Button {
            viewModel.playSoundUrl(soundUrl)
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 11))
              Text("Play")
                .font(.system(size: 11))
            }
            .foregroundColor(.cyan)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.cyan.opacity(0.15))
            .cornerRadius(12)
          }
        }

        // TTS speak
        Button {
          viewModel.speakTranslation(entry.translatedText)
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "mouth.fill")
              .font(.system(size: 11))
            Text("Speak")
              .font(.system(size: 11))
          }
          .foregroundColor(.purple.opacity(0.9))
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(Color.purple.opacity(0.12))
          .cornerRadius(12)
        }
      }

      // Examples (collapsed by default) — filter out empty examples from API
      let validExamples = entry.examples.filter { !$0.source.isEmpty || !$0.target.isEmpty }
      if !validExamples.isEmpty {
        ExamplesView(examples: validExamples)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(Color.white.opacity(0.07))
    .cornerRadius(14)
  }
}

// MARK: - Examples

struct ExamplesView: View {
  let examples: [TranslationExample]
  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          isExpanded.toggle()
        }
      } label: {
        HStack(spacing: 4) {
          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 10))
          Text("Examples (\(examples.count))")
            .font(.system(size: 11))
        }
        .foregroundColor(.white.opacity(0.5))
      }

      if isExpanded {
        ForEach(examples.prefix(3), id: \.id) { example in
          VStack(alignment: .leading, spacing: 2) {
            Text(example.source)
              .font(.system(size: 12))
              .foregroundColor(.white.opacity(0.6))
            Text(example.target)
              .font(.system(size: 12))
              .foregroundColor(.white.opacity(0.45))
              .italic()
          }
          .padding(.leading, 14)
        }
      }
    }
  }
}
