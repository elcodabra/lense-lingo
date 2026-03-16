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

// Universal keyword check — covers EN, RU, ES and common patterns in any language.
// All patterns are combined into one regex to avoid per-language misses.
const VISUAL_KEYWORDS = new RegExp([
  // English
  "see", "seeing", "seen", "look", "looking", "watch", "watching",
  "show me", "read", "reading", "describe", "what.?s this", "what.?s that",
  "what is this", "what is that", "what are these", "what are those",
  "in front", "around me", "nearby", "before me",
  "camera", "photo", "picture", "image", "snap", "capture",
  "scan", "recognize", "identify", "detect", "point",
  "translate", "sign", "menu", "label", "screen", "text on", "written",
  "color", "colour", "brand", "price", "how much", "how many",
  "where am i", "what place", "what building", "what street",
  "what flower", "what plant", "what animal", "what dog", "what bird",
  "what food", "what dish",
  // Russian
  "вид", "виж", "вижу", "видишь", "видно", "видеть",
  "смотр", "смотри", "покаж", "покажи", "глянь", "глядь",
  "читай", "прочитай", "прочти",
  "опиш", "опиши", "расскаж",
  "что это", "что там", "что здесь", "что за", "это что",
  "перед", "вокруг", "рядом", "передо мной",
  "камер", "фото", "снимок", "снимк", "картинк",
  "сканир", "распозна", "определи", "узнай",
  "перевед", "перевод", "переведи",
  "вывеск", "меню", "экран", "надпис", "табличк", "ценник",
  "цвет", "бренд", "марк", "сколько стоит", "какая цена",
  "где я", "что за место", "какое здание", "какая улица",
  // Spanish
  "ver", "veo", "ves", "vemos", "mira", "miro", "mirando",
  "muestra", "mostrar", "lee", "leer", "leyendo",
  "describ", "qué es esto", "qué es eso", "qué hay",
  "frente", "alrededor", "cerca",
  "cámara", "foto", "imagen", "captura",
  "escan", "reconoc", "identific", "detect",
  "traduc", "traducir", "letrero", "menú", "pantalla", "señal", "cartel",
  "color", "marca", "precio", "cuánto cuesta",
  "dónde estoy", "qué lugar", "qué edificio",
].map(w => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|"), "i");

// Non-visual patterns — general questions that never need an image
const NON_VISUAL_KEYWORDS = /\b(weather|time|joke|chiste|шутк|погод|врем|час|hora|clima|tell me about|cuéntame|расскаж[иь] (мне )?о|how to|cómo|как (сделать|готовить)|recipe|receta|рецепт|capital of|столиц|who is|quién es|кто тако[йе]|calculate|calcul|посчитай|history|histori|истори)\b/i;

export function checkImageNeeded(
  text: string,
  _lang: Language = "en"
): boolean {
  // If it matches a non-visual pattern first, skip image
  if (NON_VISUAL_KEYWORDS.test(text)) {
    console.log(`[ImageCheck] Non-visual keyword match: "${text}" → no`);
    return false;
  }

  // Check universal visual keywords
  if (VISUAL_KEYWORDS.test(text)) {
    console.log(`[ImageCheck] Visual keyword match: "${text}" → yes`);
    return true;
  }

  // Default: no image needed (no API call)
  console.log(`[ImageCheck] No keyword match: "${text}" → no`);
  return false;
}
