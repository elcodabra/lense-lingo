/**
 * Audio transcription using OpenAI Whisper API (primary)
 * and Gemini audio (fallback).
 */

import OpenAI, { toFile } from "openai";

export interface TranscriptionResult {
  text: string;
  source: "whisper" | "gemini";
  durationMs: number;
}

const GEMINI_MODEL = process.env.GEMINI_MODEL ?? "gemini-2.5-flash";
const GEMINI_GENERATE_CONTENT_URL =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

// Strip codec suffixes: "audio/webm;codecs=opus" → "audio/webm"
function cleanMimeType(mime: string): string {
  return mime.split(";")[0].trim();
}

export async function transcribeAudio(
  audioBuffer: Buffer,
  mimeType = "audio/webm",
  language?: string
): Promise<TranscriptionResult> {
  const cleanMime = cleanMimeType(mimeType);
  const start = Date.now();

  console.log(`[Transcribe] Starting: ${audioBuffer.length} bytes, mime=${cleanMime}, lang=${language}`);

  // Try Whisper first
  const openaiKey = process.env.CHATGPT_API_KEY ?? "";
  if (openaiKey) {
    try {
      const result = await whisperTranscribe(audioBuffer, cleanMime, language, openaiKey);
      console.log(`[Transcribe] Whisper succeeded: "${result}"`);
      return { text: result, source: "whisper", durationMs: Date.now() - start };
    } catch (err) {
      console.error("[Transcribe] Whisper failed, trying Gemini:", err);
    }
  } else {
    console.log("[Transcribe] No CHATGPT_API_KEY, skipping Whisper");
  }

  // Fallback to Gemini audio
  const geminiKey = process.env.GEMINI_API_KEY ?? "";
  if (geminiKey) {
    const result = await geminiTranscribe(audioBuffer, cleanMime, language, geminiKey);
    console.log(`[Transcribe] Gemini succeeded: "${result}"`);
    return { text: result, source: "gemini", durationMs: Date.now() - start };
  }

  throw new Error("No API keys configured for audio transcription (set CHATGPT_API_KEY or GEMINI_API_KEY)");
}

async function whisperTranscribe(
  audioBuffer: Buffer,
  mimeType: string,
  language: string | undefined,
  apiKey: string
): Promise<string> {
  const ext = mimeExtension(mimeType);
  const filename = `audio.${ext}`;

  console.log(`[Whisper] Sending ${audioBuffer.length} bytes as ${filename} (${mimeType})`);

  const openai = new OpenAI({ apiKey });
  const file = await toFile(audioBuffer, filename, { type: mimeType });

  const response = await openai.audio.transcriptions.create({
    file,
    model: "whisper-1",
    ...(language ? { language } : {}),
  });

  return response.text ?? "";
}

async function geminiTranscribe(
  audioBuffer: Buffer,
  mimeType: string,
  language: string | undefined,
  apiKey: string
): Promise<string> {
  const base64Audio = audioBuffer.toString("base64");
  const langHint = language ? ` The audio is in ${language}.` : "";

  const body = {
    contents: [
      {
        parts: [
          { text: `Transcribe this audio accurately. Return only the transcribed text, nothing else.${langHint}` },
          { inline_data: { mime_type: mimeType, data: base64Audio } },
        ],
      },
    ],
  };

  const res = await fetch(GEMINI_GENERATE_CONTENT_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-goog-api-key": apiKey,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err?.error?.message ?? `Gemini HTTP ${res.status}`);
  }

  const json = await res.json();
  const text = json?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error("Invalid Gemini audio response");
  return text.trim();
}

function mimeExtension(mime: string): string {
  const map: Record<string, string> = {
    "audio/webm": "webm",
    "audio/ogg": "ogg",
    "audio/mp4": "m4a",
    "audio/mpeg": "mp3",
    "audio/wav": "wav",
    "audio/x-wav": "wav",
    "audio/mp3": "mp3",
    "audio/aac": "aac",
    "audio/flac": "flac",
  };
  return map[mime] ?? "webm";
}
