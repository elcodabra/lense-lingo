import { geminiGenerate, geminiGenerateWithImage } from "./gemini";
import { chatgptGenerate, chatgptGenerateWithImage } from "./chatgpt";

export type Language = "en" | "ru" | "es";
export type AISource = "gemini" | "chatgpt";

export interface AIResponse {
  text: string;
  source: AISource;
  durationMs: number;
}

function getLanguageInstruction(lang: Language): string {
  const shortPrefix = " Keep your answer concise — 1-3 sentences max.";
  switch (lang) {
    case "ru":
      return shortPrefix + " Отвечай на русском языке.";
    case "es":
      return shortPrefix + " Responde en español.";
    default:
      return shortPrefix + " Respond in English.";
  }
}

export async function generateAIResponse(
  text: string,
  lang: Language = "en",
  image?: { base64: string; mimeType?: string }
): Promise<AIResponse> {
  const promptText = text + getLanguageInstruction(lang);
  const start = Date.now();

  // Try Gemini first
  try {
    const response = image
      ? await geminiGenerateWithImage(promptText, image.base64, image.mimeType)
      : await geminiGenerate(promptText);
    return {
      text: response,
      source: "gemini",
      durationMs: Date.now() - start,
    };
  } catch (geminiError) {
    console.error("[AI] Gemini failed, falling back to ChatGPT:", geminiError);
  }

  // Fallback to ChatGPT
  const response = image
    ? await chatgptGenerateWithImage(promptText, image.base64, image.mimeType)
    : await chatgptGenerate(promptText);
  return {
    text: response,
    source: "chatgpt",
    durationMs: Date.now() - start,
  };
}

// Fast keyword-based check before calling the AI
const VISUAL_KEYWORDS: Record<Language, RegExp> = {
  en: /\b(see|seeing|look|looking|watch|watching|show|read|describe|what.?s this|what.?s that|in front|around me|nearby|camera|photo|picture|image|scan|recognize|identify|translate this|sign|menu|label|screen)\b/i,
  ru: /\b(вид|виж|смотр|покаж|читай|опиш|что это|что там|перед|вокруг|камер|фото|снимок|сканир|распозна|перевед|вывеск|меню|экран|надпис)\b/i,
  es: /\b(ve[ros]|mir[ao]|muestra|le[ea]|describ|qué es|qué hay|frente|alrededor|cámara|foto|imagen|escan|reconoc|identific|traduc|letrero|menú|pantalla|señal)\b/i,
};

function getImageCheckPrompt(text: string, lang: Language): string {
  switch (lang) {
    case "ru":
      return `Пользователь носит умные очки с камерой и спросил: "${text}"

Нужна ли картинка с камеры для ответа? Ответь ТОЛЬКО "yes" или "no".

ВАЖНО: Если пользователь спрашивает что он видит, что вокруг, просит описать, прочитать, перевести, распознать что-то — это ВСЕГДА "yes".
Если это общий вопрос (погода, шутка, время, факты, совет) — "no".`;
    case "es":
      return `El usuario lleva gafas inteligentes con cámara y preguntó: "${text}"

¿Se necesita imagen de la cámara para responder? Responde SOLO "yes" o "no".

IMPORTANTE: Si pregunta qué ve, qué hay alrededor, pide describir, leer, traducir, reconocer algo — SIEMPRE "yes".
Si es una pregunta general (clima, chistes, hora, datos, consejos) — "no".`;
    default:
      return `The user is wearing smart glasses with a camera and asked: "${text}"

Is a camera image needed to answer this? Answer ONLY "yes" or "no".

IMPORTANT: If the user asks what they see, what's around, asks to describe, read, translate, recognize, identify, or look at something — ALWAYS "yes".
If it's a general question (weather, jokes, time, facts, advice, greetings) — "no".`;
  }
}

export async function checkImageNeeded(
  text: string,
  lang: Language = "en"
): Promise<boolean> {
  // Fast keyword check first
  if (VISUAL_KEYWORDS[lang]?.test(text)) {
    console.log(`[ImageCheck] Keyword match for: "${text}" → yes`);
    return true;
  }

  const prompt = getImageCheckPrompt(text, lang);

  try {
    const response = await geminiGenerate(prompt);
    const first = response
      .toLowerCase()
      .trim()
      .split(/[\s.,!?]+/)[0];
    return first === "yes";
  } catch {
    // If Gemini fails, try ChatGPT
    try {
      const response = await chatgptGenerate(prompt);
      const first = response
        .toLowerCase()
        .trim()
        .split(/[\s.,!?]+/)[0];
      return first === "yes";
    } catch {
      return false;
    }
  }
}
