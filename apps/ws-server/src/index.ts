import "dotenv/config";
import { createServer } from "http";
import { Server as SocketIOServer } from "socket.io";
import { generateAIResponse, checkImageNeeded, Language } from "./lib/ai-service";
import { transcribeAudio } from "./lib/transcribe";

const port = parseInt(process.env.PORT || "3001", 10);

const httpServer = createServer((_, res) => {
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ status: "ok", service: "lenslingo-ws" }));
});

const io = new SocketIOServer(httpServer, {
  cors: { origin: "*" },
  maxHttpBufferSize: 10 * 1024 * 1024, // 10 MB for audio payloads
});

io.on("connection", (socket) => {
  console.log(`[WS] Client connected: ${socket.id}`);

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
    audio: ArrayBuffer | Buffer | string;
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
      const transcription = await transcribeAudio(audioBuffer, audioMimeType, language);
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
        imageNeeded = await checkImageNeeded(transcription.text, language);
        socket.emit("audio:image-needed", { requestId, imageNeeded });
      }

      // 3. Generate AI response
      const aiResult = await generateAIResponse(transcription.text, language, data.image);
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

  socket.on("interrupt", (data: { requestId?: string }) => {
    console.log(`[WS] Client interrupted: ${data.requestId ?? socket.id}`);
    socket.emit("interrupt:ack", { requestId: data.requestId ?? socket.id });
  });

  socket.on("disconnect", () => {
    console.log(`[WS] Client disconnected: ${socket.id}`);
  });
});

httpServer.listen(port, () => {
  console.log(`> WebSocket server ready on port ${port}`);
});
