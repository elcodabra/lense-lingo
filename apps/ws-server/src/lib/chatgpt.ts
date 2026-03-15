const CHATGPT_BASE_URL = "https://api.openai.com/v1/chat/completions";

function getApiKey(): string {
  const key = process.env.CHATGPT_API_KEY ?? "";
  if (!key) throw new Error("CHATGPT_API_KEY is not set");
  return key;
}

export async function chatgptGenerate(text: string): Promise<string> {
  const apiKey = getApiKey();

  const body = {
    model: "gpt-3.5-turbo",
    messages: [{ role: "user", content: text }],
    max_tokens: 150,
    temperature: 0.7,
  };

  const res = await fetch(CHATGPT_BASE_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(
      err?.error?.message ?? `ChatGPT HTTP ${res.status}`
    );
  }

  const json = await res.json();
  const content = json?.choices?.[0]?.message?.content;
  if (!content) throw new Error("Invalid ChatGPT response structure");
  return content.trim();
}

export async function chatgptGenerateWithImage(
  text: string,
  base64Image: string,
  mimeType = "image/jpeg"
): Promise<string> {
  const apiKey = getApiKey();

  const body = {
    model: "gpt-4o",
    messages: [
      {
        role: "user",
        content: [
          { type: "text", text },
          {
            type: "image_url",
            image_url: { url: `data:${mimeType};base64,${base64Image}` },
          },
        ],
      },
    ],
    max_tokens: 300,
    temperature: 0.7,
  };

  const res = await fetch(CHATGPT_BASE_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(
      err?.error?.message ?? `ChatGPT HTTP ${res.status}`
    );
  }

  const json = await res.json();
  const content = json?.choices?.[0]?.message?.content;
  if (!content) throw new Error("Invalid ChatGPT response structure");
  return content.trim();
}
