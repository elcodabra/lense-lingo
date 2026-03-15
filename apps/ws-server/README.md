# LensLingo WebSocket Server

Standalone Socket.IO server for real-time audio transcription and AI responses. Deployed on Railway.

## Events

See [backend README](../backend/README.md) for the full WebSocket event reference.

## Setup

```bash
cp .env.example .env
# Add your GEMINI_API_KEY and CHATGPT_API_KEY
npm install
npm run dev
```

## Deploy to Railway

1. Install Railway CLI: `npm i -g @railway/cli`
2. Login: `railway login`
3. Create project: `railway init`
4. Set root directory to `apps/ws-server` in Railway dashboard
5. Add environment variables: `GEMINI_API_KEY`, `CHATGPT_API_KEY`
6. Deploy: `railway up`
7. Copy the Railway URL and set it as `NEXT_PUBLIC_WS_URL` in Vercel

## Scripts

| Command | Description |
|---------|-------------|
| `npm run dev` | Dev server with hot reload (port 3001) |
| `npm start` | Production server |
