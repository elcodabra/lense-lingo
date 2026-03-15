"use client";

import { useState, useRef, useCallback, useEffect } from "react";
import { io, Socket } from "socket.io-client";
import AudioMode from "@/components/AudioMode";

type Language = "en" | "ru" | "es";
type AISource = "gemini" | "chatgpt";
type TransportMode = "rest" | "websocket";

interface Message {
  id: number;
  role: "user" | "assistant";
  text: string;
  source?: AISource;
  durationMs?: number;
  imagePreview?: string;
  transport?: TransportMode;
}

const LANGUAGES: { value: Language; label: string }[] = [
  { value: "en", label: "English" },
  { value: "ru", label: "Русский" },
  { value: "es", label: "Español" },
];

export default function Home() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [language, setLanguage] = useState<Language>("en");
  const [imageBase64, setImageBase64] = useState<string | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [imageMimeType, setImageMimeType] = useState("image/jpeg");
  const [loading, setLoading] = useState(false);
  const [imageCheckResult, setImageCheckResult] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<"chat" | "audio" | "image-check">("chat");
  const [transport, setTransport] = useState<TransportMode>("websocket");
  const [wsConnected, setWsConnected] = useState(false);
  const [isSpeaking, setIsSpeaking] = useState(false);
  const [speakingMsgId, setSpeakingMsgId] = useState<number | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const nextId = useRef(1);
  const socketRef = useRef<Socket | null>(null);

  // TTS language map
  const TTS_LANG: Record<Language, string> = { en: "en-US", ru: "ru-RU", es: "es-ES" };

  // Interrupt any ongoing TTS
  const interruptTTS = useCallback(() => {
    if (typeof window !== "undefined" && window.speechSynthesis.speaking) {
      window.speechSynthesis.cancel();
    }
    setIsSpeaking(false);
    setSpeakingMsgId(null);
  }, []);

  // Speak text, track which message is speaking
  const speakText = useCallback(
    (text: string, msgId: number) => {
      if (typeof window === "undefined" || !window.speechSynthesis) return;

      // Cancel any current speech first
      window.speechSynthesis.cancel();

      const utterance = new SpeechSynthesisUtterance(text);
      utterance.lang = TTS_LANG[language];
      utterance.rate = 1.0;

      utterance.onstart = () => {
        setIsSpeaking(true);
        setSpeakingMsgId(msgId);
      };
      utterance.onend = () => {
        setIsSpeaking(false);
        setSpeakingMsgId(null);
      };
      utterance.onerror = () => {
        setIsSpeaking(false);
        setSpeakingMsgId(null);
      };

      window.speechSynthesis.speak(utterance);
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [language]
  );

  // Pending speak ref for deferred TTS (from WS callbacks that can't call speakText directly)
  const pendingSpeakRef = useRef<{ text: string; id: number } | null>(null);
  // AbortController for in-flight REST requests
  const abortControllerRef = useRef<AbortController | null>(null);

  // Effect to process pending speak requests
  useEffect(() => {
    if (pendingSpeakRef.current) {
      const { text, id } = pendingSpeakRef.current;
      pendingSpeakRef.current = null;
      speakText(text, id);
    }
  });

  // Cleanup TTS on unmount
  useEffect(() => {
    return () => {
      if (typeof window !== "undefined") window.speechSynthesis.cancel();
    };
  }, []);

  // Socket.IO connection
  useEffect(() => {
    const socket = io({ autoConnect: false });

    socket.on("connect", () => setWsConnected(true));
    socket.on("disconnect", () => setWsConnected(false));

    socket.on("generate:result", (data: {
      requestId: string;
      text: string;
      source: AISource;
      durationMs: number;
    }) => {
      const msgId = nextId.current++;
      setMessages((prev) => [
        ...prev,
        {
          id: msgId,
          role: "assistant",
          text: data.text,
          source: data.source,
          durationMs: data.durationMs,
          transport: "websocket",
        },
      ]);
      setLoading(false);
      // TTS is triggered via effect
      pendingSpeakRef.current = { text: data.text, id: msgId };
    });

    socket.on("generate:error", (data: { error: string }) => {
      setMessages((prev) => [
        ...prev,
        {
          id: nextId.current++,
          role: "assistant",
          text: `Error: ${data.error}`,
          transport: "websocket",
        },
      ]);
      setLoading(false);
    });

    socket.on("check-image-needed:result", (data: { imageNeeded: boolean }) => {
      setImageCheckResult(
        data.imageNeeded
          ? "Yes — image IS needed for this request"
          : "No — image is NOT needed for this request"
      );
      setLoading(false);
    });

    socket.on("check-image-needed:error", (data: { error: string }) => {
      setImageCheckResult(`Error: ${data.error}`);
      setLoading(false);
    });

    socketRef.current = socket;

    return () => {
      socket.disconnect();
    };
  }, []);

  // Connect/disconnect based on transport mode
  useEffect(() => {
    const socket = socketRef.current;
    if (!socket) return;

    if (transport === "websocket") {
      socket.connect();
    } else {
      socket.disconnect();
    }
  }, [transport]);

  const clearImage = useCallback(() => {
    setImageBase64(null);
    setImagePreview(null);
    setImageMimeType("image/jpeg");
    if (fileInputRef.current) fileInputRef.current.value = "";
  }, []);

  const handleImageUpload = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (!file) return;
      setImageMimeType(file.type || "image/jpeg");
      const reader = new FileReader();
      reader.onload = () => {
        const dataUrl = reader.result as string;
        setImagePreview(dataUrl);
        const base64 = dataUrl.split(",")[1];
        setImageBase64(base64);
      };
      reader.readAsDataURL(file);
    },
    []
  );

  const sendViaRest = useCallback(
    async (text: string) => {
      // Cancel any previous in-flight request
      abortControllerRef.current?.abort();
      const controller = new AbortController();
      abortControllerRef.current = controller;

      const body: Record<string, unknown> = { text, language };
      if (imageBase64) {
        body.image = { base64: imageBase64, mimeType: imageMimeType };
      }
      try {
        const res = await fetch("/api/generate", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
          signal: controller.signal,
        });
        const data = await res.json();
        if (controller.signal.aborted) return;
        if (!res.ok) {
          setMessages((prev) => [
            ...prev,
            { id: nextId.current++, role: "assistant", text: `Error: ${data.error}`, transport: "rest" },
          ]);
        } else {
          const msgId = nextId.current++;
          setMessages((prev) => [
            ...prev,
            {
              id: msgId,
              role: "assistant",
              text: data.text,
              source: data.source,
              durationMs: data.durationMs,
              transport: "rest",
            },
          ]);
          if (data.text) speakText(data.text, msgId);
        }
      } catch (err) {
        if ((err as Error).name === "AbortError") return; // cancelled, ignore
        throw err;
      } finally {
        if (!controller.signal.aborted) {
          setLoading(false);
        }
      }
      clearImage();
    },
    [language, imageBase64, imageMimeType, clearImage, speakText]
  );

  const sendViaWebSocket = useCallback(
    (text: string) => {
      const socket = socketRef.current;
      if (!socket?.connected) return;

      const payload: Record<string, unknown> = {
        text,
        language,
        requestId: `req-${nextId.current}`,
      };
      if (imageBase64) {
        payload.image = { base64: imageBase64, mimeType: imageMimeType };
      }
      socket.emit("generate", payload);
      clearImage();
    },
    [language, imageBase64, imageMimeType, clearImage]
  );

  const sendMessage = useCallback(async () => {
    const text = input.trim();
    if (!text) return;

    // Interrupt any ongoing TTS and cancel in-flight requests
    interruptTTS();
    abortControllerRef.current?.abort();

    const userMsg: Message = {
      id: nextId.current++,
      role: "user",
      text,
      imagePreview: imagePreview ?? undefined,
    };
    setMessages((prev) => [...prev, userMsg]);
    setInput("");
    setLoading(true);

    if (transport === "websocket" && socketRef.current?.connected) {
      sendViaWebSocket(text);
    } else {
      try {
        await sendViaRest(text);
      } catch (err) {
        if ((err as Error).name === "AbortError") return;
        setMessages((prev) => [
          ...prev,
          {
            id: nextId.current++,
            role: "assistant",
            text: `Network error: ${err instanceof Error ? err.message : "Unknown"}`,
          },
        ]);
        setLoading(false);
        clearImage();
      }
    }
  }, [input, imagePreview, transport, sendViaWebSocket, sendViaRest, clearImage, interruptTTS]);

  const checkImageViaRest = useCallback(async () => {
    const text = input.trim();
    if (!text) return;
    setLoading(true);
    setImageCheckResult(null);
    try {
      const res = await fetch("/api/check-image-needed", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text, language }),
      });
      const data = await res.json();
      if (!res.ok) {
        setImageCheckResult(`Error: ${data.error}`);
      } else {
        setImageCheckResult(
          data.imageNeeded
            ? "Yes — image IS needed for this request"
            : "No — image is NOT needed for this request"
        );
      }
    } catch (err) {
      setImageCheckResult(
        `Network error: ${err instanceof Error ? err.message : "Unknown"}`
      );
    } finally {
      setLoading(false);
    }
  }, [input, language]);

  const checkImageViaWs = useCallback(() => {
    const text = input.trim();
    if (!text) return;
    const socket = socketRef.current;
    if (!socket?.connected) return;
    setLoading(true);
    setImageCheckResult(null);
    socket.emit("check-image-needed", { text, language, requestId: `check-${nextId.current}` });
  }, [input, language]);

  const checkImage = useCallback(() => {
    if (transport === "websocket" && socketRef.current?.connected) {
      checkImageViaWs();
    } else {
      checkImageViaRest();
    }
  }, [transport, checkImageViaWs, checkImageViaRest]);

  return (
    <div className="min-h-screen bg-[var(--background)] text-[var(--foreground)] flex flex-col">
      {/* Header */}
      <header className="border-b border-gray-200 dark:border-gray-800 px-6 py-4">
        <div className="max-w-3xl mx-auto flex items-center justify-between">
          <h1 className="text-xl font-semibold">LensLingo</h1>
          <div className="flex items-center gap-3">
            {/* Transport toggle */}
            <div className="flex items-center gap-2 bg-gray-100 dark:bg-gray-900 rounded-lg p-1">
              <button
                onClick={() => setTransport("rest")}
                className={`px-3 py-1 rounded-md text-xs font-medium transition-colors ${
                  transport === "rest"
                    ? "bg-white dark:bg-gray-800 shadow-sm"
                    : "hover:bg-gray-200 dark:hover:bg-gray-800"
                }`}
              >
                REST
              </button>
              <button
                onClick={() => setTransport("websocket")}
                className={`px-3 py-1 rounded-md text-xs font-medium transition-colors ${
                  transport === "websocket"
                    ? "bg-white dark:bg-gray-800 shadow-sm"
                    : "hover:bg-gray-200 dark:hover:bg-gray-800"
                }`}
              >
                WebSocket
              </button>
            </div>
            {/* WS status indicator */}
            {transport === "websocket" && (
              <span
                className={`inline-block w-2 h-2 rounded-full ${
                  wsConnected ? "bg-green-500" : "bg-red-500"
                }`}
                title={wsConnected ? "Connected" : "Disconnected"}
              />
            )}
            {/* Global language selector */}
            <select
              value={language}
              onChange={(e) => setLanguage(e.target.value as Language)}
              className="bg-gray-100 dark:bg-gray-800 border border-gray-300 dark:border-gray-700 rounded-lg px-2 py-1 text-xs"
            >
              {LANGUAGES.map((l) => (
                <option key={l.value} value={l.value}>
                  {l.label}
                </option>
              ))}
            </select>
          </div>
        </div>
      </header>

      {/* Tabs */}
      <div className="max-w-3xl mx-auto w-full px-6 pt-4">
        <div className="flex gap-1 bg-gray-100 dark:bg-gray-900 rounded-lg p-1">
          <button
            onClick={() => setActiveTab("chat")}
            className={`flex-1 py-2 px-4 rounded-md text-sm font-medium transition-colors ${
              activeTab === "chat"
                ? "bg-white dark:bg-gray-800 shadow-sm"
                : "hover:bg-gray-200 dark:hover:bg-gray-800"
            }`}
          >
            Chat / Generate
          </button>
          <button
            onClick={() => setActiveTab("audio")}
            className={`flex-1 py-2 px-4 rounded-md text-sm font-medium transition-colors ${
              activeTab === "audio"
                ? "bg-white dark:bg-gray-800 shadow-sm"
                : "hover:bg-gray-200 dark:hover:bg-gray-800"
            }`}
          >
            Audio
          </button>
          <button
            onClick={() => setActiveTab("image-check")}
            className={`flex-1 py-2 px-4 rounded-md text-sm font-medium transition-colors ${
              activeTab === "image-check"
                ? "bg-white dark:bg-gray-800 shadow-sm"
                : "hover:bg-gray-200 dark:hover:bg-gray-800"
            }`}
          >
            Image Check
          </button>
        </div>
      </div>

      {/* Main Content */}
      <main className="flex-1 max-w-3xl mx-auto w-full px-6 py-4 flex flex-col">
        {activeTab === "chat" ? (
          <>
            {/* Messages */}
            <div className="flex-1 overflow-y-auto space-y-4 mb-4">
              {messages.length === 0 && (
                <div className="text-center text-gray-400 dark:text-gray-600 py-20">
                  <p className="text-lg mb-2">Send a message to test the API</p>
                  <p className="text-sm">
                    Uses Gemini with ChatGPT fallback, just like the iOS app
                  </p>
                </div>
              )}
              {messages.map((msg) => (
                <div
                  key={msg.id}
                  className={`flex ${
                    msg.role === "user" ? "justify-end" : "justify-start"
                  }`}
                >
                  <div
                    className={`max-w-[80%] rounded-2xl px-4 py-3 ${
                      msg.role === "user"
                        ? "bg-blue-600 text-white"
                        : "bg-gray-100 dark:bg-gray-800"
                    }`}
                  >
                    {msg.imagePreview && (
                      <img
                        src={msg.imagePreview}
                        alt="Attached"
                        className="max-w-[200px] rounded-lg mb-2"
                      />
                    )}
                    {/* Speaking indicator */}
                    {msg.role === "assistant" && speakingMsgId === msg.id && (
                      <div className="flex items-center gap-2 mb-2">
                        <span className="inline-block w-1.5 h-3 bg-blue-500 rounded-full animate-pulse" />
                        <span className="inline-block w-1.5 h-4 bg-blue-500 rounded-full animate-pulse" style={{ animationDelay: "0.15s" }} />
                        <span className="inline-block w-1.5 h-3 bg-blue-500 rounded-full animate-pulse" style={{ animationDelay: "0.3s" }} />
                        <span className="text-xs text-blue-500 ml-1">Speaking...</span>
                        <button
                          onClick={interruptTTS}
                          className="ml-auto text-xs px-2 py-0.5 rounded bg-red-100 dark:bg-red-900/40 text-red-600 dark:text-red-300 hover:bg-red-200 dark:hover:bg-red-900/60"
                        >
                          Stop
                        </button>
                      </div>
                    )}
                    <p className="whitespace-pre-wrap">{msg.text}</p>
                    {(msg.source || msg.transport) && msg.role === "assistant" && (
                      <div className="flex items-center gap-2 mt-2 text-xs opacity-70">
                        {msg.source && (
                          <span
                            className={`px-2 py-0.5 rounded-full ${
                              msg.source === "gemini"
                                ? "bg-yellow-200 dark:bg-yellow-900 text-yellow-800 dark:text-yellow-200"
                                : "bg-green-200 dark:bg-green-900 text-green-800 dark:text-green-200"
                            }`}
                          >
                            {msg.source === "gemini" ? "Gemini" : "ChatGPT"}
                          </span>
                        )}
                        {msg.transport && (
                          <span className="px-2 py-0.5 rounded-full bg-gray-200 dark:bg-gray-700 text-gray-600 dark:text-gray-300">
                            {msg.transport === "websocket" ? "WS" : "REST"}
                          </span>
                        )}
                        {msg.durationMs !== undefined && (
                          <span>{(msg.durationMs / 1000).toFixed(2)}s</span>
                        )}
                        {/* Replay button (when not currently speaking) */}
                        {speakingMsgId !== msg.id && (
                          <button
                            onClick={() => speakText(msg.text, msg.id)}
                            className="px-2 py-0.5 rounded-full bg-gray-200 dark:bg-gray-700 text-gray-600 dark:text-gray-300 hover:bg-blue-200 dark:hover:bg-blue-900"
                            title="Replay"
                          >
                            &#9654;
                          </button>
                        )}
                      </div>
                    )}
                  </div>
                </div>
              ))}
              {loading && (
                <div className="flex justify-start">
                  <div className="bg-gray-100 dark:bg-gray-800 rounded-2xl px-4 py-3">
                    <div className="flex gap-1">
                      <span className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" />
                      <span
                        className="w-2 h-2 bg-gray-400 rounded-full animate-bounce"
                        style={{ animationDelay: "0.1s" }}
                      />
                      <span
                        className="w-2 h-2 bg-gray-400 rounded-full animate-bounce"
                        style={{ animationDelay: "0.2s" }}
                      />
                    </div>
                  </div>
                </div>
              )}
            </div>

            {/* Image preview */}
            {imagePreview && (
              <div className="mb-2 flex items-center gap-2">
                <img
                  src={imagePreview}
                  alt="Upload preview"
                  className="h-16 rounded-lg border border-gray-300 dark:border-gray-700"
                />
                <button
                  onClick={clearImage}
                  className="text-red-500 hover:text-red-700 text-sm"
                >
                  Remove
                </button>
              </div>
            )}

            {/* Status bar: shows during loading or speaking */}
            {(loading || isSpeaking) && (
              <div className={`mb-2 flex items-center gap-3 px-4 py-2 rounded-lg border ${
                isSpeaking
                  ? "bg-blue-50 dark:bg-blue-950/40 border-blue-200 dark:border-blue-800"
                  : "bg-gray-50 dark:bg-gray-900/40 border-gray-200 dark:border-gray-800"
              }`}>
                {isSpeaking ? (
                  <>
                    <span className="inline-block w-1.5 h-3 bg-blue-500 rounded-full animate-pulse" />
                    <span className="inline-block w-1.5 h-4 bg-blue-500 rounded-full animate-pulse" style={{ animationDelay: "0.15s" }} />
                    <span className="inline-block w-1.5 h-3 bg-blue-500 rounded-full animate-pulse" style={{ animationDelay: "0.3s" }} />
                    <span className="text-sm text-blue-600 dark:text-blue-300 flex-1">Speaking...</span>
                  </>
                ) : (
                  <>
                    <span className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" />
                    <span className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style={{ animationDelay: "0.1s" }} />
                    <span className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style={{ animationDelay: "0.2s" }} />
                    <span className="text-sm text-gray-500 dark:text-gray-400 flex-1">Thinking... type to interrupt</span>
                  </>
                )}
                <button
                  onClick={() => { interruptTTS(); abortControllerRef.current?.abort(); setLoading(false); }}
                  className="px-3 py-1 rounded-md bg-red-500 text-white text-sm font-medium hover:bg-red-600 transition-colors"
                >
                  Stop
                </button>
              </div>
            )}

            {/* Input area */}
            <div className="flex gap-2 items-end">
              <input
                type="file"
                accept="image/*"
                ref={fileInputRef}
                onChange={handleImageUpload}
                className="hidden"
              />
              <button
                onClick={() => fileInputRef.current?.click()}
                className="bg-gray-100 dark:bg-gray-800 border border-gray-300 dark:border-gray-700 rounded-lg px-3 py-2 hover:bg-gray-200 dark:hover:bg-gray-700 text-sm"
                title="Attach image"
              >
                Image
              </button>

              <input
                type="text"
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && !e.shiftKey) {
                    e.preventDefault();
                    sendMessage();
                  }
                }}
                placeholder={loading ? "Type to interrupt..." : "Type a message..."}
                className="flex-1 bg-gray-100 dark:bg-gray-800 border border-gray-300 dark:border-gray-700 rounded-lg px-4 py-2"
              />
              <button
                onClick={sendMessage}
                disabled={!input.trim()}
                className="bg-blue-600 text-white rounded-lg px-5 py-2 hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed font-medium"
              >
                Send
              </button>
            </div>
          </>
        ) : activeTab === "audio" ? (
          <AudioMode
            language={language}
            transport={transport}
            socket={socketRef.current}
            wsConnected={wsConnected}
          />
        ) : (
          /* Image Check Tab */
          <div className="flex-1 flex flex-col items-center justify-center gap-6 py-10">
            <div className="text-center mb-4">
              <h2 className="text-lg font-semibold mb-1">
                Image Need Checker
              </h2>
              <p className="text-sm text-gray-500">
                Tests whether a user query requires camera image context
              </p>
            </div>

            <div className="w-full max-w-md flex flex-col gap-3">
              <select
                value={language}
                onChange={(e) => setLanguage(e.target.value as Language)}
                className="bg-gray-100 dark:bg-gray-800 border border-gray-300 dark:border-gray-700 rounded-lg px-3 py-2 text-sm"
              >
                {LANGUAGES.map((l) => (
                  <option key={l.value} value={l.value}>
                    {l.label}
                  </option>
                ))}
              </select>

              <input
                type="text"
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    e.preventDefault();
                    checkImage();
                  }
                }}
                placeholder='e.g. "What do you see?" or "Tell me a joke"'
                className="bg-gray-100 dark:bg-gray-800 border border-gray-300 dark:border-gray-700 rounded-lg px-4 py-2"
                disabled={loading}
              />

              <button
                onClick={checkImage}
                disabled={loading || !input.trim()}
                className="bg-purple-600 text-white rounded-lg px-5 py-2 hover:bg-purple-700 disabled:opacity-50 disabled:cursor-not-allowed font-medium"
              >
                {loading ? "Checking..." : "Check if image needed"}
              </button>

              {imageCheckResult && (
                <div
                  className={`p-4 rounded-lg text-center font-medium ${
                    imageCheckResult.startsWith("Yes")
                      ? "bg-yellow-100 dark:bg-yellow-900/30 text-yellow-800 dark:text-yellow-200"
                      : imageCheckResult.startsWith("No")
                        ? "bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-200"
                        : "bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-200"
                  }`}
                >
                  {imageCheckResult}
                </div>
              )}
            </div>
          </div>
        )}
      </main>

      {/* Footer */}
      <footer className="border-t border-gray-200 dark:border-gray-800 px-6 py-3">
        <div className="max-w-3xl mx-auto flex justify-between text-xs text-gray-400">
          <span>REST: /api/generate, /api/check-image-needed</span>
          <span>WS: generate, check-image-needed</span>
        </div>
      </footer>
    </div>
  );
}
