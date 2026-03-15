"use client";

import { useState, useRef, useCallback, useEffect } from "react";
import { Socket } from "socket.io-client";

type Language = "en" | "ru" | "es";
type AISource = "gemini" | "chatgpt";
type TransportMode = "rest" | "websocket";

interface ConversationTurn {
  id: number;
  userText: string;
  transcriptionSource?: "whisper" | "gemini";
  transcriptionMs?: number;
  aiText?: string;
  aiSource?: AISource;
  aiMs?: number;
  transport?: TransportMode;
  status: "transcribing" | "thinking" | "speaking" | "done" | "error";
  error?: string;
}

const LANG_LABELS: Record<Language, string> = {
  en: "English",
  ru: "Русский",
  es: "Español",
};

// TTS voice language mapping
const TTS_LANG: Record<Language, string> = {
  en: "en-US",
  ru: "ru-RU",
  es: "es-ES",
};

interface AudioModeProps {
  language: Language;
  transport: TransportMode;
  socket: Socket | null;
  wsConnected: boolean;
}

export default function AudioMode({ language, transport, socket, wsConnected }: AudioModeProps) {
  const [turns, setTurns] = useState<ConversationTurn[]>([]);
  const [isRecording, setIsRecording] = useState(false);
  const [isSpeaking, setIsSpeaking] = useState(false);
  const [autoListen, setAutoListen] = useState(false);
  const [micLevel, setMicLevel] = useState(0);

  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const audioChunksRef = useRef<Blob[]>([]);
  const nextIdRef = useRef(1);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const animFrameRef = useRef<number>(0);
  const streamRef = useRef<MediaStream | null>(null);
  const shouldAutoListenRef = useRef(false);
  const turnsEndRef = useRef<HTMLDivElement>(null);
  const utteranceRef = useRef<SpeechSynthesisUtterance | null>(null);
  const speakAbortRef = useRef(false);

  // Keep ref in sync
  useEffect(() => {
    shouldAutoListenRef.current = autoListen;
  }, [autoListen]);

  // Scroll to bottom on new turns
  useEffect(() => {
    turnsEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [turns]);

  // Force-stop TTS — works around Chrome's unreliable cancel()
  const forceStopTTS = useCallback(() => {
    speakAbortRef.current = true;
    if (typeof window !== "undefined") {
      // Remove event handlers so they don't interfere
      if (utteranceRef.current) {
        utteranceRef.current.onstart = null;
        utteranceRef.current.onend = null;
        utteranceRef.current.onerror = null;
        utteranceRef.current = null;
      }
      // Chrome workaround: pause → resume → cancel
      window.speechSynthesis.pause();
      window.speechSynthesis.resume();
      window.speechSynthesis.cancel();
      setIsSpeaking(false);
      setTurns((prev) =>
        prev.map((t) => (t.status === "speaking" ? { ...t, status: "done" } : t))
      );
    }
    socket?.emit("interrupt", { requestId: "interrupt" });
  }, [socket]);

  // Speak text with TTS, returns promise that resolves when done or interrupted
  const speak = useCallback(
    (text: string): Promise<void> => {
      return new Promise((resolve) => {
        if (typeof window === "undefined" || !window.speechSynthesis) {
          resolve();
          return;
        }

        // Cancel any previous speech first
        speakAbortRef.current = false;
        window.speechSynthesis.cancel();

        let resolved = false;
        const done = () => {
          if (resolved) return;
          resolved = true;
          utteranceRef.current = null;
          setIsSpeaking(false);
          resolve();
        };

        const utterance = new SpeechSynthesisUtterance(text);
        utterance.lang = TTS_LANG[language];
        utterance.rate = 1.0;
        utterance.pitch = 1.0;

        utterance.onstart = () => {
          if (speakAbortRef.current) {
            window.speechSynthesis.cancel();
            done();
            return;
          }
          setIsSpeaking(true);
        };
        utterance.onend = done;
        utterance.onerror = done;

        utteranceRef.current = utterance;
        window.speechSynthesis.speak(utterance);

        // Safety: if cancel() doesn't fire events, resolve after a short delay
        // when abort is requested
        const checkAbort = setInterval(() => {
          if (speakAbortRef.current) {
            clearInterval(checkAbort);
            window.speechSynthesis.cancel();
            done();
          }
          if (resolved) clearInterval(checkAbort);
        }, 100);
      });
    },
    [language]
  );

  // Update a turn by id
  const updateTurn = useCallback(
    (id: number, updates: Partial<ConversationTurn>) => {
      setTurns((prev) =>
        prev.map((t) => (t.id === id ? { ...t, ...updates } : t))
      );
    },
    []
  );

  // Process audio via REST
  const processAudioRest = useCallback(
    async (audioBlob: Blob, turnId: number) => {
      const formData = new FormData();
      formData.append("audio", audioBlob);
      formData.append("language", language);

      try {
        const res = await fetch("/api/audio", {
          method: "POST",
          body: formData,
        });
        const data = await res.json();

        if (!res.ok) {
          updateTurn(turnId, { status: "error", error: data.error });
          return;
        }

        if (!data.transcription?.text?.trim()) {
          updateTurn(turnId, {
            status: "done",
            userText: "(no speech detected)",
            transcriptionSource: data.transcription?.source,
            transcriptionMs: data.transcription?.durationMs,
          });
          return;
        }

        updateTurn(turnId, {
          userText: data.transcription.text,
          transcriptionSource: data.transcription.source,
          transcriptionMs: data.transcription.durationMs,
          aiText: data.response?.text,
          aiSource: data.response?.source,
          aiMs: data.response?.durationMs,
          transport: "rest",
          status: "speaking",
        });

        if (data.response?.text) {
          await speak(data.response.text);
        }

        updateTurn(turnId, { status: "done" });

        // Auto-listen after response
        if (shouldAutoListenRef.current) {
          startRecording();
        }
      } catch (err) {
        updateTurn(turnId, {
          status: "error",
          error: err instanceof Error ? err.message : "Network error",
        });
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [language, speak, updateTurn]
  );

  // Process audio via WebSocket
  const processAudioWs = useCallback(
    (audioBlob: Blob, turnId: number) => {
      console.log(`[AudioMode] processAudioWs called, socket=${!!socket}, connected=${socket?.connected}, turnId=${turnId}`);
      if (!socket?.connected) {
        updateTurn(turnId, { status: "error", error: "WebSocket not connected" });
        return;
      }

      const requestId = `audio-${turnId}`;
      let cleaned = false;

      const cleanup = () => {
        if (cleaned) return;
        cleaned = true;
        clearTimeout(timeout);
        socket.off("audio:transcribed", onTranscribed);
        socket.off("audio:result", onResult);
        socket.off("audio:error", onError);
      };

      const onTranscribed = (data: { requestId: string; text: string; source: string; durationMs: number }) => {
        console.log(`[AudioMode] audio:transcribed received`, data);
        if (data.requestId !== requestId) return;
        updateTurn(turnId, {
          userText: data.text || "(no speech detected)",
          transcriptionSource: data.source as "whisper" | "gemini",
          transcriptionMs: data.durationMs,
          status: data.text?.trim() ? "thinking" : "done",
        });
      };

      const onResult = (data: {
        requestId: string;
        transcription: { text: string; source: string; durationMs: number };
        response: { text: string; source: AISource; durationMs: number } | null;
      }) => {
        if (data.requestId !== requestId) return;
        cleanup();

        updateTurn(turnId, {
          userText: data.transcription.text || "(no speech detected)",
          transcriptionSource: data.transcription.source as "whisper" | "gemini",
          transcriptionMs: data.transcription.durationMs,
          aiText: data.response?.text,
          aiSource: data.response?.source,
          aiMs: data.response?.durationMs,
          transport: "websocket",
          status: data.response?.text ? "speaking" : "done",
        });

        if (data.response?.text) {
          speak(data.response.text).then(() => {
            updateTurn(turnId, { status: "done" });
            if (shouldAutoListenRef.current) {
              startRecording();
            }
          });
        } else if (shouldAutoListenRef.current) {
          startRecording();
        }
      };

      const onError = (data: { requestId: string; error: string }) => {
        console.log(`[AudioMode] audio:error received`, data);
        if (data.requestId !== requestId) return;
        cleanup();
        updateTurn(turnId, { status: "error", error: data.error });
      };

      // Timeout — 30s
      const timeout = setTimeout(() => {
        cleanup();
        updateTurn(turnId, { status: "error", error: "Request timed out (30s)" });
      }, 30000);

      socket.on("audio:transcribed", onTranscribed);
      socket.on("audio:result", onResult);
      socket.on("audio:error", onError);

      // Send audio as base64
      console.log(`[AudioMode] Sending audio via WS, socket.connected=${socket.connected}, requestId=${requestId}, blobSize=${audioBlob.size}, mime=${audioBlob.type}`);
      const reader = new FileReader();
      reader.onload = () => {
        const base64 = (reader.result as string).split(",")[1];
        console.log(`[AudioMode] Emitting 'audio' event, base64 length=${base64?.length}`);
        socket.emit("audio", {
          audio: base64,
          audioMimeType: audioBlob.type,
          language,
          requestId,
        });
      };
      reader.onerror = (err) => {
        console.error("[AudioMode] FileReader error:", err);
      };
      reader.readAsDataURL(audioBlob);
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [socket, language, speak, updateTurn]
  );

  // Start recording
  const startRecording = useCallback(async () => {
    // Interrupt any ongoing TTS
    forceStopTTS();

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      streamRef.current = stream;

      // Audio level visualization
      const audioCtx = new AudioContext();
      const source = audioCtx.createMediaStreamSource(stream);
      const analyser = audioCtx.createAnalyser();
      analyser.fftSize = 256;
      source.connect(analyser);
      analyserRef.current = analyser;

      const dataArray = new Uint8Array(analyser.frequencyBinCount);
      const updateLevel = () => {
        analyser.getByteFrequencyData(dataArray);
        const avg = dataArray.reduce((a, b) => a + b, 0) / dataArray.length;
        setMicLevel(avg / 128); // normalize to 0-2 range
        animFrameRef.current = requestAnimationFrame(updateLevel);
      };
      updateLevel();

      const mediaRecorder = new MediaRecorder(stream, {
        mimeType: MediaRecorder.isTypeSupported("audio/webm;codecs=opus")
          ? "audio/webm;codecs=opus"
          : "audio/webm",
      });
      audioChunksRef.current = [];

      mediaRecorder.ondataavailable = (e) => {
        if (e.data.size > 0) audioChunksRef.current.push(e.data);
      };

      mediaRecorder.onstop = () => {
        cancelAnimationFrame(animFrameRef.current);
        setMicLevel(0);
        stream.getTracks().forEach((t) => t.stop());
        streamRef.current = null;

        const audioBlob = new Blob(audioChunksRef.current, {
          type: mediaRecorder.mimeType,
        });

        console.log(`[AudioMode] Recording stopped, blob size=${audioBlob.size}, mime=${audioBlob.type}`);
        if (audioBlob.size < 1000) {
          console.log("[AudioMode] Audio too short, skipping");
          return;
        }

        const turnId = nextIdRef.current++;
        console.log(`[AudioMode] Creating turn ${turnId}, transport=${transport}, socket.connected=${socket?.connected}`);
        setTurns((prev) => [
          ...prev,
          {
            id: turnId,
            userText: "...",
            status: "transcribing",
          },
        ]);

        if (transport === "websocket" && socket?.connected) {
          processAudioWs(audioBlob, turnId);
        } else {
          processAudioRest(audioBlob, turnId);
        }
      };

      mediaRecorderRef.current = mediaRecorder;
      mediaRecorder.start();
      setIsRecording(true);
    } catch (err) {
      console.error("Microphone access error:", err);
    }
  }, [forceStopTTS, transport, socket, processAudioWs, processAudioRest]);

  // Stop recording
  const stopRecording = useCallback(() => {
    if (mediaRecorderRef.current?.state === "recording") {
      mediaRecorderRef.current.stop();
    }
    setIsRecording(false);
  }, []);

  // Toggle recording
  const toggleRecording = useCallback(() => {
    if (isRecording) {
      stopRecording();
    } else {
      startRecording();
    }
  }, [isRecording, startRecording, stopRecording]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      cancelAnimationFrame(animFrameRef.current);
      streamRef.current?.getTracks().forEach((t) => t.stop());
      if (typeof window !== "undefined") {
        window.speechSynthesis.cancel();
      }
    };
  }, []);

  return (
    <div className="flex-1 flex flex-col">
      {/* Conversation history */}
      <div className="flex-1 overflow-y-auto space-y-4 mb-4">
        {turns.length === 0 && (
          <div className="text-center text-gray-400 dark:text-gray-600 py-16">
            <p className="text-lg mb-2">Audio Mode</p>
            <p className="text-sm mb-1">
              Tap the mic to record → audio is sent to backend → transcribed → AI responds → TTS speaks
            </p>
            <p className="text-sm">
              Start talking while AI speaks to naturally interrupt
            </p>
          </div>
        )}

        {turns.map((turn) => (
          <div key={turn.id} className="space-y-2">
            {/* User turn */}
            <div className="flex justify-end">
              <div className="max-w-[80%] rounded-2xl px-4 py-3 bg-blue-600 text-white">
                <p className="whitespace-pre-wrap">{turn.userText}</p>
                {turn.transcriptionSource && (
                  <div className="flex items-center gap-2 mt-1 text-xs opacity-70">
                    <span className="px-2 py-0.5 rounded-full bg-blue-500">
                      {turn.transcriptionSource === "whisper" ? "Whisper" : "Gemini"} STT
                    </span>
                    {turn.transcriptionMs !== undefined && (
                      <span>{(turn.transcriptionMs / 1000).toFixed(2)}s</span>
                    )}
                  </div>
                )}
              </div>
            </div>

            {/* AI turn */}
            {(turn.status === "transcribing" || turn.status === "thinking") && (
              <div className="flex justify-start">
                <div className="bg-gray-100 dark:bg-gray-800 rounded-2xl px-4 py-3">
                  <div className="flex items-center gap-2 text-sm text-gray-500">
                    <div className="flex gap-1">
                      <span className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" />
                      <span className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style={{ animationDelay: "0.1s" }} />
                      <span className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style={{ animationDelay: "0.2s" }} />
                    </div>
                    <span>
                      {turn.status === "transcribing" ? "Transcribing..." : "Thinking..."}
                    </span>
                  </div>
                </div>
              </div>
            )}

            {turn.aiText && (
              <div className="flex justify-start">
                <div className="max-w-[80%] rounded-2xl px-4 py-3 bg-gray-100 dark:bg-gray-800">
                  {turn.status === "speaking" && (
                    <div className="flex items-center gap-1 mb-2">
                      <span className="inline-block w-1.5 h-3 bg-blue-500 rounded-full animate-pulse" />
                      <span className="inline-block w-1.5 h-4 bg-blue-500 rounded-full animate-pulse" style={{ animationDelay: "0.15s" }} />
                      <span className="inline-block w-1.5 h-3 bg-blue-500 rounded-full animate-pulse" style={{ animationDelay: "0.3s" }} />
                      <span className="text-xs text-blue-500 ml-1">Speaking...</span>
                    </div>
                  )}
                  <p className="whitespace-pre-wrap">{turn.aiText}</p>
                  <div className="flex items-center gap-2 mt-2 text-xs opacity-70">
                    {turn.aiSource && (
                      <span
                        className={`px-2 py-0.5 rounded-full ${
                          turn.aiSource === "gemini"
                            ? "bg-yellow-200 dark:bg-yellow-900 text-yellow-800 dark:text-yellow-200"
                            : "bg-green-200 dark:bg-green-900 text-green-800 dark:text-green-200"
                        }`}
                      >
                        {turn.aiSource === "gemini" ? "Gemini" : "ChatGPT"}
                      </span>
                    )}
                    {turn.transport && (
                      <span className="px-2 py-0.5 rounded-full bg-gray-200 dark:bg-gray-700 text-gray-600 dark:text-gray-300">
                        {turn.transport === "websocket" ? "WS" : "REST"}
                      </span>
                    )}
                    {turn.aiMs !== undefined && (
                      <span>{(turn.aiMs / 1000).toFixed(2)}s</span>
                    )}
                  </div>
                </div>
              </div>
            )}

            {turn.status === "error" && (
              <div className="flex justify-start">
                <div className="max-w-[80%] rounded-2xl px-4 py-3 bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-200">
                  Error: {turn.error}
                </div>
              </div>
            )}
          </div>
        ))}
        <div ref={turnsEndRef} />
      </div>

      {/* Controls */}
      <div className="flex flex-col items-center gap-4 pb-4">
        {/* Auto-listen toggle */}
        <label className="flex items-center gap-2 text-sm cursor-pointer">
          <input
            type="checkbox"
            checked={autoListen}
            onChange={(e) => setAutoListen(e.target.checked)}
            className="w-4 h-4 accent-green-500"
          />
          <span>Auto-listen after response</span>
        </label>

        {/* Mic button */}
        <div className="flex items-center gap-4">
          <button
            onClick={() => {
              forceStopTTS();
              toggleRecording();
            }}
            className={`relative w-20 h-20 rounded-full flex items-center justify-center transition-all ${
              isRecording
                ? "bg-red-500 hover:bg-red-600 scale-110"
                : "bg-blue-600 hover:bg-blue-700"
            }`}
          >
            {/* Mic level ring */}
            {isRecording && (
              <span
                className="absolute inset-0 rounded-full border-4 border-red-300 animate-ping"
                style={{
                  opacity: Math.min(micLevel * 0.5, 0.8),
                  transform: `scale(${1 + micLevel * 0.15})`,
                }}
              />
            )}
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 24 24"
              fill="white"
              className="w-8 h-8"
            >
              {isRecording ? (
                <rect x="6" y="6" width="12" height="12" rx="2" />
              ) : (
                <path d="M12 1a4 4 0 0 0-4 4v6a4 4 0 0 0 8 0V5a4 4 0 0 0-4-4Zm7 10a7 7 0 0 1-6 6.93V21h3a1 1 0 1 1 0 2H8a1 1 0 1 1 0-2h3v-3.07A7 7 0 0 1 5 11a1 1 0 1 1 2 0 5 5 0 0 0 10 0 1 1 0 1 1 2 0Z" />
              )}
            </svg>
          </button>
        </div>

        <p className="text-xs text-gray-400">
          {isRecording
            ? "Recording... tap to stop"
            : isSpeaking
              ? "AI is speaking — tap mic or Interrupt to cut in"
              : `Tap mic to speak (${LANG_LABELS[language]})`}
        </p>
      </div>
    </div>
  );
}
