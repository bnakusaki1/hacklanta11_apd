import 'dotenv/config';

import express from 'express';
import { createServer } from 'node:http';
import { WebSocket, WebSocketServer } from 'ws';

const port = Number(process.env.PORT ?? 3000);
const apiKey = process.env.ELEVENLABS_API_KEY;
const accessToken = process.env.BACKEND_ACCESS_TOKEN;

const app = express();
app.get('/health', (_request, response) => {
  response.json({ status: 'ok', service: 'apd_backend' });
});

const server = createServer(app);
const clients = new WebSocketServer({ noServer: true, maxPayload: 1024 * 1024 });

server.on('upgrade', (request, socket, head) => {
  const pathname = new URL(request.url ?? '/', 'http://localhost').pathname;
  if (pathname !== '/transcribe') {
    socket.write('HTTP/1.1 404 Not Found\r\n\r\n');
    socket.destroy();
    return;
  }

  if (!apiKey || !accessToken) {
    socket.write('HTTP/1.1 503 Service Unavailable\r\n\r\n');
    socket.destroy();
    return;
  }

  const suppliedToken = request.headers.authorization?.replace(/^Bearer\s+/i, '');
  if (accessToken && suppliedToken !== accessToken) {
    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
    socket.destroy();
    return;
  }

  clients.handleUpgrade(request, socket, head, (client) => {
    clients.emit('connection', client, request);
  });
});

clients.on('connection', (client, request) => {
  const query = new URL(request.url ?? '/', 'http://localhost').searchParams;
  const audioFormat = query.get('audio_format') ?? 'pcm_16000';
  const languageCode = query.get('language_code');
  if (!['pcm_16000', 'pcm_24000', 'pcm_48000'].includes(audioFormat)) {
    client.close(1008, 'Unsupported audio format.');
    return;
  }

  const upstreamUrl = new URL('wss://api.elevenlabs.io/v1/speech-to-text/realtime');
  upstreamUrl.searchParams.set('model_id', 'scribe_v2_realtime');
  upstreamUrl.searchParams.set('audio_format', audioFormat);
  upstreamUrl.searchParams.set('commit_strategy', 'vad');
  if (languageCode) upstreamUrl.searchParams.set('language_code', languageCode);

  const upstream = new WebSocket(upstreamUrl, {
    headers: { 'xi-api-key': apiKey },
    maxPayload: 1024 * 1024,
  });
  let upstreamReady = false;
  let clientClosed = false;
  let pendingStopTimer;

  const sendToClient = (payload) => {
    if (client.readyState === WebSocket.OPEN) client.send(payload);
  };

  upstream.on('message', (data, isBinary) => {
    if (isBinary) return;
    const message = data.toString();
    try {
      const event = JSON.parse(message);
      if (event.message_type === 'session_started') upstreamReady = true;
      sendToClient(message);
      if (
        ['committed_transcript', 'committed_transcript_with_timestamps'].includes(event.message_type) &&
        pendingStopTimer
      ) {
        clearTimeout(pendingStopTimer);
        pendingStopTimer = undefined;
        upstream.close(1000, 'Transcription complete.');
      }
    } catch {
      sendToClient(JSON.stringify({ message_type: 'error', error: 'Invalid response from ElevenLabs.' }));
    }
  });

  upstream.on('open', () => {
    sendToClient(JSON.stringify({ message_type: 'relay_ready' }));
  });

  upstream.on('error', () => {
    sendToClient(JSON.stringify({ message_type: 'error', error: 'ElevenLabs connection failed.' }));
    if (client.readyState === WebSocket.OPEN) client.close(1011, 'Upstream connection failed.');
  });

  upstream.on('close', (code, reason) => {
    if (pendingStopTimer) clearTimeout(pendingStopTimer);
    if (!clientClosed && client.readyState === WebSocket.OPEN) {
      sendToClient(JSON.stringify({
        message_type: 'relay_closed',
        code,
        reason: reason.toString(),
      }));
      client.close(1000, 'Transcription relay closed.');
    }
  });

  client.on('message', (data, isBinary) => {
    if (!upstreamReady || upstream.readyState !== WebSocket.OPEN) {
      sendToClient(JSON.stringify({ message_type: 'error', error: 'Transcription session is not ready yet.' }));
      return;
    }

    if (isBinary) {
      const audio = Buffer.concat(
        Array.isArray(data) ? data : [Buffer.from(data)],
      );
      upstream.send(JSON.stringify({
        message_type: 'input_audio_chunk',
        audio_base_64: audio.toString('base64'),
      }));
      return;
    }

    let control;
    try {
      control = JSON.parse(data.toString());
    } catch {
      sendToClient(JSON.stringify({ message_type: 'error', error: 'Text frames must be JSON control messages.' }));
      return;
    }

    if (control.type === 'stop') {
      upstream.send(JSON.stringify({
        message_type: 'input_audio_chunk',
        audio_base_64: '',
        commit: true,
      }));
      pendingStopTimer = setTimeout(() => upstream.close(1000, 'Client stopped.'), 2000);
    } else if (control.type === 'audio_chunk' && typeof control.audio_base_64 === 'string') {
      upstream.send(JSON.stringify({
        message_type: 'input_audio_chunk',
        audio_base_64: control.audio_base_64,
      }));
    } else {
      sendToClient(JSON.stringify({ message_type: 'error', error: 'Unknown control message.' }));
    }
  });

  client.on('close', () => {
    clientClosed = true;
    if (pendingStopTimer) clearTimeout(pendingStopTimer);
    if (upstream.readyState === WebSocket.OPEN || upstream.readyState === WebSocket.CONNECTING) {
      upstream.close(1000, 'Client disconnected.');
    }
  });

  client.on('error', () => {
    clientClosed = true;
    upstream.terminate();
  });
});

server.listen(port, '0.0.0.0', () => {
  console.log(`apd_backend listening on 0.0.0.0:${port}`);
});
