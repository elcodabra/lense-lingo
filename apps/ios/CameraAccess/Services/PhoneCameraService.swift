import AVFoundation
import UIKit

/// Provides iPhone camera frames as a fallback when glasses aren't connected
final class PhoneCameraService: NSObject, ObservableObject {
  private var captureSession: AVCaptureSession?
  private let sessionQueue = DispatchQueue(label: "phoneCameraQueue")
  private let videoOutput = AVCaptureVideoDataOutput()

  var onFrame: ((UIImage) -> Void)?

  var isRunning: Bool { captureSession?.isRunning ?? false }

  func start() {
    sessionQueue.async { [weak self] in
      self?.setupAndStart()
    }
  }

  func stop() {
    sessionQueue.async { [weak self] in
      self?.captureSession?.stopRunning()
    }
  }

  private func setupAndStart() {
    if let session = captureSession, session.isRunning { return }

    // Configure audio session first — must be .playAndRecord for speech recognition to work
    // alongside the camera capture session
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setCategory(.playAndRecord, mode: .spokenAudio,
                                   options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
      try audioSession.setActive(true)
    } catch {
      print("⚠️ [PhoneCamera] Audio session setup error: \(error)")
    }

    let session = AVCaptureSession()
    session.sessionPreset = .medium
    // Prevent capture session from overriding our audio session config
    session.automaticallyConfiguresApplicationAudioSession = false

    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
          let input = try? AVCaptureDeviceInput(device: camera) else {
      print("❌ [PhoneCamera] Cannot access back camera")
      return
    }

    if session.canAddInput(input) {
      session.addInput(input)
    }

    videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    if session.canAddOutput(videoOutput) {
      session.addOutput(videoOutput)
    }

    // Set orientation to portrait
    if let connection = videoOutput.connection(with: .video) {
      if connection.isVideoRotationAngleSupported(90) {
        connection.videoRotationAngle = 90
      }
    }

    self.captureSession = session
    session.startRunning()
    print("📱 [PhoneCamera] Started")
  }
}

extension PhoneCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    let context = CIContext()
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
    let image = UIImage(cgImage: cgImage)

    DispatchQueue.main.async { [weak self] in
      self?.onFrame?(image)
    }
  }
}
