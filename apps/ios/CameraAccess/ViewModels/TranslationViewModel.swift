/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// TranslationViewModel.swift
//
// Manages translation mode: speech recognition → wordzzz API → TTS/audio playback.
// Supports text and image-based translation.
//

import AVFoundation
import Speech
import SwiftUI
import UIKit

struct TranslationEntry: Identifiable {
  let id = UUID()
  let sourceText: String
  let translatedText: String
  let transcription: String?
  let soundUrl: String?
  let examples: [TranslationExample]
}

@MainActor
class TranslationViewModel: ObservableObject {
  // MARK: - Published Properties

  @Published var sourceLanguage: TranslationLanguage {
    didSet {
      UserDefaults.standard.set(sourceLanguage.rawValue, forKey: "translationSourceLang")
      setupSpeechRecognition()
    }
  }
  @Published var targetLanguage: TranslationLanguage {
    didSet {
      UserDefaults.standard.set(targetLanguage.rawValue, forKey: "translationTargetLang")
    }
  }

  @Published var currentPartialText: String = ""
  @Published var entries: [TranslationEntry] = []
  @Published var isTranslating: Bool = false
  @Published var isSpeechRecognitionActive: Bool = false
  @Published var isListening: Bool = false
  @Published var autoListening: Bool = false
  @Published var isSpeaking: Bool = false
  @Published var isPlayingAudio: Bool = false
  @Published var errorMessage: String?

  // Image translation
  @Published var currentImage: UIImage?
  @Published var isTranslatingImage: Bool = false

  // MARK: - Private Properties

  private var speechRecognizer: SFSpeechRecognizer?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var audioEngine = AVAudioEngine()
  private var isStartingRecognition = false

  private let speechSynthesizer = AVSpeechSynthesizer()
  private let synthesizerDelegate = SpeechSynthDelegate()
  private var audioPlayer: AVAudioPlayer?

  private var autoSendTask: Task<Void, Never>?
  private var currentTranslationTask: Task<Void, Never>?
  private let autoSendDelay: TimeInterval = 2.0

  // MARK: - Init

  init() {
    // Restore saved languages
    let savedSource = UserDefaults.standard.string(forKey: "translationSourceLang") ?? "en"
    let savedTarget = UserDefaults.standard.string(forKey: "translationTargetLang") ?? "ru"
    self.sourceLanguage = TranslationLanguage(rawValue: savedSource) ?? .english
    self.targetLanguage = TranslationLanguage(rawValue: savedTarget) ?? .russian

    synthesizerDelegate.onSpeakingChanged = { [weak self] speaking in
      Task { @MainActor in self?.isSpeaking = speaking }
    }
    speechSynthesizer.delegate = synthesizerDelegate

    setupSpeechRecognition()
  }

  // MARK: - Language Control

  func swapLanguages() {
    let temp = sourceLanguage
    sourceLanguage = targetLanguage
    targetLanguage = temp

    // Restart recognition with new source language if active
    if isSpeechRecognitionActive {
      stopListening()
      Task {
        try? await Task.sleep(nanoseconds: 300_000_000)
        await startListening()
      }
    }
  }

  // MARK: - Speech Recognition

  private func setupSpeechRecognition() {
    let locale = sourceLanguage.locale
    if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable {
      speechRecognizer = recognizer
      print("🌐 [Translation] Speech recognizer set for \(sourceLanguage.displayName)")
    } else {
      speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
      print("⚠️ [Translation] Fallback to English recognizer")
    }
  }

