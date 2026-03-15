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
  switch (lang) {
    case "ru":
      return " Отвечай на русском языке, так как пользователь спросил на русском.";
    case "es":
      return " Responde en español, ya que el usuario preguntó en español.";
    default:
      return " Respond in English, as the user asked in English.";
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

function getImageCheckPrompt(text: string, lang: Language): string {
  switch (lang) {
    case "ru":
      return `Пользователь носит умные очки с камерой. Он спросил: "${text}"

Нужна ли картинка с камеры для ответа на этот запрос?

Ответьте ТОЛЬКО "yes" или "no" - больше ничего.

Примеры, где НУЖНА картинка: "Что ты видишь?", "Что я вижу?", "Что видно?", "Расскажи что вижу", "Опиши что вижу"
Примеры, где НЕ НУЖНА картинка: вопросы о погоде, шутки, вопросы о времени, общие вопросы не о визуальном контенте.`;
    case "es":
      return `El usuario está usando gafas inteligentes con una cámara. Preguntó: "${text}"

¿Esta solicitud necesita ver lo que la cámara está mostrando actualmente?

Responde SOLO "yes" o "no" - nada más.

Ejemplos que NECESITAN imagen: "¿Qué ves?", "¿Qué veo?", "Describe lo que está frente a mí"
Ejemplos que NO necesitan imagen: preguntas sobre el clima, chistes, preguntas sobre la hora.`;
    default:
      return `The user is wearing smart glasses with a camera. They asked: "${text}"

Does this request need to see what the camera is currently showing?

Answer ONLY "yes" or "no" - nothing else.

Examples that NEED image: "What do you see?", "What do I see?", "Describe what's in front of me"
Examples that DON'T need image: weather questions, jokes, time questions, general questions.`;
  }
}

export async function checkImageNeeded(
  text: string,
  lang: Language = "en"
): Promise<boolean> {
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
