import dotenv from "dotenv";
import express from "express";
import { createServer } from "node:http";
import { WebSocket, WebSocketServer, type RawData } from "ws";
import {
  AudioFormat,
  CommitStrategy,
  ElevenLabsClient,
  RealtimeEvents,
  type RealtimeConnection,
} from "@elevenlabs/elevenlabs-js";

// Load local development credentials first, then fall back to .env.
dotenv.config({ path: ".env.local" });
dotenv.config();

const port = Number(process.env.PORT ?? 3000);
const apiKey = process.env.ELEVENLABS_API_KEY;
const accessToken = process.env.BACKEND_ACCESS_TOKEN;

if (!apiKey || !accessToken) {
  console.error(
    "Missing ELEVENLABS_API_KEY or BACKEND_ACCESS_TOKEN. Add both to apd_backend/.env.local or apd_backend/.env.",
  );
  process.exit(1);
}

const elevenlabs = new ElevenLabsClient({ apiKey });
const app = express();
app.get("/health", (_request, response) => {
  response.json({ status: "ok", service: "apd_backend" });
});

const server = createServer(app);
const clients = new WebSocketServer({
  noServer: true,
  maxPayload: 1024 * 1024,
});
const maxPendingAudioBytes = 1024 * 1024;

server.on("upgrade", (request, socket, head) => {
  const pathname = new URL(request.url ?? "/", "http://localhost").pathname;
  if (pathname !== "/transcribe") {
    socket.write("HTTP/1.1 404 Not Found\r\n\r\n");
    socket.destroy();
    return;
  }

  const suppliedToken = request.headers.authorization?.replace(
    /^Bearer\s+/i,
    "",
  );
  if (suppliedToken !== accessToken) {
    socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
    socket.destroy();
    return;
  }

  clients.handleUpgrade(request, socket, head, (client) => {
    clients.emit("connection", client, request);
  });
});

