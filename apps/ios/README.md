# LensLingo — iOS App

AI assistant and real-time translator for Meta AI glasses — or your iPhone camera.

## Features

### AI Assistant Mode
- Stream video from Meta AI glasses or iPhone camera
- Voice-activated AI questions with auto-listening
- Image analysis — AI sees what your camera sees
- Gemini (primary) with ChatGPT fallback
- Text-to-speech responses
- Manual Start/Stop and Send Screen controls

### Translation Mode
- Real-time speech translation between 10 languages
- Source & target language pickers with swap
- Audio playback of translations (via wordzzz.app)
- Image translation — point camera at text to translate
- Auto-listening with continuous recognition (restarts per phrase)
- Translation examples and transcriptions
- TTS pronunciation of translations

### iPhone Camera Fallback
- Works without Meta AI glasses connected
- Uses iPhone back camera for video and image analysis
- Full AI assistant and translation features available
- Seamless switch — glasses take priority when connected

### Lock Screen & Background
- Background mode support (audio, Bluetooth, external accessory)
- Local notifications for AI responses and translations when backgrounded
- TTS continues playing on lock screen
- Notification permission requested on first launch

### General
- Bluetooth connectivity to Meta AI glasses
- Photo capture and sharing
- Energy-saving mode (disable video display)
- Mode picker (AI Assistant / Translation) with persistence

## Prerequisites

- iOS 17.0+
- Xcode 14.0+
- Swift 5.0+
- Meta Wearables Device Access Toolkit (included as dependency)
- Meta AI glasses for full experience (iPhone camera fallback available)

## Setup

### 1. Open the project

```bash
open CameraAccess.xcodeproj
```

### 2. Configure backend token

The app connects to the LensLingo backend at `https://lense-lingo.vercel.app`.

**Option A: Xcode build setting (recommended)**

1. Select the **CameraAccess** target
2. Go to **Build Settings** > click **+** > **Add User-Defined Setting**
3. Name it `BACKEND_API_TOKEN` and set it to your `SITE_PASSWORD` from Vercel

**Option B: Hardcode in Info.plist**

```xml
<key>BACKEND_API_TOKEN</key>
<string>your-password-here</string>
```

### 3. Build and run

1. Select your target device
2. Press `Cmd+R` to build and run

## Usage

### Getting Started

1. Launch LensLingo
2. **(Optional)** Turn **Developer Mode** on in the Meta AI app and press **Connect my glasses**
3. Choose your mode: **AI Assistant** or **Translation**
4. Press **Start streaming** (with glasses) or **Start with iPhone camera** (without)

### AI Assistant Mode
- Enable **Auto Listening** to have the AI respond to everything you say
- Use **Start/Stop** for manual voice input
- Tap **Send Screen** to send the current camera view to AI
- Responses appear as notifications on lock screen

### Translation Mode
- Select source and target languages
- Enable **Auto Listening** for continuous translation
- Use **Start/Stop** for manual one-shot translation
- Tap **Translate** (camera button) to translate text from the camera view
- Tap the speaker icon to hear pronunciation or the mouth icon for TTS
- Each phrase restarts recognition automatically (no accumulation)

## Project Structure

```
CameraAccess/
├── Models/
│   ├── AppLanguage.swift            # AI mode languages (EN/RU/ES)
│   └── AppMode.swift                # Mode enum (assistant/translation)
├── ViewModels/
│   ├── StreamSessionViewModel.swift # AI assistant + streaming + phone camera
│   ├── TranslationViewModel.swift   # Translation mode logic
│   └── WearablesViewModel.swift     # Device connection state
├── Views/
│   ├── NonStreamView.swift          # Pre-streaming setup with mode picker
│   ├── StreamView.swift             # AI assistant streaming UI
│   ├── TranslationStreamView.swift  # Translation streaming UI
│   ├── TranslationView.swift        # Standalone translation UI
│   └── StreamSessionView.swift      # View router (mode + streaming state)
├── Services/
│   ├── BackendService.swift         # REST client for AI backend
│   ├── TranslationService.swift     # wordzzz.app API client
│   ├── NotificationService.swift    # Local notifications for background
│   └── PhoneCameraService.swift     # iPhone camera fallback via AVCaptureSession
└── Info.plist                       # Permissions & configuration
```

## Permissions

| Permission | Usage |
|------------|-------|
| Camera | iPhone camera fallback when glasses not connected |
| Microphone | Speech recognition for voice input |
| Speech Recognition | Converting speech to text |
| Bluetooth | Connecting to Meta AI glasses |
| Notifications | Showing responses on lock screen |

## Translation API

Translation is powered by [wordzzz.app](https://wordzzz.app):

```
GET https://wordzzz.app/api?word=hello&from=en&to=ru
```

Response includes translations, transcription, audio URL, and usage examples.

## License

This source code is licensed under the license found in the LICENSE file in the root directory of this source tree.
