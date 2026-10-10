# apd_backend

Express and WebSocket relay for ElevenLabs Scribe v2 Realtime. The Flutter app connects to `/transcribe`; the backend sends PCM audio chunks to ElevenLabs and relays transcript events back to Flutter.

## Run locally

1. Install Node.js 20 or newer.
2. Copy `.env.example` to `.env` and set `ELEVENLABS_API_KEY`. Set `BACKEND_ACCESS_TOKEN` to a long random value.
3. Run `npm install`, then `npm start` from this directory.
4. Confirm `http://localhost:3000/health` returns `{"status":"ok","service":"apd_backend"}`.
5. In the app's Settings, enter the backend WebSocket URL and the same access token.

For an Android emulator, use `ws://10.0.2.2:3000/transcribe`. For the iOS simulator use `ws://127.0.0.1:3000/transcribe`. A physical phone needs the computer's LAN address, for example `ws://192.168.1.20:3000/transcribe`, and both devices must be on the same network. Use `wss://` when deployed outside local development.

## Audio protocol

- The Flutter client opens `ws(s)://<host>/transcribe` with an optional `Authorization: Bearer <BACKEND_ACCESS_TOKEN>` header.
- Wait for `session_started` before sending audio. Send binary WebSocket frames containing mono PCM16 audio at 16 kHz.
- The relay converts each binary frame to ElevenLabs' `input_audio_chunk` JSON message.
- The backend relays ElevenLabs `partial_transcript`, `committed_transcript`, and session events to Flutter as JSON text frames.
- Send `{"type":"stop"}` to request a final commit. The relay closes the upstream session after the final transcript or a short timeout.

The Flutter client exposes `TranscriptionBackendClient.sendAudioChunk(Uint8List)` for the audio-capture work that will be merged later. This prototype does not capture microphone audio itself.

Keep `.env` private. The ElevenLabs key is held only by the backend. `BACKEND_ACCESS_TOKEN` is required for every WebSocket connection; local network deployments should still be treated as prototype-only.
