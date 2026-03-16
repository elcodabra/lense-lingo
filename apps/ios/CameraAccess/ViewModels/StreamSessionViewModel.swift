/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamSessionViewModel.swift
//
// Core view model demonstrating video streaming from Meta wearable devices using the DAT SDK.
// This class showcases the key streaming patterns: device selection, session management,
// video frame handling, photo capture, and error handling.
//

import MWDATCamera
import MWDATCore
import SwiftUI
import Speech
import AVFoundation

enum StreamingStatus {
  case streaming
  case waiting
  case stopped
}

@MainActor
class StreamSessionViewModel: ObservableObject {
  @Published var currentVideoFrame: UIImage?
  @Published var hasReceivedFirstFrame: Bool = false
  @Published var streamingStatus: StreamingStatus = .stopped
  @Published var showError: Bool = false
  @Published var errorMessage: String = ""
  @Published var hasActiveDevice: Bool = false
  
  // Video display control for energy saving
  @Published var shouldShowVideoDisplay: Bool {
    didSet {
      UserDefaults.standard.set(shouldShowVideoDisplay, forKey: "shouldShowVideoDisplay")
    }
  }

  var isStreaming: Bool {
    streamingStatus != .stopped
  }
  
  // Check if Start/Stop button should show Stop state
  // Show Stop when: manual sending is active, generating response, or recognition is active in manual mode
  var shouldShowStopButton: Bool {
    isManualSending || isGeneratingResponse || (isSpeechRecognitionActive && !autolistening)
  }

  // Timer properties
  @Published var activeTimeLimit: StreamTimeLimit = .noLimit
  @Published var remainingTime: TimeInterval = 0

  // Photo capture properties
  @Published var capturedPhoto: UIImage?
  @Published var showPhotoPreview: Bool = false

  // Speech recognition UI properties
  @Published var recognizedText: String = ""
  @Published var recognizedLines: [String] = []
  @Published var currentPartialText: String = ""
  @Published var isSpeechRecognitionActive: Bool = false
  @Published var autolistening: Bool = false // Auto mode for speech recognition
  @Published var isManualSending: Bool = false // Flag to show listening status during manual send
  
  // AI response properties
  @Published var aiResponses: [String: String] = [:] // Maps recognized text to AI response
  @Published var responseSources: [String: String] = [:] // Maps recognized text to response source ("gemini" or "chatgpt")
  @Published var isGeneratingResponse: Bool = false
  @Published var lastAIResponse: String = ""
  @Published var currentAIImage: UIImage? // Image currently being sent to AI
  
  private var lastFinalizedText: String = ""
  private var currentAIResponseTask: Task<Void, Never>? // Track current AI response task for cancellation

  private var timerTask: Task<Void, Never>?
  // The core DAT SDK StreamSession - handles all streaming operations
  private var streamSession: StreamSession
  // Listener tokens are used to manage DAT SDK event subscriptions
  private var stateListenerToken: AnyListenerToken?
  private var videoFrameListenerToken: AnyListenerToken?
  private var errorListenerToken: AnyListenerToken?
  private var photoDataListenerToken: AnyListenerToken?
  private let wearables: WearablesInterface
  private let deviceSelector: AutoDeviceSelector
  private var deviceMonitorTask: Task<Void, Never>?
  
  // Language preference - observed from WearablesViewModel
  @Published var selectedLanguage: AppLanguage = .english
  
  // Speech recognition properties
  private var speechRecognizer: SFSpeechRecognizer?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private let audioEngine = AVAudioEngine()
  private var isStartingSpeechRecognition: Bool = false
  private var isIntentionallyStopping: Bool = false
  
  // Text-to-speech properties
  private let speechSynthesizer = AVSpeechSynthesizer()
  private let speechSynthesizerDelegate = SpeechSynthesizerDelegate()
  @Published var isSpeaking: Bool = false
  
  // Auto-send timer for non-finalized text
  private var autoSendTask: Task<Void, Never>?
  private var lastPartialUpdateTime: Date?
  private let autoSendDelay: TimeInterval = 3.0 // Send after 3 seconds of silence

  init(wearables: WearablesInterface, selectedLanguage: AppLanguage = .english) {
    self.wearables = wearables
    self.selectedLanguage = selectedLanguage
    // Load video display preference or default to true
    self.shouldShowVideoDisplay = UserDefaults.standard.object(forKey: "shouldShowVideoDisplay") as? Bool ?? true
    // Let the SDK auto-select from available devices
    self.deviceSelector = AutoDeviceSelector(wearables: wearables)
    let config = StreamSessionConfig(
      videoCodec: VideoCodec.raw,
      resolution: StreamingResolution.low,
      frameRate: 24)
    streamSession = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)

    // Monitor device availability
    deviceMonitorTask = Task { @MainActor in
      for await device in deviceSelector.activeDeviceStream() {
        self.hasActiveDevice = device != nil
      }
    }

    // Subscribe to session state changes using the DAT SDK listener pattern
    // State changes tell us when streaming starts, stops, or encounters issues
    stateListenerToken = streamSession.statePublisher.listen { [weak self] state in
      Task { @MainActor [weak self] in
        self?.updateStatusFromState(state)
      }
    }

