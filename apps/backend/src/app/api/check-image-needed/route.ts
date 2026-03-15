import { NextRequest, NextResponse } from "next/server";
import { checkImageNeeded, Language } from "@/lib/ai-service";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { text, language } = body as {
      text?: string;
      language?: Language;
    };

    if (!text?.trim()) {
      return NextResponse.json(
        { error: "text is required" },
        { status: 400 }
      );
    }

    const needed = await checkImageNeeded(text, language ?? "en");

    return NextResponse.json({ imageNeeded: needed });
  } catch (error) {
    console.error("[API /check-image-needed]", error);
    const message =
      error instanceof Error ? error.message : "Internal server error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
