# LensLingo — Meta Wearables DAT

Real-time multimodal conversation assistant for iPhone and Meta AI glasses.

Built with Meta Wearables Device Access Toolkit, Gemini, and OpenAI.

## Project Structure

```
apps/
├── ios/          # iOS app (SwiftUI) — Camera Access + LensLingo
├── backend/      # Next.js frontend + REST API (Vercel)
└── ws-server/    # Socket.IO WebSocket server (Railway)
```

| Project | Stack | Deploy | Docs |
|---------|-------|--------|------|
| [iOS App](apps/ios/) | Swift, SwiftUI, Meta DAT SDK | Xcode | [README](apps/ios/README.md) |
| [Backend](apps/backend/) | Next.js, REST API, Gemini, OpenAI | Vercel | [README](apps/backend/README.md) |
| [WS Server](apps/ws-server/) | Socket.IO, Gemini, OpenAI | Railway | [README](apps/ws-server/README.md) |

## Quick Start

### iOS App

```bash
open apps/ios/CameraAccess.xcodeproj
```

### Backend (Vercel)

```bash
cd apps/backend
cp .env.example .env
# Add your GEMINI_API_KEY and CHATGPT_API_KEY to .env
npm install
npm run dev
```

### WebSocket Server (Railway)

```bash
cd apps/ws-server
cp .env.example .env
# Add your GEMINI_API_KEY and CHATGPT_API_KEY to .env
npm install
npm run dev
```

## Architecture

```
Meta AI Glasses / iPhone
        ↓
iOS App (SwiftUI + Meta DAT SDK)
        ↓
   ┌────┴────┐
   ↓         ↓
Vercel     Railway
(REST)     (WebSocket)
   ↓         ↓
   └────┬────┘
        ↓
Gemini (primary) / ChatGPT (fallback)
```

## Deployment

| Service | Platform | Notes |
|---------|----------|-------|
| Backend | Vercel | REST API + Test UI. Set `NEXT_PUBLIC_WS_URL` to Railway URL |
| WS Server | Railway | WebSocket for real-time audio/chat. Set API keys in env vars |

## Meta Wearables DAT SDK

[![Swift Package](https://img.shields.io/badge/Swift_Package-0.3.0-brightgreen?logo=swift&logoColor=white)](https://github.com/facebook/meta-wearables-dat-ios/tags)
[![Docs](https://img.shields.io/badge/API_Reference-0.3-blue?logo=meta)](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.3)

The Meta Wearables Device Access Toolkit enables developers to utilize Meta's AI glasses to build hands-free wearable experiences into their mobile applications.

### Including the SDK in your project

The easiest way to add the SDK to your project is by using Swift Package Manager.

1. In Xcode, select **File** > **Add Package Dependencies...**
1. Search for `https://github.com/facebook/meta-wearables-dat-ios` in the top right corner
1. Select `meta-wearables-dat-ios`
1. Set the version to one of the [available versions](https://github.com/facebook/meta-wearables-dat-ios/tags)
1. Click **Add Package**
1. Select the target to which you want to add the packages
1. Click **Add Package**

Find the full [developer documentation](https://wearables.developer.meta.com/docs/develop/) on the Wearables Developer Center. For help or feature ideas, visit our [discussions forum](https://github.com/facebook/meta-wearables-dat-ios/discussions).

See the [changelog](CHANGELOG.md) for the latest updates.

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

- `YES`/`<true/>` = Opt out (analytics **disabled**)
- `NO`/`<false/>` = Opt in (analytics **enabled**)

## License

See the [LICENSE](LICENSE) file.
