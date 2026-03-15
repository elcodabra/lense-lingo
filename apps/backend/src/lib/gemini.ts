const GEMINI_MODEL = process.env.GEMINI_MODEL ?? "gemini-2.5-flash";
const GEMINI_BASE_URL =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

function getApiKey(): string {
  const key = process.env.GEMINI_API_KEY ?? "";
  if (!key) throw new Error("GEMINI_API_KEY is not set");
  return key;
}

export async function geminiGenerate(text: string): Promise<string> {
  const apiKey = getApiKey();

  const body = {
    contents: [{ parts: [{ text }] }],
  };

  const res = await fetch(GEMINI_BASE_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-goog-api-key": apiKey,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(
      err?.error?.message ?? `Gemini HTTP ${res.status}`
    );
  }

  const json = await res.json();
  const generatedText =
    json?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!generatedText) throw new Error("Invalid Gemini response structure");
  return generatedText;
}

export async function geminiGenerateWithImage(
  text: string,
  base64Image: string,
  mimeType = "image/jpeg"
): Promise<string> {
  const apiKey = getApiKey();

  const body = {
    contents: [
      {
        parts: [
          { text },
          { inline_data: { mime_type: mimeType, data: base64Image } },
        ],
      },
    ],
  };

  const res = await fetch(GEMINI_BASE_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-goog-api-key": apiKey,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(
      err?.error?.message ?? `Gemini HTTP ${res.status}`
    );
  }

  const json = await res.json();
  const generatedText =
    json?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!generatedText) throw new Error("Invalid Gemini response structure");
  return generatedText;
}
