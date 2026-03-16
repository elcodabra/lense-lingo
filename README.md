# LensLingo — AI & Translation for Smart Glasses

Real-time AI assistant and translator for Meta AI glasses (or iPhone camera), powered by Gemini, OpenAI, and [wordzzz.app](https://wordzzz.app).

Built with Meta Wearables Device Access Toolkit.

## Features

- **AI Assistant** — Ask questions, describe what you see, get instant AI answers
- **Translation Mode** — Real-time speech translation between 10 languages with audio playback
- **Image Translation** — Point your camera at text and translate it instantly
- **Voice Control** — Hands-free with auto-listening, speech recognition, and TTS
- **iPhone Camera Fallback** — Works without glasses using your phone's camera and mic
- **Lock Screen Notifications** — AI responses and translations delivered as notifications
- **Background Mode** — Keeps working with the screen locked

## Project Structure

```
apps/
├── ios/          # LensLingo iOS app (SwiftUI)
└── backend/      # Node.js/Next.js backend — AI & REST API
```

| Project | Stack | Docs |
|---------|-------|------|
| [iOS App](apps/ios/) | Swift, SwiftUI, AVFoundation, Speech, Meta DAT SDK | [README](apps/ios/README.md) |
| [Backend](apps/backend/) | Next.js, OpenAI, Gemini | [README](apps/backend/README.md) |

## Quick Start

### iOS App

```bash
open apps/ios/CameraAccess.xcodeproj
```

See [apps/ios/README.md](apps/ios/README.md) for full setup.

### Backend

```bash
cd apps/backend
cp .env.example .env
# Add your GEMINI_API_KEY and CHATGPT_API_KEY to .env
npm install
npm run dev
```

See [apps/backend/README.md](apps/backend/README.md) for API docs.

## Architecture

```
Meta AI Glasses (Bluetooth)          iPhone Camera (fallback)
            ↓                                ↓
            └──────────┬─────────────────────┘
                       ↓
             LensLingo iOS App
  ├── AI Assistant Mode
  │     ├── Speech Recognition → Backend API → Gemini/ChatGPT → TTS
  │     └── Camera Frame → Image Analysis → AI Response
  └── Translation Mode
        ├── Speech Recognition → wordzzz.app API → TTS/Audio
        └── Camera Frame → OCR (AI) → wordzzz.app → Translation
                       ↓
            Local Notifications (lock screen)
```

## Supported Languages

### AI Assistant
English, Russian, Spanish

### Translation (via wordzzz.app)
English, Russian, Spanish, French, German, Italian, Portuguese, Chinese, Japanese, Korean

## Meta Wearables DAT SDK

[![Swift Package](https://img.shields.io/badge/Swift_Package-0.3.0-brightgreen?logo=swift&logoColor=white)](https://github.com/facebook/meta-wearables-dat-ios/tags)
[![Docs](https://img.shields.io/badge/API_Reference-0.3-blue?logo=meta)](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.3)

The Meta Wearables Device Access Toolkit enables developers to utilize Meta's AI glasses to build hands-free wearable experiences into their mobile applications.

### Including the SDK in your project

1. In Xcode, select **File** > **Add Package Dependencies...**
1. Search for `https://github.com/facebook/meta-wearables-dat-ios`
1. Select `meta-wearables-dat-ios`
1. Set the version to one of the [available versions](https://github.com/facebook/meta-wearables-dat-ios/tags)
1. Click **Add Package**

Find the full [developer documentation](https://wearables.developer.meta.com/docs/develop/) on the Wearables Developer Center.

## Developer Terms

- By using the Wearables Device Access Toolkit, you agree to our [Meta Wearables Developer Terms](https://wearables.developer.meta.com/terms),
  including our [Acceptable Use Policy](https://wearables.developer.meta.com/acceptable-use-policy).
- By enabling Meta integrations, including through this SDK, Meta may collect information about how users' Meta devices communicate with your app.
  Meta will use this information collected in accordance with our [Privacy Policy](https://www.meta.com/legal/privacy-policy/).

### Opting out of data collection

To configure analytics settings, modify your app's `Info.plist`:

```XML
<key>MWDAT</key>
<dict>
    <key>Analytics</key>
    <dict>
        <key>OptOut</key>
        <true/>
    </dict>
</dict>
```

## License

See the [LICENSE](LICENSE) file.
