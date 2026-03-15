import "dotenv/config";
import { createServer } from "http";
import next from "next";
import { Server as SocketIOServer } from "socket.io";
import { generateAIResponse, checkImageNeeded, Language } from "./src/lib/ai-service";
import { transcribeAudio } from "./src/lib/transcribe";

const dev = process.env.NODE_ENV !== "production";
const hostname = "0.0.0.0";
const port = parseInt(process.env.PORT || "3000", 10);

const app = next({ dev, hostname, port });
const handle = app.getRequestHandler();

app.prepare().then(() => {
  const httpServer = createServer((req, res) => {
    handle(req, res);
  });

  const io = new SocketIOServer(httpServer, {
    cors: { origin: "*" },
    maxHttpBufferSize: 10 * 1024 * 1024, // 10 MB for audio payloads
  });

  io.on("connection", (socket) => {
    console.log(`[WS] Client connected: ${socket.id}`);

    // Log ALL incoming events for debugging
    socket.onAny((eventName, ...args) => {
      const argSummary = args.map(a => {
        if (typeof a === 'string') return `string(${a.length})`;
        if (typeof a === 'object' && a !== null) return JSON.stringify(Object.keys(a));
        return String(a);
      }).join(', ');
      console.log(`[WS] Event: "${eventName}" from ${socket.id}, args: [${argSummary}]`);
    });

    // Generate AI response
    socket.on("generate", async (data: {
      text?: string;
      language?: Language;
      image?: { base64: string; mimeType?: string };
      requestId?: string;
    }) => {
      const requestId = data.requestId ?? socket.id;

      if (!data.text?.trim()) {
        socket.emit("generate:error", { requestId, error: "text is required" });
        return;
      }

      socket.emit("generate:start", { requestId });

      try {
        const result = await generateAIResponse(
          data.text,
          data.language ?? "en",
          data.image
        );
        socket.emit("generate:result", { requestId, ...result });
      } catch (error) {
        const message = error instanceof Error ? error.message : "Internal server error";
        socket.emit("generate:error", { requestId, error: message });
      }
    });

    // Check if image is needed
    socket.on("check-image-needed", async (data: {
      text?: string;
      language?: Language;
      requestId?: string;
    }) => {
      const requestId = data.requestId ?? socket.id;

      if (!data.text?.trim()) {
        socket.emit("check-image-needed:error", { requestId, error: "text is required" });
        return;
      }

      try {
        const needed = await checkImageNeeded(data.text, data.language ?? "en");
        socket.emit("check-image-needed:result", { requestId, imageNeeded: needed });
      } catch (error) {
        const message = error instanceof Error ? error.message : "Internal server error";
        socket.emit("check-image-needed:error", { requestId, error: message });
      }
    });

    // Audio: transcribe + generate AI response
    socket.on("audio", async (data: {
      audio: ArrayBuffer | Buffer | string; // binary or base64
      audioMimeType?: string;
      language?: Language;
      image?: { base64: string; mimeType?: string };
      requestId?: string;
    }) => {
      const requestId = data.requestId ?? socket.id;

      if (!data.audio) {
        socket.emit("audio:error", { requestId, error: "audio is required" });
        return;
      }

      console.log(`[WS] Audio received from ${socket.id}, requestId=${requestId}, type=${typeof data.audio}, mime=${data.audioMimeType}`);
      socket.emit("audio:start", { requestId });

      try {
        // Convert to Buffer
        let audioBuffer: Buffer;
        if (typeof data.audio === "string") {
          audioBuffer = Buffer.from(data.audio, "base64");
        } else {
          audioBuffer = Buffer.from(new Uint8Array(data.audio as ArrayBuffer));
        }

        const audioMimeType = data.audioMimeType ?? "audio/webm";
        const language = data.language ?? "en";

        console.log(`[WS] Audio buffer: ${audioBuffer.length} bytes, mime=${audioMimeType}, lang=${language}`);

        // 1. Transcribe
        console.log(`[WS] Step 1: Transcribing...`);
        const transcription = await transcribeAudio(audioBuffer, audioMimeType, language);
        console.log(`[WS] Step 1 done: "${transcription.text}" (${transcription.source}, ${transcription.durationMs}ms)`);
        socket.emit("audio:transcribed", {
          requestId,
          text: transcription.text,
          source: transcription.source,
          durationMs: transcription.durationMs,
        });

        if (!transcription.text.trim()) {
          socket.emit("audio:result", { requestId, transcription, response: null });
          return;
        }

        // 2. Check if image is needed
        let imageNeeded = false;
        if (!data.image) {
          console.log(`[WS] Step 2: Checking image need...`);
          imageNeeded = await checkImageNeeded(transcription.text, language);
          console.log(`[WS] Step 2 done: imageNeeded=${imageNeeded}`);
          socket.emit("audio:image-needed", { requestId, imageNeeded });
        }

        // 3. Generate AI response
        console.log(`[WS] Step 3: Generating AI response...`);
        const aiResult = await generateAIResponse(transcription.text, language, data.image);
        console.log(`[WS] Step 3 done: "${aiResult.text?.substring(0, 50)}..." (${aiResult.source})`);
        socket.emit("audio:result", {
          requestId,
          transcription: {
            text: transcription.text,
            source: transcription.source,
            durationMs: transcription.durationMs,
          },
          response: aiResult,
          imageNeeded,
        });
      } catch (error) {
        console.error(`[WS] Audio processing error for ${requestId}:`, error);
        const message = error instanceof Error ? error.message : "Internal server error";
        socket.emit("audio:error", { requestId, error: message });
      }
    });

    // Interrupt: client signals it wants to cancel current TTS / generation
    socket.on("interrupt", (data: { requestId?: string }) => {
      console.log(`[WS] Client interrupted: ${data.requestId ?? socket.id}`);
      socket.emit("interrupt:ack", { requestId: data.requestId ?? socket.id });
    });

    socket.on("disconnect", () => {
      console.log(`[WS] Client disconnected: ${socket.id}`);
    });
  });

  httpServer.listen(port, () => {
    console.log(`> Ready on http://${hostname}:${port}`);
    console.log(`> WebSocket server running on same port`);
  });
});
