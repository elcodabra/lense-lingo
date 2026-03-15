# LensLingo Web — Backend & Test UI

Next.js backend for the LensLingo iOS app with REST + WebSocket support, audio transcription, and a web UI to test everything.

## Architecture

```
Meta Glasses / iOS App / Web Test UI
            ↓
  REST API  ←→  WebSocket (Socket.IO)
            ↓
  Audio → Whisper STT (or Gemini) → Transcription
            ↓
  Gemini (primary) → ChatGPT (fallback) → Response
            ↓
  TTS (client-side) ← natural interruption
```

## REST API Endpoints

### POST `/api/generate`

Generate an AI response (text-only or multimodal with image).

```json
{
  "text": "What do you see?",
  "language": "en",
  "image": {
    "base64": "<base64-encoded-image>",
    "mimeType": "image/jpeg"
  }
}
```

Response:

```json
{
  "text": "I can see a park with...",
  "source": "gemini",
  "durationMs": 1234
}
```

### POST `/api/audio`

Full voice pipeline: accepts audio, transcribes, generates AI response.

Multipart form-data:
- `audio` — audio file blob (webm, wav, mp3, m4a, ogg, etc.)
- `language` — `"en"` | `"ru"` | `"es"` (optional)
- `image` — base64 image string (optional)

Or JSON body:

```json
{
  "audioBase64": "<base64-encoded-audio>",
  "audioMimeType": "audio/webm",
  "language": "en"
}
```

Response:

```json
{
  "transcription": {
    "text": "What is this building?",
    "source": "whisper",
    "durationMs": 890
  },
  "response": {
    "text": "This appears to be...",
    "source": "gemini",
    "durationMs": 1234
  },
  "imageNeeded": true
}
```

### POST `/api/check-image-needed`

Check if a user query requires camera image context.

```json
{
  "text": "What do you see?",
  "language": "en"
}
```

Response:

```json
{
  "imageNeeded": true
}
```

## WebSocket Events (Socket.IO)

### Client → Server

| Event | Payload |
|---|---|
| `generate` | `{ text, language?, image?, requestId? }` |
| `audio` | `{ audio (base64), audioMimeType?, language?, image?, requestId? }` |
| `check-image-needed` | `{ text, language?, requestId? }` |
| `interrupt` | `{ requestId? }` |

### Server → Client

| Event | Payload |
|---|---|
| `generate:start` | `{ requestId }` |
| `generate:result` | `{ requestId, text, source, durationMs }` |
| `generate:error` | `{ requestId, error }` |
| `audio:start` | `{ requestId }` |
| `audio:transcribed` | `{ requestId, text, source, durationMs }` |
| `audio:image-needed` | `{ requestId, imageNeeded }` |
| `audio:result` | `{ requestId, transcription, response, imageNeeded }` |
| `audio:error` | `{ requestId, error }` |
| `interrupt:ack` | `{ requestId }` |
| `check-image-needed:result` | `{ requestId, imageNeeded }` |
| `check-image-needed:error` | `{ requestId, error }` |

## Setup

1. Copy environment template:

```bash
cp .env.example .env
```

2. Add your API keys to `.env`:

```
GEMINI_API_KEY=your-gemini-api-key
CHATGPT_API_KEY=your-openai-api-key
```

3. Install and run:

```bash
npm install
npm run dev
```

4. Open http://localhost:3000 for the test UI.

## Scripts

| Command | Description |
|---|---|
| `npm run dev` | Custom server with Next.js + WebSocket on port 3000 |
| `npm run dev:next` | Next.js only (REST endpoints, no WebSocket) |
| `npm run build` | Production build |
| `npm start` | Production server with WebSocket |

## Supported Languages

- English (`en`)
- Russian (`ru`)
- Spanish (`es`)

## Test UI Tabs

- **Chat / Generate** — text input with optional image, AI response with source badge
- **Audio** — mic recording → Whisper transcription → AI response → TTS with natural interruption
- **Image Check** — test whether a query needs camera image context

### Audio Mode Features

- Record from microphone, audio sent to backend for transcription (Whisper or Gemini)
- AI response spoken via browser TTS
- **Natural interruption**: tap mic or "Interrupt" while AI speaks to cut in immediately
- **Auto-listen**: automatically starts recording after AI finishes speaking
- Shows transcription source (Whisper/Gemini STT), AI source (Gemini/ChatGPT), and transport (REST/WS)
- Visual mic level indicator during recording