clients.on("connection", (client, request) => {
  const clientAddress = request.socket.remoteAddress ?? "unknown";
  const query = new URL(request.url ?? "/", "http://localhost").searchParams;
  const languageCode = query.get("language_code") ?? undefined;
  let upstream: RealtimeConnection | undefined;
  let upstreamReady = false;
  let clientClosed = false;
  let stopRequested = false;
  let pendingStop = false;
  let pendingStopTimer: NodeJS.Timeout | undefined;
  const pendingAudio: Buffer[] = [];
  let pendingAudioBytes = 0;

  console.log(`Client connected from ${clientAddress}.`);

  const sendToClient = (payload: string): void => {
    if (client.readyState === WebSocket.OPEN) client.send(payload);
  };

  const forwardEvent = (event: { message_type: string }): void => {
    sendToClient(JSON.stringify(event));
    console.log(`ElevenLabs response forwarded to ${clientAddress}:`, event);
  };

  const closeUpstream = (): void => {
    if (pendingStopTimer) clearTimeout(pendingStopTimer);
    pendingStopTimer = undefined;
    upstream?.close();
  };

  const sendStop = (): void => {
    if (!upstreamReady || !upstream || stopRequested) return;
    stopRequested = true;
    try {
      upstream.commit();
      pendingStopTimer = setTimeout(closeUpstream, 2300);
    } catch (error) {
      sendToClient(
        JSON.stringify({
          message_type: "error",
          error: errorMessage(error),
        }),
      );
      closeUpstream();
    }
  };

  const sendAudio = (audio: Buffer): void => {
    if (!upstreamReady || !upstream) {
      if (pendingAudioBytes + audio.length > maxPendingAudioBytes) {
        sendToClient(
          JSON.stringify({
            message_type: "error",
            error:
              "Transcription service is taking too long to start. Please try again.",
          }),
        );
        client.close(1013, "Transcription service startup timeout.");
        return;
      }
      pendingAudio.push(audio);
      pendingAudioBytes += audio.length;
      return;
    }

    upstream.send({ audioBase64: audio.toString("base64") });
  };

  // Tell Flutter the relay is ready. Audio is buffered until ElevenLabs starts.
  sendToClient(JSON.stringify({ message_type: "relay_ready" }));

  void elevenlabs.speechToText.realtime
    .connect({
      modelId: "scribe_v2_realtime",
      audioFormat: AudioFormat.PCM_16000,
      sampleRate: 16000,
      commitStrategy: CommitStrategy.VAD,
      includeTimestamps: true,
      languageCode,
    })
    .then((connection) => {
      upstream = connection;
      if (clientClosed) {
        connection.close();
        return;
      }

      connection.on(RealtimeEvents.SESSION_STARTED, (event) => {
        upstreamReady = true;
        forwardEvent(event);
        while (pendingAudio.length > 0) {
          const audio = pendingAudio.shift();
          if (!audio) continue;
          pendingAudioBytes -= audio.length;
          connection.send({ audioBase64: audio.toString("base64") });
        }
        if (pendingStop) sendStop();
      });

      connection.on(RealtimeEvents.PARTIAL_TRANSCRIPT, forwardEvent);
      connection.on(RealtimeEvents.FINAL_TRANSCRIPT, forwardEvent);
      connection.on(RealtimeEvents.FINAL_TRANSCRIPT_WITH_TIMESTAMPS, forwardEvent);

      const onCommittedTranscript = (
        event: { message_type: string },
      ): void => {
        forwardEvent(event);
        if (stopRequested) closeUpstream();
      };
      connection.on(RealtimeEvents.COMMITTED_TRANSCRIPT, onCommittedTranscript);
      connection.on(
        RealtimeEvents.COMMITTED_TRANSCRIPT_WITH_TIMESTAMPS,
        onCommittedTranscript,
      );

      connection.on(RealtimeEvents.ERROR, (error) => {
        const message = errorMessage(error);
        console.error(
          `ElevenLabs error for client ${clientAddress}: ${message}`,
        );
        sendToClient(JSON.stringify({ message_type: "error", error: message }));
        if (client.readyState === WebSocket.OPEN) {
          client.close(1011, "ElevenLabs transcription failed.");
        }
      });

      connection.on(RealtimeEvents.CLOSE, () => {
        if (pendingStopTimer) clearTimeout(pendingStopTimer);
        pendingStopTimer = undefined;
        console.log(`ElevenLabs connection closed for client ${clientAddress}.`);
        sendToClient(JSON.stringify({ message_type: "relay_closed" }));
        if (!clientClosed && client.readyState === WebSocket.OPEN) {
          client.close(1000, "Transcription relay closed.");
        }
      });
    })
    .catch((error: unknown) => {
      const message = errorMessage(error);
      console.error(
        `Could not start ElevenLabs for client ${clientAddress}: ${message}`,
      );
      sendToClient(JSON.stringify({ message_type: "error", error: message }));
      if (client.readyState === WebSocket.OPEN) {
        client.close(1011, "ElevenLabs connection failed.");
      }
    });

  client.on("message", (data: RawData, isBinary: boolean) => {
    if (isBinary) {
      sendAudio(toBuffer(data));
      return;
    }

    let control: { type?: string; audio_base_64?: unknown };
    try {
      control = JSON.parse(data.toString());
    } catch {
      sendToClient(
        JSON.stringify({
          message_type: "error",
          error: "Text frames must be JSON control messages.",
        }),
      );
      return;
    }

    if (control.type === "stop") {
      if (upstreamReady) sendStop();
      else pendingStop = true;
    } else if (
      control.type === "audio_chunk" &&
      typeof control.audio_base_64 === "string"
    ) {
      sendAudio(Buffer.from(control.audio_base_64, "base64"));
    } else {
      sendToClient(
        JSON.stringify({
          message_type: "error",
          error: "Unknown control message.",
        }),
      );
    }
  });

  client.on("close", () => {
    clientClosed = true;
    if (pendingStopTimer) clearTimeout(pendingStopTimer);
    console.log(`Client ${clientAddress} disconnected.`);
    closeUpstream();
  });

  client.on("error", (error) => {
    clientClosed = true;
    console.error(
      `Client websocket error from ${clientAddress}: ${error.message}`,
    );
    closeUpstream();
  });
});

function toBuffer(data: RawData): Buffer {
  if (Buffer.isBuffer(data)) return data;
  if (Array.isArray(data)) return Buffer.concat(data);
  return Buffer.from(data);
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (
    typeof error === "object" &&
    error !== null &&
    "error" in error &&
    typeof error.error === "string"
  ) {
    return error.error;
  }
  return "ElevenLabs connection failed.";
}

server.listen(port, "0.0.0.0", () => {
  console.log(`apd_backend listening on 0.0.0.0:${port}`);
});
