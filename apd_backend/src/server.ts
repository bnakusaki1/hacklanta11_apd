import 'dotenv/config';
import express from 'express';
import http from 'http';
import { URL } from 'url';
import WebSocket, { WebSocketServer, RawData } from 'ws';

const ELEVENLABS_API_KEY = process.env.ELEVENLABS_API_KEY;
const ELEVENLABS_URL = 'wss://api.elevenlabs.io/v1/speech-to-text/realtime';
const SAMPLE_RATE = 16000; // client audio must be 16 kHz, mono, 16-bit PCM (LE)
const STOP_TIMEOUT_MS = 3000;

if (!ELEVENLABS_API_KEY) {
  console.error('Missing ELEVENLABS_API_KEY');
  process.exit(1);
}

const app = express();
app.get('/health', (_req, res) => res.json({ ok: true }));

const server = http.createServer(app);
const wss = new WebSocketServer({ noServer: true, maxPayload: 1024 * 1024 });

// Only /transcribe accepts WebSocket upgrades
server.on('upgrade', (req, socket, head) => {
  const { pathname } = new URL(req.url ?? '', `http://${req.headers.host}`);
  if (pathname !== '/transcribe') {
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws, req));
});

function toBuffer(data: RawData): Buffer {
  if (Buffer.isBuffer(data)) return data;
  if (Array.isArray(data)) return Buffer.concat(data);
  return Buffer.from(data as ArrayBuffer);
}

wss.on('connection', (client: WebSocket, req) => {
  const id = Math.random().toString(36).slice(2, 8);
  const log = (...args: unknown[]) => console.log(`[${id}]`, ...args);
  log('client connected');

  const { searchParams } = new URL(req.url ?? '', `http://${req.headers.host}`);
  const includeTimestamps = searchParams.get('include_timestamps') === 'true';

  const params = new URLSearchParams({
    model_id: 'scribe_v2_realtime',
    audio_format: 'pcm_16000',
    commit_strategy: searchParams.get('commit_strategy') ?? 'vad',
    include_timestamps: String(includeTimestamps),w
  });
  const languageCode = searchParams.get('language_code');
  if (languageCode) params.set('language_code', languageCode);

  const upstream = new WebSocket(`${ELEVENLABS_URL}?${params}`, {
    headers: { 'xi-api-key': ELEVENLABS_API_KEY },
  });

  let upstreamReady = false;
  let stopping = false;
  let stopTimer: NodeJS.Timeout | undefined;
  let chunksIn = 0;
  let bytesIn = 0;
  const queue: string[] = []; // audio that arrives before ElevenLabs is ready

  const sendUpstream = (payload: object) => {
    const msg = JSON.stringify(payload);
    if (upstreamReady) upstream.send(msg);
    else queue.push(msg);
  };

  const sendAudio = (pcm: Buffer) => {
    if (pcm.length === 0) return;
    chunksIn++;
    bytesIn += pcm.length;
    if (chunksIn % 20 === 1) log(`[audio in] chunk #${chunksIn}, ${bytesIn} bytes total`);
    sendUpstream({
      message_type: 'input_audio_chunk',
      audio_base_64: pcm.toString('base64'),
      commit: false,
      sample_rate: SAMPLE_RATE,
    });
  };

  const commit = () => {
    log('[commit]');
    sendUpstream({
      message_type: 'input_audio_chunk',
      audio_base_64: '',
      commit: true,
      sample_rate: SAMPLE_RATE,
    });
  };

  const finish = () => {
    clearTimeout(stopTimer);
    if (client.readyState === WebSocket.OPEN) client.close(1000, 'done');
    if (upstream.readyState === WebSocket.OPEN || upstream.readyState === WebSocket.CONNECTING) {
      upstream.close();
    }
  };

  // Client says it is done: flush the tail, wait for the final transcript, then close
  const stop = () => {
    if (stopping) return;
    stopping = true;
    log('[stop] requested by client');
    commit();
    stopTimer = setTimeout(() => {
      log('[stop] timed out waiting for final transcript');
      finish();
    }, STOP_TIMEOUT_MS);
  };

  // ---------- Client -> ElevenLabs ----------
  client.on('message', (data, isBinary) => {
    if (stopping) return;

    // 1) Binary frame = raw PCM audio
    if (isBinary) {
      sendAudio(toBuffer(data));
      return;
    }

    // 2) Text frame = control word or JSON
    const text = toBuffer(data).toString('utf8').trim();

    if (text === 'commit') return commit();
    if (text === 'stop') return stop();

    try {
      const msg = JSON.parse(text);
      const type = msg.type ?? msg.message_type;
      const b64: string | undefined = msg.audio_base_64 ?? msg.audio ?? msg.data;

      if (b64 && (type === undefined || type === 'audio' || type === 'input_audio_chunk')) {
        sendAudio(Buffer.from(b64, 'base64'));
      } else if (type === 'commit') {
        commit();
      } else if (type === 'stop') {
        stop();
      } else {
        log('[unknown json message]', text.slice(0, 200));
      }
    } catch {
      log('[unknown text message]', text.slice(0, 200));
    }
  });

  // ---------- ElevenLabs -> Client ----------
  upstream.on('open', () => {
    upstreamReady = true;
    log('[upstream] connected to ElevenLabs');
    queue.splice(0).forEach((m) => upstream.send(m));
  });

  upstream.on('message', (data) => {
    const raw = toBuffer(data).toString('utf8');

    let type = 'unparsed';
    try {
      const msg = JSON.parse(raw);
      type = msg.message_type;
      switch (type) {
        case 'partial_transcript':
          log(`[partial]   ${msg.text}`);
          break;
        case 'committed_transcript':
          log(`[committed] ${msg.text}`);
          break;
        case 'committed_transcript_with_timestamps':
          log(`[committed+timestamps] ${msg.text ?? ''}`, msg.words);
          break;
        default:
          log(`[${type}]`, msg);
      }
    } catch {
      log('[unparsed upstream message]', raw);
    }

    if (client.readyState === WebSocket.OPEN) client.send(raw);

    // During a stop, the final transcript means we can close
    if (stopping) {
      const final = includeTimestamps
        ? 'committed_transcript_with_timestamps'
        : 'committed_transcript';
      if (type === final) finish();
    }
  });

  upstream.on('error', (err) => {
    log('[upstream error]', err.message);
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify({ message_type: 'error', error: err.message }));
    }
    finish();
  });

  upstream.on('close', (code, reason) => {
    log(`[upstream] closed (${code}) ${reason.toString()}`);
    finish();
  });

  client.on('close', () => {
    log(`client disconnected (${chunksIn} chunks, ${bytesIn} bytes received)`);
    clearTimeout(stopTimer);
    if (upstream.readyState === WebSocket.OPEN || upstream.readyState === WebSocket.CONNECTING) {
      upstream.close();
    }
  });

  client.on('error', (err) => log('[client error]', err.message));
});

const PORT = Number(process.env.PORT) || 3000;
server.listen(PORT, () => console.log(`Server listening on port ${PORT}`));