    // Subscribe to video frames from the device camera
    // Each VideoFrame contains the raw camera data that we convert to UIImage
    videoFrameListenerToken = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
      Task { @MainActor [weak self] in
        guard let self else { return }

        if let image = videoFrame.makeUIImage() {
          self.currentVideoFrame = image
          if !self.hasReceivedFirstFrame {
            self.hasReceivedFirstFrame = true
          }
        }
      }
    }

    // Subscribe to streaming errors
    // Errors include device disconnection, streaming failures, etc.
    errorListenerToken = streamSession.errorPublisher.listen { [weak self] error in
      Task { @MainActor [weak self] in
        guard let self else { return }
        let newErrorMessage = formatStreamingError(error)
        if newErrorMessage != self.errorMessage {
          showError(newErrorMessage)
        }
      }
    }

    updateStatusFromState(streamSession.state)

    // Subscribe to photo capture events
    // PhotoData contains the captured image in the requested format (JPEG/HEIC)
    photoDataListenerToken = streamSession.photoDataPublisher.listen { [weak self] photoData in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let uiImage = UIImage(data: photoData.data) {
          self.capturedPhoto = uiImage
          self.showPhotoPreview = true
        }
      }
    }
    
    // Initialize speech recognizer
    setupSpeechRecognition()
    
    // Setup text-to-speech delegate
    speechSynthesizerDelegate.onSpeakingChanged = { [weak self] isSpeaking in
      Task { @MainActor in
        self?.isSpeaking = isSpeaking
      }
    }
    speechSynthesizerDelegate.onSpeechFinished = { [weak self] in
      Task { @MainActor in
        guard let self = self else { return }
        self.isSpeaking = false
        
        print("🔧 [TTS] Speech finished")
        
        // Since we use .playAndRecord category, speech recognition should continue running
        // We don't need to switch categories or restart recognition
        // Just verify that recognition is still active
        if self.isStreaming {
          if !self.isSpeechRecognitionActive {
            print("🔄 [TTS] Speech recognition became inactive after TTS, restarting...")
            await self.startSpeechRecognition()
          } else if !self.audioEngine.isRunning {
            print("🔄 [TTS] Audio engine stopped after TTS, restarting speech recognition...")
            await self.startSpeechRecognition()
          } else {
            print("✅ [TTS] Speech recognition is still active after TTS completion")
            // Ensure audio session is still properly configured
            do {
              let audioSession = AVAudioSession.sharedInstance()
              // Keep using .playAndRecord to allow both recognition and future playback
              try audioSession.setCategory(.playAndRecord, 
                                           mode: .spokenAudio, 
                                           options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
              try audioSession.setActive(true, options: [])
              print("✅ [TTS] Audio session reconfirmed for continuous recognition")
            } catch {
              print("⚠️ [TTS] Failed to reconfigure audio session: \(error.localizedDescription)")
            }
          }
        } else {
          // If we're not streaming, just deactivate
          do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
          } catch {
            print("⚠️ [TTS] Failed to deactivate audio session: \(error.localizedDescription)")
          }
        }
      }
    }
    speechSynthesizer.delegate = speechSynthesizerDelegate
  }

  func handleStartStreaming() async {
    let permission = Permission.camera
    do {
      let status = try await wearables.checkPermissionStatus(permission)
      if status == .granted {
        await startSession()
        return
      }
      let requestStatus = try await wearables.requestPermission(permission)
      if requestStatus == .granted {
        await startSession()
        return
      }
      showError("Permission denied")
    } catch {
      showError("Permission error: \(error.description)")
    }
  }

  func startSession() async {
    // Reset to unlimited time when starting a new stream
    activeTimeLimit = .noLimit
    remainingTime = 0
    stopTimer()

    await streamSession.start()
    // Start speech recognition when streaming starts only if autolistening is enabled
    if autolistening {
      await startSpeechRecognition()
    }
  }

  private func showError(_ message: String) {
    errorMessage = message
    showError = true
  }

  func stopSession() async {
    stopTimer()
    stopSpeechRecognition()
    await streamSession.stop()
  }

  func dismissError() {
    showError = false
    errorMessage = ""
  }

  func setTimeLimit(_ limit: StreamTimeLimit) {
    activeTimeLimit = limit
    remainingTime = limit.durationInSeconds ?? 0

    if limit.isTimeLimited {
      startTimer()
    } else {
      stopTimer()
    }
  }

  func capturePhoto() {
    streamSession.capturePhoto(format: .jpeg)
  }

  func dismissPhotoPreview() {
    showPhotoPreview = false
    capturedPhoto = nil
  }

  private func startTimer() {
    stopTimer()
    timerTask = Task { @MainActor [weak self] in
      while let self, remainingTime > 0 {
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
        guard !Task.isCancelled else { break }
        remainingTime -= 1
      }
      if let self, !Task.isCancelled {
        await stopSession()
      }
    }
  }

  private func stopTimer() {
    timerTask?.cancel()
    timerTask = nil
  }

  private func updateStatusFromState(_ state: StreamSessionState) {
    switch state {
    case .stopped:
      currentVideoFrame = nil
      streamingStatus = .stopped
      // Stop speech recognition when streaming stops
      if isSpeechRecognitionActive {
        stopSpeechRecognition()
      }
    case .waitingForDevice, .starting, .stopping, .paused:
      streamingStatus = .waiting
    case .streaming:
      streamingStatus = .streaming
      // Ensure speech recognition starts when streaming is active only if autolistening is enabled
      if !isSpeechRecognitionActive && autolistening {
        Task {
          await startSpeechRecognition()
        }
      }
    }
  }

  private func formatStreamingError(_ error: StreamSessionError) -> String {
    switch error {
    case .internalError:
      return "An internal error occurred. Please try again."
    case .deviceNotFound:
      return "Device not found. Please ensure your device is connected."
    case .deviceNotConnected:
      return "Device not connected. Please check your connection and try again."
    case .timeout:
      return "The operation timed out. Please try again."
    case .videoStreamingError:
      return "Video streaming failed. Please try again."
    case .audioStreamingError:
      return "Audio streaming failed. Please try again."
    case .permissionDenied:
      return "Camera permission denied. Please grant permission in Settings."
    @unknown default:
      return "An unknown streaming error occurred."
    }
  }
  
  // MARK: - Speech Recognition
  
  private func setupSpeechRecognition() {
    // Use selected language preference
    print("🌍 [Speech Recognition] setupSpeechRecognition called with selectedLanguage: \(selectedLanguage.displayName)")
    let targetLocale: Locale
    let languageName: String
    
    switch selectedLanguage {
    case .russian:
      targetLocale = Locale(identifier: "ru-RU")
      languageName = "Russian"
    case .english:
      targetLocale = Locale(identifier: "en-US")
      languageName = "English"
    case .spanish:
      targetLocale = Locale(identifier: "es-ES")
      languageName = "Spanish"
    case .system:
      targetLocale = Locale.current
      languageName = "System (\(Locale.current.language.languageCode?.identifier ?? "unknown"))"
    }
    
    print("🌍 [Speech Recognition] Target locale: \(targetLocale.identifier) for language: \(languageName)")
    
    // Try to use selected language first
    if let recognizer = SFSpeechRecognizer(locale: targetLocale), recognizer.isAvailable {
      speechRecognizer = recognizer
      print("🌍 [Speech Recognition] Using \(languageName) locale: \(targetLocale.identifier)")
    } else {
      // Fallback to alternatives
      let russianLocale = Locale(identifier: "ru-RU")
      let englishLocale = Locale(identifier: "en-US")
      let spanishLocale = Locale(identifier: "es-ES")
      
      // Try Russian if not selected
      if selectedLanguage != .russian {
        if let russianRecognizer = SFSpeechRecognizer(locale: russianLocale), russianRecognizer.isAvailable {
          speechRecognizer = russianRecognizer
          print("🌍 [Speech Recognition] Using Russian locale (ru-RU) as fallback")
        }
      }
      
      // Try Spanish if not selected and Russian not available
      if speechRecognizer == nil && selectedLanguage != .spanish {
        if let spanishRecognizer = SFSpeechRecognizer(locale: spanishLocale), spanishRecognizer.isAvailable {
          speechRecognizer = spanishRecognizer
          print("🌍 [Speech Recognition] Using Spanish locale (es-ES) as fallback")
        }
      }
      
      // Try English if not selected and others not available
      if speechRecognizer == nil && selectedLanguage != .english {
        if let englishRecognizer = SFSpeechRecognizer(locale: englishLocale), englishRecognizer.isAvailable {
          speechRecognizer = englishRecognizer
          print("🌍 [Speech Recognition] Using English locale (en-US) as fallback")
        }
      }
      
      // Final fallback - current locale
      if speechRecognizer == nil {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        if let recognizer = speechRecognizer, recognizer.isAvailable {
          print("🌍 [Speech Recognition] Using current locale: \(Locale.current.identifier)")
        }
      }
    }
    
    guard let recognizer = speechRecognizer, recognizer.isAvailable else {
      print("⚠️ [Speech Recognition] Speech recognizer is not available for selected language: \(languageName)")
      print("   Attempted locale: \(targetLocale.identifier)")
      return
    }
    
    print("✅ [Speech Recognition] Speech recognizer configured successfully")
    print("   Selected language: \(languageName)")
    print("   Locale: \(recognizer.locale.identifier)")
    print("   Supports on-device recognition: \(recognizer.supportsOnDeviceRecognition)")
  }
  
  func updateLanguage(_ newLanguage: AppLanguage) async {
    print("🌍 [Language] Updating language from \(selectedLanguage.displayName) to \(newLanguage.displayName)")
    selectedLanguage = newLanguage
    // Reconfigure speech recognizer with new language
    setupSpeechRecognition()
    print("🌍 [Language] Speech recognizer reconfigured for: \(newLanguage.displayName)")
    // If recognition is active, restart it with new language
    if isSpeechRecognitionActive {
      print("🌍 [Language] Restarting active speech recognition with new language")
      stopSpeechRecognition()
      try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
      await startSpeechRecognition()
    } else {
      print("🌍 [Language] Speech recognition not active, will use new language when started")
    }
  }
  
  private func startSpeechRecognition() async {
    // Prevent multiple simultaneous starts
    guard !isStartingSpeechRecognition && !isSpeechRecognitionActive else {
      return
    }
    
    isStartingSpeechRecognition = true
    defer { isStartingSpeechRecognition = false }
    
    // Request authorization
    let authStatus = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }
    guard authStatus == .authorized else {
      print("Speech recognition authorization denied")
      isSpeechRecognitionActive = false
      return
    }
    
    // Request microphone permission
    let micAuthStatus = await withCheckedContinuation { continuation in
      if #available(iOS 17.0, *) {
        AVAudioApplication.requestRecordPermission { granted in
          continuation.resume(returning: granted)
        }
      } else {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
          continuation.resume(returning: granted)
        }
      }
    }
    guard micAuthStatus else {
      print("Microphone permission denied")
      isSpeechRecognitionActive = false
      return
    }
    
    // Stop any existing recognition before starting new one
    if isSpeechRecognitionActive {
      isIntentionallyStopping = true
      stopSpeechRecognition()
      // Give a brief moment for cleanup before resetting the flag
      try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
      isIntentionallyStopping = false
    }
    
    // Ensure speech recognizer is configured with current language
    // This is important if language was changed after init but before recognition started
    let expectedLocale = selectedLanguage.locale
    if speechRecognizer == nil || speechRecognizer?.locale.identifier != expectedLocale.identifier {
      print("🌍 [Speech Recognition] Reconfiguring recognizer before start")
      print("   Current recognizer locale: \(speechRecognizer?.locale.identifier ?? "nil")")
      print("   Expected locale: \(expectedLocale.identifier) for language: \(selectedLanguage.displayName)")
      setupSpeechRecognition()
    }
    
    guard let recognizer = speechRecognizer, recognizer.isAvailable else {
      print("⚠️ [Speech Recognition] Cannot start: recognizer not available for language: \(selectedLanguage.displayName)")
      isSpeechRecognitionActive = false
      return
    }
    
    print("🌍 [Speech Recognition] Starting recognition with locale: \(recognizer.locale.identifier) (selected: \(selectedLanguage.displayName))")
    
    do {
      let audioSession = AVAudioSession.sharedInstance()
      // Use .playAndRecord from the start to support both recognition and future playback
      // This allows speech recognition to continue even when TTS starts
      try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
      try audioSession.setActive(true, options: [])
      
      recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
      
      guard let recognitionRequest = recognitionRequest else {
        print("Unable to create recognition request")
        isSpeechRecognitionActive = false
        return
      }
      
      recognitionRequest.shouldReportPartialResults = true
      
      // Set task hint for better multi-language recognition
      // This helps the recognizer handle both Russian and English
      recognitionRequest.taskHint = .dictation
      
      let inputNode = audioEngine.inputNode
      let recordingFormat = inputNode.outputFormat(forBus: 0)
      
      inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
        recognitionRequest.append(buffer)
      }
      
      audioEngine.prepare()
      try audioEngine.start()
      
      // Use the current speechRecognizer which should be configured with the selected language
      guard let currentRecognizer = speechRecognizer else {
        print("⚠️ [Speech Recognition] speechRecognizer is nil, cannot create recognition task")
        isSpeechRecognitionActive = false
        return
      }
      
      print("🌍 [Speech Recognition] Creating recognition task with recognizer locale: \(currentRecognizer.locale.identifier)")
      
      recognitionTask = currentRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
        guard let self = self else { return }
        
        Task { @MainActor in
          if let result = result {
            let transcription = result.bestTranscription
            let recognizedText = transcription.formattedString
            
            print("🎤 [Speech Recognition] Received result")
            print("   isFinal: \(result.isFinal)")
            print("   Full text: \"\(recognizedText)\"")
            print("   Last finalized text: \"\(self.lastFinalizedText)\"")
            
            if result.isFinal {
              print("✅ [Speech Recognition] Result is FINAL")
              // When phrase is finalized, extract only the new text
              let newText = self.extractNewText(from: transcription, after: self.lastFinalizedText)
              print("   Extracted new text: \"\(newText)\"")
              print("   New text length: \(newText.count)")
              print("   New text after trimming: \"\(newText.trimmingCharacters(in: .whitespacesAndNewlines))\"")
              
              if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.recognizedLines.append(newText)
                // Store only the new finalized text (the phrase we just added)
                // This helps us detect when a completely new phrase starts after a pause
                self.lastFinalizedText = newText
                self.currentPartialText = ""
                self.updateRecognizedTextDisplay()
                // Log final transcription
                print("✅ [Speech Recognition] Final text saved: \"\(newText)\"")
                print("🚀 [Speech Recognition] Calling generateAIResponse...")
                
                // Cancel any pending auto-send task since we have final text
                self.cancelAutoSendTask()
                
                // Cancel previous AI response task if it's still running (interrupt)
                if let previousTask = self.currentAIResponseTask {
                  print("🛑 [Speech Recognition] Canceling previous AI response task (interrupted by new request)")
                  previousTask.cancel()
                }
                
                // Stop current speech if speaking (interrupt)
                if self.isSpeaking {
                  print("🛑 [Speech Recognition] Stopping current speech (interrupted by new request)")
                  self.stopSpeaking()
                }
                
                // Call AI API to generate response (Gemini with ChatGPT fallback)
                // In manual mode (autolistening off), don't check for image
                let newTask = Task {
                  print("📞 [Speech Recognition] Task started for AI response generation")
                  if self.autolistening {
                    // Auto mode - check if image is needed
                    await self.generateAIResponse(for: newText)
                  } else {
                    // Manual mode - no image check
                    await self.generateAIResponseWithoutImage(for: newText)
                  }
                  print("📞 [Speech Recognition] AI response generation task completed")
                }
                self.currentAIResponseTask = newTask
              } else {
                print("⚠️ [Speech Recognition] New text is empty after extraction, skipping AI call")
              }
            } else {
              // Extract only the new partial text (being spoken)
              let newPartialText = self.extractNewText(from: transcription, after: self.lastFinalizedText)
              print("   Partial text extracted: \"\(newPartialText)\"")
              
              // Only update if we have new text (not empty or just whitespace)
              if !newPartialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.currentPartialText = newPartialText
                self.lastPartialUpdateTime = Date()
                self.updateRecognizedTextDisplay()
                // Log the recognized text
                print("🎤 [Speech Recognition] Partial text updated: \"\(newPartialText)\"")
                
                // Schedule auto-send if text hasn't been sent yet (only in auto mode)
                if self.autolistening {
                  self.scheduleAutoSendIfNeeded(partialText: newPartialText)
                }
              }
            }
          }
          
          if let error = error {
            // Don't handle errors if we're intentionally stopping
            if self.isIntentionallyStopping {
              print("Speech recognition stopped intentionally - ignoring error")
              return
            }
            
            let nsError = error as NSError
            let errorDescription = error.localizedDescription.lowercased()
            
            // Check if it's a cancellation error (code 216 or contains "canceled")
            let isCancellationError = nsError.code == 216 || 
                                     errorDescription.contains("canceled") || 
                                     errorDescription.contains("cancelled")
            
            if isCancellationError {
              // This is a cancellation error - only restart if autolistening is enabled
              print("Speech recognition canceled (code: \(nsError.code), domain: \(nsError.domain))")
              if self.isStreaming && !self.isIntentionallyStopping && !self.isSpeechRecognitionActive && self.autolistening {
                // Restart after a brief delay only if autolistening is on
                Task {
                  try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                  if self.isStreaming && !self.isIntentionallyStopping && !self.isSpeechRecognitionActive && self.autolistening {
                    print("Restarting speech recognition after cancellation (autolistening is on)")
                    await self.startSpeechRecognition()
                  }
                }
              }
              return
            }
            
            // For other errors, log and handle
            print("Speech recognition error: \(error.localizedDescription) (code: \(nsError.code), domain: \(nsError.domain))")
            // Clear partial text on error
            self.currentPartialText = ""
            self.updateRecognizedTextDisplay()
            
            // If we're still streaming and it's not an intentional stop, restart only if autolistening is enabled
            if self.isStreaming && !self.isIntentionallyStopping && !self.isSpeechRecognitionActive && self.autolistening {
              // Restart after a brief delay to avoid rapid restart loops
              Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                if self.isStreaming && !self.isIntentionallyStopping && !self.isSpeechRecognitionActive && self.autolistening {
                  print("Restarting speech recognition after error (autolistening is on)")
                  await self.startSpeechRecognition()
                }
              }
            } else if !self.isStreaming {
              self.stopSpeechRecognition()
            }
          }
        }
      }
      
      // Mark speech recognition as active
      isSpeechRecognitionActive = true
      isIntentionallyStopping = false
    } catch {
      print("Failed to start speech recognition: \(error.localizedDescription)")
      isSpeechRecognitionActive = false
      isIntentionallyStopping = false
      // If we're still streaming, try to restart after a delay only if autolistening is enabled
      if isStreaming && autolistening {
        Task { @MainActor in
          try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
          if self.isStreaming && !self.isIntentionallyStopping && self.autolistening {
            await self.startSpeechRecognition()
          }
        }
      } else {
        stopSpeechRecognition()
      }
    }
  }
  
  private func stopSpeechRecognition() {
    // Cancel recognition task first
    recognitionTask?.cancel()
    recognitionTask = nil
    
    // End audio on request
    recognitionRequest?.endAudio()
    recognitionRequest = nil
    
    // Stop audio engine
    if audioEngine.isRunning {
      audioEngine.stop()
    }
    
    // Safely remove tap if it exists
    if audioEngine.inputNode.numberOfInputs > 0 {
      audioEngine.inputNode.removeTap(onBus: 0)
    }
    
    // Cancel current AI response task if running
    if let aiTask = currentAIResponseTask {
      print("🛑 [Speech Recognition] Canceling AI response task during stop")
      aiTask.cancel()
      currentAIResponseTask = nil
    }
    
    // Deactivate audio session
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      print("Failed to deactivate audio session: \(error.localizedDescription)")
    }
    
    isSpeechRecognitionActive = false
    
    // Cancel auto-send task
    cancelAutoSendTask()
    
    // Stop speech synthesis
    stopSpeaking()
    
    // Only clear text if we're fully stopping (not restarting)
    if !isStreaming {
      recognizedText = ""
      recognizedLines = []
      currentPartialText = ""
      lastFinalizedText = ""
      aiResponses = [:]
      responseSources = [:]
      lastAIResponse = ""
      isGeneratingResponse = false
      lastPartialUpdateTime = nil
    }
  }
  
  // MARK: - Text-to-Speech
  
  private func speakText(_ text: String) {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      print("⚠️ [TTS] Empty text, skipping speech")
      return
    }
    
    // Stop any current speech
    if speechSynthesizer.isSpeaking {
      print("🛑 [TTS] Stopping current speech to start new one")
      speechSynthesizer.stopSpeaking(at: .immediate)
    }
    
    // Remove "Error:" prefix if present for better speech
    let textToSpeak = text.replacingOccurrences(of: "Error: ", with: "")
    
    print("🔊 [TTS] Starting speech synthesis")
    print("   Text to speak: \"\(textToSpeak)\"")
    print("   Text length: \(textToSpeak.count) characters")
    
    // Check if audio engine is running before switching audio session
    let wasAudioEngineRunning = audioEngine.isRunning
    print("   Audio engine was running: \(wasAudioEngineRunning)")
    print("   Speech recognition is active: \(isSpeechRecognitionActive)")
    
    let utterance = AVSpeechUtterance(string: textToSpeak)
    
    // Configure voice settings - use selected language preference
    let targetLanguage: String
    let languageName: String
    
    switch selectedLanguage {
    case .russian:
      targetLanguage = "ru-RU"
      languageName = "Russian"
    case .spanish:
      targetLanguage = "es-ES"
      languageName = "Spanish"
    case .english, .system:
      targetLanguage = "en-US"
      languageName = "English"
    }
    
    print("🔊 [TTS] Using language: \(languageName)")
    
    // Try selected language first, then fallback to English
    utterance.voice = AVSpeechSynthesisVoice(language: targetLanguage) ?? 
                      AVSpeechSynthesisVoice(language: "en-US") ?? 
                      AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en-US")
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9 // Slightly slower for clarity
    utterance.pitchMultiplier = 1.0
    utterance.volume = 0.8
    
    // Configure audio session for speech
    // Use .playAndRecord category to support both recognition and playback simultaneously
    // This allows speech recognition to continue listening even during speech playback
    do {
      let audioSession = AVAudioSession.sharedInstance()
      print("🔧 [TTS] Configuring audio session for simultaneous speech recognition and playback")
      
      // Use .playAndRecord with options that allow both recording and playback
      // .mixWithOthers and .allowBluetooth allow speech recognition to continue
      try audioSession.setCategory(.playAndRecord, 
                                   mode: .spokenAudio, 
                                   options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
      
      // Activate without notifyOthersOnDeactivation to keep audio engine running
      // This is critical to keep speech recognition active during playback
      try audioSession.setActive(true, options: [])
      
      print("✅ [TTS] Audio session configured for simultaneous operation")
      print("   Audio engine should continue running: \(audioEngine.isRunning)")
      
      // Ensure speech recognition audio engine is still running
      if !audioEngine.isRunning && isSpeechRecognitionActive && isStreaming {
        print("⚠️ [TTS] Audio engine stopped during TTS setup, but we'll keep recognition active")
        // Don't restart here as it might conflict with TTS
        // The recognition task should continue if the audio session supports it
      }
    } catch {
      print("⚠️ [TTS] Failed to configure audio session: \(error.localizedDescription)")
      print("   Error code: \((error as NSError).code)")
      print("   Error domain: \((error as NSError).domain)")
      // Continue anyway - speech synthesizer might still work
    }
    
    speechSynthesizer.speak(utterance)
    isSpeaking = true
    print("✅ [TTS] Speech started (speech recognition should continue in background)")
  }
  
  private func stopSpeaking() {
    if speechSynthesizer.isSpeaking {
      print("🛑 [TTS] Stopping speech")
      speechSynthesizer.stopSpeaking(at: .immediate)
    }
    isSpeaking = false
  }
  
  // MARK: - Auto-send mechanism for non-finalized text
  
  private func scheduleAutoSendIfNeeded(partialText: String) {
    // Only schedule auto-send in auto mode (autolistening enabled)
    guard autolistening else {
      return
    }
    
    // Cancel existing task
    cancelAutoSendTask()
    
    // Don't auto-send if we already have a response for this text
    let trimmedText = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedText.isEmpty || aiResponses[trimmedText] != nil {
      return
    }
    
    print("⏰ [Speech Recognition] Scheduling auto-send in \(autoSendDelay)s for: \"\(trimmedText)\"")
    
    autoSendTask = Task { @MainActor [weak self] in
      guard let self = self else { return }
      
      try? await Task.sleep(nanoseconds: UInt64(self.autoSendDelay * 1_000_000_000))
      
      // Check if text hasn't been finalized and hasn't been sent yet
      if self.isStreaming && 
         !self.isIntentionallyStopping &&
         self.currentPartialText == trimmedText &&
         self.aiResponses[trimmedText] == nil {
        
        print("⏰ [Speech Recognition] Auto-send triggered for: \"\(trimmedText)\"")
        print("   Last update was \(self.lastPartialUpdateTime.map { String(format: "%.2f", Date().timeIntervalSince($0)) } ?? "unknown")s ago")
        
        // Treat this as final text and send
        if !trimmedText.isEmpty {
          self.recognizedLines.append(trimmedText)
          self.lastFinalizedText = trimmedText
          self.currentPartialText = ""
          self.updateRecognizedTextDisplay()
          
          // Cancel previous AI response task if it's still running (interrupt)
          if let previousTask = self.currentAIResponseTask {
            print("🛑 [Auto-send] Canceling previous AI response task (interrupted by auto-send)")
            previousTask.cancel()
          }
          
          // Stop current speech if speaking (interrupt)
          if self.isSpeaking {
            print("🛑 [Auto-send] Stopping current speech (interrupted by auto-send)")
            self.stopSpeaking()
          }
          
          let newTask = Task {
            // In manual mode (autolistening off), don't check for image
            if self.autolistening {
              // Auto mode - check if image is needed
              await self.generateAIResponse(for: trimmedText)
            } else {
              // Manual mode - no image check
              await self.generateAIResponseWithoutImage(for: trimmedText)
            }
          }
          self.currentAIResponseTask = newTask
        }
      }
    }
  }
  
  private func cancelAutoSendTask() {
    autoSendTask?.cancel()
    autoSendTask = nil
  }
  
  // MARK: - AI Integration (Gemini with ChatGPT fallback)
  
  private var backendLanguageCode: String {
    switch selectedLanguage {
    case .russian: return "ru"
    case .spanish: return "es"
    case .english, .system: return "en"
    }
  }

  private func shouldUseImage(for text: String) async -> Bool {
    if Task.isCancelled { return false }

    print("🤔 [AI] Checking if image is needed for: \"\(text)\"")

    do {
      let needed = try await BackendService.shared.checkImageNeeded(for: text, language: backendLanguageCode)
      print("🤔 [AI] Backend says image needed: \(needed)")
      if Task.isCancelled { return false }
      return needed
    } catch {
      if Task.isCancelled { return false }
      print("⚠️ [AI] Backend image check failed: \(error.localizedDescription), defaulting to no image")
      return false
    }
  }
  
  private func generateAIResponseWithoutImage(for text: String) async {
    print("🟢 [AI] generateAIResponseWithoutImage called with text: \"\(text)\"")

    if Task.isCancelled {
      await MainActor.run { self.isGeneratingResponse = false; self.currentAIResponseTask = nil }
      return
    }

    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      await MainActor.run { self.isGeneratingResponse = false; self.currentAIResponseTask = nil }
      return
    }

    isGeneratingResponse = true

    do {
      let result = try await BackendService.shared.generateResponse(for: text, language: backendLanguageCode)

      if Task.isCancelled {
        await MainActor.run { self.isGeneratingResponse = false; self.currentAIResponseTask = nil }
        return
      }

      await MainActor.run {
        self.aiResponses[text] = result.text
        self.responseSources[text] = result.source
        self.lastAIResponse = result.text
        self.isGeneratingResponse = false
        self.currentAIResponseTask = nil
        print("✅ [AI] Backend response: \(result.source) in \(result.durationMs)ms")
        self.speakText(result.text)
      }
    } catch {
      if Task.isCancelled {
        await MainActor.run { self.isGeneratingResponse = false; self.currentAIResponseTask = nil }
        return
      }
      await MainActor.run {
        self.isGeneratingResponse = false
        self.currentAIResponseTask = nil
        self.aiResponses[text] = "Error: \(error.localizedDescription)"
        self.responseSources[text] = "error"
        self.lastAIResponse = "Error: \(error.localizedDescription)"
        print("❌ [AI] Backend error: \(error.localizedDescription)")
      }
    }
  }
  
  private func generateAIResponse(for text: String) async {
    print("🟢 [AI] generateAIResponse called with text: \"\(text)\"")

    if Task.isCancelled {
      await MainActor.run { self.isGeneratingResponse = false; self.currentAIResponseTask = nil }
      return
    }

    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      await MainActor.run { self.isGeneratingResponse = false; self.currentAIResponseTask = nil }
      return
    }

    isGeneratingResponse = true

    // Check if image is needed via backend
    let needsImage = await shouldUseImage(for: text)
    if Task.isCancelled {
      await MainActor.run { self.isGeneratingResponse = false; self.currentAIImage = nil; self.currentAIResponseTask = nil }
      return
    }

    let image = needsImage ? currentVideoFrame : nil
    await MainActor.run {
      self.currentAIImage = image
    }

    if needsImage {
      print("📸 [AI] Image needed, frame available: \(image != nil)")
    }

    do {
      let result = try await BackendService.shared.generateResponse(
        for: text, language: backendLanguageCode, image: image
      )

      if Task.isCancelled {
        await MainActor.run { self.isGeneratingResponse = false; self.currentAIImage = nil; self.currentAIResponseTask = nil }
        return
      }

      await MainActor.run {
        self.aiResponses[text] = result.text
        self.responseSources[text] = result.source
        self.lastAIResponse = result.text
        self.isGeneratingResponse = false
        self.currentAIImage = nil
        self.currentAIResponseTask = nil
        print("✅ [AI] Backend response: \(result.source) in \(result.durationMs)ms")
        self.speakText(result.text)
      }
    } catch {
      if Task.isCancelled {
        await MainActor.run { self.isGeneratingResponse = false; self.currentAIImage = nil; self.currentAIResponseTask = nil }
        return
      }
      await MainActor.run {
        self.isGeneratingResponse = false
        self.currentAIImage = nil
        self.currentAIResponseTask = nil
        self.aiResponses[text] = "Error: \(error.localizedDescription)"
        self.responseSources[text] = "error"
        self.lastAIResponse = "Error: \(error.localizedDescription)"
        print("❌ [AI] Backend error: \(error.localizedDescription)")
      }
    }
  }
  
  private func updateRecognizedTextDisplay() {
    var allText = recognizedLines.joined(separator: "\n")
    if !currentPartialText.isEmpty {
      if !allText.isEmpty {
        allText += "\n"
      }
      allText += currentPartialText
    }
    recognizedText = allText
  }
  
  private func extractNewText(from transcription: SFTranscription, after lastText: String) -> String {
    let fullText = transcription.formattedString
    
    // If there's no previous finalized text, return the full text
    guard !lastText.isEmpty else {
      return fullText
    }
    
    // If full text is exactly the same as last text, there's no new text
    if fullText == lastText {
      return ""
    }
    
    // Check if full text contains the last finalized text
    if let range = fullText.range(of: lastText, options: [.caseInsensitive, .diacriticInsensitive]) {
      // Found lastText in fullText - extract text after it
      let afterRange = range.upperBound
      if afterRange < fullText.endIndex {
        let remaining = String(fullText[afterRange...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
          return remaining
        }
      }
      return ""
    }
    
    // If full text doesn't contain lastText, it might be:
    // 1. A completely new phrase after a long pause (recognition restarted)
    // 2. A phrase that doesn't match exactly (different capitalization/punctuation)
    
    // Try using segments to find where new text starts
    let segments = transcription.segments
    if !segments.isEmpty {
      let lastTextLower = lastText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
      let lastTextWords = lastTextLower.components(separatedBy: CharacterSet.whitespaces).filter { !$0.isEmpty }
      
      // If we have no words in lastText, return full text
      guard !lastTextWords.isEmpty else {
        return fullText
      }
      
      var newTextSegments: [SFTranscriptionSegment] = []
      var foundNewTextStart = false
      
      for segment in segments {
        let segmentText = segment.substring.lowercased()
        
        // Check if this segment word is in the last finalized text
        if foundNewTextStart {
          // We've already found the start of new text, add all subsequent segments
          newTextSegments.append(segment)
        } else if !lastTextWords.contains(segmentText) {
          // This segment is not in lastText, so it's new text
          foundNewTextStart = true
          newTextSegments.append(segment)
        } else {
          // This segment is in lastText, check if we're at the end of lastText
          // by comparing cumulative text
          let currentSegmentsText = (newTextSegments + [segment]).map { $0.substring }.joined(separator: " ").lowercased()
          if !lastTextLower.hasPrefix(currentSegmentsText) {
            // We've gone past where lastText would be, start collecting new segments
            foundNewTextStart = true
            newTextSegments.append(segment)
          }
        }
      }
      
      // If we found new segments, return them
      if !newTextSegments.isEmpty {
        let extracted = newTextSegments.map { $0.substring }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !extracted.isEmpty {
          return extracted
        }
      }
      
      // If no new segments found but fullText doesn't contain lastText,
      // it's likely a new phrase after a pause - return full text
      return fullText
    }
    
    // If no segments available and fullText doesn't contain lastText,
    // it's probably a new phrase after a pause
    return fullText
  }
  
  // MARK: - Auto Listening Control
  
  func toggleAutolistening() {
    autolistening.toggle()
    
    if autolistening {
      // Enable auto listening - start speech recognition if streaming
      if isStreaming && !isSpeechRecognitionActive {
        Task {
          await startSpeechRecognition()
        }
      }
    } else {
      // Disable auto listening - stop speech recognition
      if isSpeechRecognitionActive {
        stopSpeechRecognition()
      }
    }
  }
  
  // MARK: - Manual Send Functions
  
  func manualSendAudio() {
    // If already sending/recognizing, stop instead
    if shouldShowStopButton {
      stopManualSend()
      return
    }
    
    // Show listening status immediately when Start button is pressed
    isManualSending = true
    
    // Start recognition if not already active (needed to capture audio)
    if !isSpeechRecognitionActive {
      Task {
        await startSpeechRecognition()
        // Wait a moment for recognition to start and capture audio
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        await performManualAudioSend()
      }
    } else {
      // Recognition is already active, proceed immediately
      Task {
        await performManualAudioSend()
      }
    }
  }
  
  func stopManualSend() {
    Task { @MainActor in
      print("🛑 [Manual Send] Stopping manual send and recognition")

      // Set flag to prevent automatic restart
      self.isIntentionallyStopping = true

      // Cancel auto-send task
      self.cancelAutoSendTask()

      // Grab the current partial text before clearing — send it if available
      let pendingText = self.currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)

      // Stop speech synthesis if speaking
      if self.isSpeaking {
        print("🛑 [Manual Send] Stopping speech")
        self.stopSpeaking()
      }

      // Cancel previous AI response task
      if let currentTask = self.currentAIResponseTask {
        print("🛑 [Manual Send] Canceling previous AI response task")
        currentTask.cancel()
        self.currentAIResponseTask = nil
      }

      // If we have pending text, send it to AI before stopping
      if !pendingText.isEmpty {
        print("📤 [Manual Send] Sending pending text on stop: \"\(pendingText)\"")

        // Clear partial text
        self.currentPartialText = ""
        self.updateRecognizedTextDisplay()

        // Stop speech recognition
        if !self.autolistening {
          self.stopSpeechRecognition()
        }

        // Send the text to AI
        await self.sendTextToAI(pendingText)

        // Reset intentional stopping flag
        try? await Task.sleep(nanoseconds: 500_000_000)
        self.isIntentionallyStopping = false
      } else {
        // No text to send — just clean up
        self.isManualSending = false
        self.isGeneratingResponse = false
        self.currentPartialText = ""
        self.updateRecognizedTextDisplay()

        if !self.autolistening {
          print("🛑 [Manual Send] Stopping speech recognition (autolistening is off)")
          self.stopSpeechRecognition()
          try? await Task.sleep(nanoseconds: 2_000_000_000)
          self.isIntentionallyStopping = false
        } else {
          try? await Task.sleep(nanoseconds: 500_000_000)
          self.isIntentionallyStopping = false
        }
      }
    }
  }
  
  private func performManualAudioSend() async {
    // Read text on main actor to ensure we get the latest value
    let textToSend: String = await MainActor.run {
      // First try to use current partial text if available
      if !self.currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let text = self.currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
        print("📤 [Manual Send] Using current partial text: \"\(text)\"")
        return text
      } else if !self.recognizedLines.isEmpty {
        // Use the last recognized line
        let text = self.recognizedLines.last ?? ""
        print("📤 [Manual Send] Using last recognized line: \"\(text)\"")
        return text
      } else {
        print("📤 [Manual Send] No text available in current state")
        return ""
      }
    }
    
    // If no text available, wait a bit more for recognition
    if textToSend.isEmpty {
      print("📤 [Manual Send] No text available yet, waiting for recognition...")
      try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 more second
      
      // Try again after waiting
      let textAfterWait: String = await MainActor.run {
        if !self.currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          let text = self.currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
          print("📤 [Manual Send] Found text after wait: \"\(text)\"")
          return text
        } else if !self.recognizedLines.isEmpty {
          let text = self.recognizedLines.last ?? ""
          print("📤 [Manual Send] Found last recognized line after wait: \"\(text)\"")
          return text
        } else {
          print("⚠️ [Manual Send] Still no audio text available to send")
          return ""
        }
      }
      
      guard !textAfterWait.isEmpty else {
        await MainActor.run {
          self.isManualSending = false
        }
        return
      }
      
      // Use the text we found after waiting
      await sendTextToAI(textAfterWait)
      return
    }
    
    guard !textToSend.isEmpty else {
      print("⚠️ [Manual Send] Text is empty, cannot send")
      await MainActor.run {
        self.isManualSending = false
      }
      return
    }
    
    print("📤 [Manual Send] Manually sending audio text: \"\(textToSend)\"")
    
    await sendTextToAI(textToSend)
  }
  
  private func sendTextToAI(_ textToSend: String) async {
    print("📤 [Manual Send] Sending text to AI: \"\(textToSend)\"")
    
    // Add to recognized lines if not already there
    if !recognizedLines.contains(textToSend) && currentPartialText != textToSend {
      await MainActor.run {
        self.recognizedLines.append(textToSend)
        self.lastFinalizedText = textToSend
      }
    }
    
    // Clear partial text
    await MainActor.run {
      self.currentPartialText = ""
      self.updateRecognizedTextDisplay()
    }
    
    // Cancel any pending auto-send task
    cancelAutoSendTask()
    
    // Cancel previous AI response task if it's still running
    await MainActor.run {
      if let previousTask = self.currentAIResponseTask {
        print("🛑 [Manual Send] Canceling previous AI response task")
        previousTask.cancel()
        self.currentAIResponseTask = nil
      }
      
      // Stop current speech if speaking
      if self.isSpeaking {
        print("🛑 [Manual Send] Stopping current speech")
        self.stopSpeaking()
      }
    }
    
    // Stop recognition after sending ONLY if autolistening is ON
    // When autolistening is OFF, keep recognition running for next manual send
    let shouldStopAfterSend = await MainActor.run { autolistening }
    
    print("🚀 [Manual Send] Creating AI response task for: \"\(textToSend)\"")
    print("   shouldStopAfterSend: \(shouldStopAfterSend)")
    print("   autolistening: \(shouldStopAfterSend)")
    
    // Send to AI without image
    let newTask = Task {
      print("🚀 [Manual Send] Task started, calling generateAIResponseWithoutImage")
      await self.generateAIResponseWithoutImage(for: textToSend)
      print("🚀 [Manual Send] generateAIResponseWithoutImage completed")
      
      // Stop recognition if we're in manual mode
      if shouldStopAfterSend {
        await MainActor.run {
          print("🛑 [Manual Send] Stopping recognition after send (autolistening is on)")
          self.stopSpeechRecognition()
        }
      }
      
      // Hide manual sending status
      await MainActor.run {
        print("✅ [Manual Send] Hiding manual sending status")
        self.isManualSending = false
      }
    }
    
    await MainActor.run {
      self.currentAIResponseTask = newTask
      print("✅ [Manual Send] AI response task created and assigned")
    }
  }
  
  func manualSendScreen() {
    // Manually send current screen frame to AI
    guard let screenImage = currentVideoFrame else {
      print("⚠️ [Manual Send] No screen image available to send")
      return
    }
    
    print("📸 [Manual Send] Manually sending screen image")
    print("   Image size: \(screenImage.size)")
    
    // Use current text if available, or a default prompt asking about the image
    let promptText: String
    switch selectedLanguage {
    case .russian:
      promptText = !currentPartialText.isEmpty && !currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
        : "Что ты видишь на этом изображении?"
    case .spanish:
      promptText = !currentPartialText.isEmpty && !currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
        : "¿Qué ves en esta imagen?"
    case .english, .system:
      promptText = !currentPartialText.isEmpty && !currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
        : "What do you see in this image?"
    }
    
    // Update UI to show the image being sent
    currentAIImage = screenImage
    
    // Add to recognized lines if we have text
    if !currentPartialText.isEmpty && !currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let textToAdd = currentPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
      if !recognizedLines.contains(textToAdd) {
        recognizedLines.append(textToAdd)
        lastFinalizedText = textToAdd
      }
      currentPartialText = ""
      updateRecognizedTextDisplay()
    }
    
    // Cancel any pending auto-send task
    cancelAutoSendTask()
    
    // Cancel previous AI response task if it's still running
    if let previousTask = currentAIResponseTask {
      print("🛑 [Manual Send] Canceling previous AI response task")
      previousTask.cancel()
    }
    
    // Stop current speech if speaking
    if isSpeaking {
      print("🛑 [Manual Send] Stopping current speech")
      stopSpeaking()
    }
    
    // Send to AI with image
    let newTask = Task {
      await generateAIResponseWithImage(for: promptText, image: screenImage)
    }
    currentAIResponseTask = newTask
  }
  
  private func generateAIResponseWithImage(for text: String, image: UIImage) async {
    print("🟢 [AI] generateAIResponseWithImage called with text: \"\(text)\"")

    if Task.isCancelled {
      await MainActor.run { self.isGeneratingResponse = false; self.currentAIResponseTask = nil }
      return
    }

    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      await MainActor.run { self.isGeneratingResponse = false; self.currentAIResponseTask = nil }
      return
    }

    isGeneratingResponse = true

    do {
      let result = try await BackendService.shared.generateResponse(
        for: text, language: backendLanguageCode, image: image
      )

      if Task.isCancelled {
        await MainActor.run { self.isGeneratingResponse = false; self.currentAIImage = nil; self.currentAIResponseTask = nil }
        return
      }

      await MainActor.run {
        self.aiResponses[text] = result.text
        self.responseSources[text] = result.source
        self.lastAIResponse = result.text
        self.isGeneratingResponse = false
        self.currentAIImage = nil
        self.currentAIResponseTask = nil
        print("✅ [AI] Backend response with image: \(result.source) in \(result.durationMs)ms")
        self.speakText(result.text)
      }
    } catch {
      if Task.isCancelled {
        await MainActor.run { self.isGeneratingResponse = false; self.currentAIImage = nil; self.currentAIResponseTask = nil }
        return
      }
      await MainActor.run {
        self.isGeneratingResponse = false
        self.currentAIImage = nil
        self.currentAIResponseTask = nil
        self.aiResponses[text] = "Error: \(error.localizedDescription)"
        self.responseSources[text] = "error"
        self.lastAIResponse = "Error: \(error.localizedDescription)"
        print("❌ [AI] Backend error: \(error.localizedDescription)")
      }
    }
  }
}

// MARK: - SpeechSynthesizerDelegate

private class SpeechSynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
  var onSpeakingChanged: ((Bool) -> Void)?
  var onSpeechFinished: (() -> Void)?
  
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
    print("🔊 [TTS] Speech started")
    onSpeakingChanged?(true)
  }
  
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    print("✅ [TTS] Speech finished")
    onSpeakingChanged?(false)
    onSpeechFinished?()
  }
  
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    print("🛑 [TTS] Speech cancelled")
    onSpeakingChanged?(false)
    onSpeechFinished?()
  }
}