  func startListening() async {
    guard !isStartingRecognition, !isSpeechRecognitionActive else { return }
    isStartingRecognition = true
    defer { isStartingRecognition = false }

    // Request auth
    let speechAuth = await withCheckedContinuation { cont in
      SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status) }
    }
    guard speechAuth == .authorized else {
      errorMessage = "Speech recognition not authorized"
      return
    }

    let micAuth = await withCheckedContinuation { cont in
      if #available(iOS 17.0, *) {
        AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
      } else {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in cont.resume(returning: granted) }
      }
    }
    guard micAuth else {
      errorMessage = "Microphone not authorized"
      return
    }

    guard let recognizer = speechRecognizer, recognizer.isAvailable else {
      errorMessage = "Speech recognizer not available"
      return
    }

    // Stop any existing
    stopRecognitionEngine()

    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playAndRecord, mode: .spokenAudio,
                                   options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
      try audioSession.setActive(true)

      let request = SFSpeechAudioBufferRecognitionRequest()
      request.shouldReportPartialResults = true
      request.taskHint = .dictation
      self.recognitionRequest = request

      // Create a fresh audio engine — reusing a stale engine causes format mismatch
      // when hardware sample rate changes (e.g. Bluetooth at 16kHz vs default 48kHz)
      audioEngine = AVAudioEngine()

      let inputNode = audioEngine.inputNode
      let recordingFormat = inputNode.outputFormat(forBus: 0)
      print("🎤 [Translation] Audio format: \(recordingFormat)")

      inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
        guard buffer.frameLength > 0 else { return }
        request.append(buffer)
      }

      audioEngine.prepare()
      try audioEngine.start()

      recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
        Task { @MainActor in
          guard let self = self else { return }

          if let result = result {
            let text = result.bestTranscription.formattedString
            self.currentPartialText = text

            if result.isFinal {
              self.handleFinalText(text)
            } else {
              self.scheduleAutoSend(text)
            }
          }

          if let error = error {
            let nsError = error as NSError
            // Ignore "no speech detected" (error code 1110) — just restart silently
            let isSilenceError = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110
            if !isSilenceError {
              print("⚠️ [Translation] Recognition error: \(error.localizedDescription)")
            }
            // Auto-restart if still listening
            if self.isListening && self.isSpeechRecognitionActive {
              self.stopRecognitionEngine()
              self.isListening = true // keep listening intent
              try? await Task.sleep(nanoseconds: 300_000_000)
              if self.isListening {
                await self.startListening()
              }
            }
          }
        }
      }

      isSpeechRecognitionActive = true
      isListening = true
      print("🎙 [Translation] Listening in \(sourceLanguage.displayName)")
    } catch {
      errorMessage = "Failed to start recognition: \(error.localizedDescription)"
      print("❌ [Translation] \(error.localizedDescription)")
    }
  }

  func stopListening() {
    isListening = false
    cancelAutoSend()
    stopRecognitionEngine()

    // Send any pending partial text
    let pending = currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !pending.isEmpty {
      handleFinalText(pending)
    }
  }

  func toggleListening() {
    if isListening {
      stopListening()
    } else {
      Task { await startListening() }
    }
  }

  func toggleAutoListening() {
    autoListening.toggle()
    if autoListening {
      if !isListening {
        Task { await startListening() }
      }
    } else {
      if isListening {
        stopListening()
      }
    }
  }

  private func stopRecognitionEngine() {
    recognitionTask?.cancel()
    recognitionTask = nil
    recognitionRequest?.endAudio()
    recognitionRequest = nil

    if audioEngine.isRunning {
      audioEngine.stop()
    }
    if audioEngine.inputNode.numberOfInputs > 0 {
      audioEngine.inputNode.removeTap(onBus: 0)
    }

    isSpeechRecognitionActive = false
  }

  // MARK: - Auto-send

  private func scheduleAutoSend(_ text: String) {
    cancelAutoSend()
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    autoSendTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(2.0 * 1_000_000_000))
      guard let self = self, !Task.isCancelled else { return }
      if self.currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed {
        self.handleFinalText(trimmed)
      }
    }
  }

  private func cancelAutoSend() {
    autoSendTask?.cancel()
    autoSendTask = nil
  }

  // MARK: - Translation

  private func handleFinalText(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    // Don't re-translate the same text
    if entries.last?.sourceText == trimmed { return }

    currentPartialText = ""
    cancelAutoSend()

    // Cancel previous translation
    currentTranslationTask?.cancel()

    currentTranslationTask = Task {
      await translateText(trimmed)
    }

    // Restart recognition session so next phrase starts fresh
    // (otherwise SFSpeechRecognizer accumulates all speech into one transcript)
    if isListening {
      stopRecognitionEngine()
      isListening = true
      Task {
        try? await Task.sleep(nanoseconds: 200_000_000)
        if isListening { await startListening() }
      }
    }
  }

  func translateText(_ text: String) async {
    isTranslating = true
    errorMessage = nil

    do {
      let response = try await TranslationService.shared.translate(
        text: text, from: sourceLanguage, to: targetLanguage
      )

      if Task.isCancelled { isTranslating = false; return }

      let translated = response.translations?.first ?? response.text ?? ""
      let entry = TranslationEntry(
        sourceText: text,
        translatedText: translated,
        transcription: response.transcription,
        soundUrl: response.soundUrl,
        examples: response.examples ?? []
      )

      entries.append(entry)
      isTranslating = false

      // Speak the translation
      speakTranslation(translated)
      NotificationService.shared.sendIfBackground(
        title: "\(sourceLanguage.flag) → \(targetLanguage.flag) Translation",
        body: translated
      )
    } catch {
      if !Task.isCancelled {
        isTranslating = false
        errorMessage = error.localizedDescription
        print("❌ [Translation] \(error.localizedDescription)")
      }
    }
  }

  // MARK: - Image Translation

  func translateImage(_ image: UIImage) {
    currentImage = image
    isTranslatingImage = true

    // Use AI backend to extract text from image, then translate
    currentTranslationTask?.cancel()
    currentTranslationTask = Task {
      await performImageTranslation(image)
    }
  }

  private func performImageTranslation(_ image: UIImage) async {
    do {
      // Ask the AI backend to read text from the image
      let prompt: String
      switch sourceLanguage {
      case .russian:
        prompt = "Прочитай и верни ТОЛЬКО текст, который видишь на изображении. Без комментариев."
      case .spanish:
        prompt = "Lee y devuelve SOLO el texto que ves en la imagen. Sin comentarios."
      default:
        prompt = "Read and return ONLY the text you see in the image. No commentary."
      }

      let result = try await BackendService.shared.generateResponse(
        for: prompt, language: sourceLanguage.rawValue, image: image
      )

      if Task.isCancelled {
        await MainActor.run { isTranslatingImage = false; currentImage = nil }
        return
      }

      let extractedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !extractedText.isEmpty else {
        await MainActor.run {
          isTranslatingImage = false
          currentImage = nil
          errorMessage = "No text found in image"
        }
        return
      }

      print("📸 [Translation] Extracted text from image: \"\(extractedText)\"")

      // Now translate the extracted text
      let translation = try await TranslationService.shared.translate(
        text: extractedText, from: sourceLanguage, to: targetLanguage
      )

      if Task.isCancelled {
        await MainActor.run { isTranslatingImage = false; currentImage = nil }
        return
      }

      let translated = translation.translations?.first ?? translation.text ?? ""
      let entry = TranslationEntry(
        sourceText: extractedText,
        translatedText: translated,
        transcription: translation.transcription,
        soundUrl: translation.soundUrl,
        examples: translation.examples ?? []
      )

      await MainActor.run {
        entries.append(entry)
        isTranslatingImage = false
        currentImage = nil
        speakTranslation(translated)
        NotificationService.shared.sendIfBackground(
          title: "\(sourceLanguage.flag) → \(targetLanguage.flag) Image Translation",
          body: translated
        )
      }
    } catch {
      if !Task.isCancelled {
        await MainActor.run {
          isTranslatingImage = false
          currentImage = nil
          errorMessage = error.localizedDescription
        }
      }
    }
  }

  // MARK: - TTS & Audio Playback

  func speakTranslation(_ text: String) {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

    if speechSynthesizer.isSpeaking {
      speechSynthesizer.stopSpeaking(at: .immediate)
    }

    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: targetLanguage.speechLanguageCode)
      ?? AVSpeechSynthesisVoice(language: "en-US")
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
    utterance.volume = 0.8

    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playAndRecord, mode: .spokenAudio,
                                   options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
      try audioSession.setActive(true)
    } catch {
      print("⚠️ [Translation TTS] Audio session error: \(error.localizedDescription)")
    }

    speechSynthesizer.speak(utterance)
    isSpeaking = true
  }

  func playSoundUrl(_ urlString: String) {
    isPlayingAudio = true

    Task {
      do {
        let data = try await TranslationService.shared.downloadAudio(from: urlString)

        await MainActor.run {
          do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .spokenAudio,
                                         options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try audioSession.setActive(true)

            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.play()

            // Auto-reset after playback
            Task { @MainActor in
              try? await Task.sleep(nanoseconds: UInt64((audioPlayer?.duration ?? 2.0) * 1_000_000_000) + 500_000_000)
              self.isPlayingAudio = false
            }
          } catch {
            print("⚠️ [Translation] Audio playback error: \(error.localizedDescription)")
            isPlayingAudio = false
          }
        }
      } catch {
        await MainActor.run {
          print("⚠️ [Translation] Audio download error: \(error.localizedDescription)")
          isPlayingAudio = false
        }
      }
    }
  }

  func stopSpeaking() {
    if speechSynthesizer.isSpeaking {
      speechSynthesizer.stopSpeaking(at: .immediate)
    }
    audioPlayer?.stop()
    isSpeaking = false
    isPlayingAudio = false
  }

  // MARK: - Cleanup

  func clearHistory() {
    entries.removeAll()
    currentPartialText = ""
    errorMessage = nil
  }

  func cleanup() {
    stopListening()
    stopSpeaking()
    currentTranslationTask?.cancel()
    stopRecognitionEngine()
  }
}

// MARK: - Speech Synthesizer Delegate

private class SpeechSynthDelegate: NSObject, AVSpeechSynthesizerDelegate {
  var onSpeakingChanged: ((Bool) -> Void)?

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
    onSpeakingChanged?(true)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    onSpeakingChanged?(false)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    onSpeakingChanged?(false)
  }
}
