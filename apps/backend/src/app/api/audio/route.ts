import { NextRequest, NextResponse } from "next/server";
import { transcribeAudio } from "@/lib/transcribe";
import { generateAIResponse, checkImageNeeded, Language } from "@/lib/ai-service";

/**
 * POST /api/audio
 *
 * Accepts audio (as multipart form-data or base64 JSON), transcribes it,
 * optionally checks if image is needed, then generates an AI response.
 *
 * Form-data fields:
 *   audio    - audio file blob
 *   language - "en" | "ru" | "es" (optional, default "en")
 *   image    - base64-encoded image string (optional)
 *   imageMimeType - image MIME type (optional, default "image/jpeg")
 *
 * JSON body (alternative):
 *   { audioBase64, audioMimeType?, language?, image?: { base64, mimeType? } }
 */
export async function POST(req: NextRequest) {
  try {
    const contentType = req.headers.get("content-type") ?? "";
    let audioBuffer: Buffer;
    let audioMimeType = "audio/webm";
    let language: Language = "en";
    let image: { base64: string; mimeType?: string } | undefined;

    if (contentType.includes("multipart/form-data")) {
      const formData = await req.formData();
      const audioFile = formData.get("audio");
      if (!audioFile || !(audioFile instanceof Blob)) {
        return NextResponse.json({ error: "audio file is required" }, { status: 400 });
      }
      audioBuffer = Buffer.from(await audioFile.arrayBuffer());
      audioMimeType = audioFile.type || "audio/webm";
      language = (formData.get("language") as Language) ?? "en";

      const imageBase64 = formData.get("image") as string | null;
      if (imageBase64) {
        image = {
          base64: imageBase64,
          mimeType: (formData.get("imageMimeType") as string) ?? "image/jpeg",
        };
      }
    } else {
      const body = await req.json();
      if (!body.audioBase64) {
        return NextResponse.json({ error: "audioBase64 is required" }, { status: 400 });
      }
      audioBuffer = Buffer.from(body.audioBase64, "base64");
      audioMimeType = body.audioMimeType ?? "audio/webm";
      language = body.language ?? "en";
      image = body.image;
    }

    // 1. Transcribe
    const transcription = await transcribeAudio(audioBuffer, audioMimeType, language);

    if (!transcription.text.trim()) {
      return NextResponse.json({
        transcription: { text: "", source: transcription.source, durationMs: transcription.durationMs },
        response: null,
      });
    }

    // 2. Check if image is needed (when no image provided)
    let imageNeeded = false;
    if (!image) {
      imageNeeded = await checkImageNeeded(transcription.text, language);
    }

    // 3. Generate AI response
    const aiResult = await generateAIResponse(transcription.text, language, image);

    return NextResponse.json({
      transcription: {
        text: transcription.text,
        source: transcription.source,
        durationMs: transcription.durationMs,
      },
      response: aiResult,
      imageNeeded,
    });
  } catch (error) {
    console.error("[API /audio]", error);
    const message = error instanceof Error ? error.message : "Internal server error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
