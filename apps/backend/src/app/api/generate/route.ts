import { NextRequest, NextResponse } from "next/server";
import { generateAIResponse, Language } from "@/lib/ai-service";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { text, language, image } = body as {
      text?: string;
      language?: Language;
      image?: { base64: string; mimeType?: string };
    };

    if (!text?.trim()) {
      return NextResponse.json(
        { error: "text is required" },
        { status: 400 }
      );
    }

    const result = await generateAIResponse(
      text,
      language ?? "en",
      image
    );

    return NextResponse.json(result);
  } catch (error) {
    console.error("[API /generate]", error);
    const message =
      error instanceof Error ? error.message : "Internal server error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
