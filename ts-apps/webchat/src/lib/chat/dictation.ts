// Browser-side microphone capture for chat dictation.
//
// The VSCode extension records in its host process because a webview can't
// open a microphone; in the standalone web chat the page can, so the bridge
// records here. Both hand the ai-proxy's speech-to-text endpoint the same
// thing: a 16 kHz mono 16-bit PCM WAV. MediaRecorder's own output (WebM/Opus
// in Chrome and Firefox, MP4/AAC in Safari) is decoded and re-encoded on
// stop — WAV is the one format every transcription provider accepts, and it
// lets the proxy measure the clip itself.

/** Longest clip the input lets run. Matches the ai-proxy's default
 *  `listen.maxSeconds`; the proxy enforces its own copy server-side. */
export const DICTATION_MAX_SECONDS = 120

const WAV_SAMPLE_RATE = 16_000

// Shorter than this and it was a stray tap, not speech.
const MIN_CLIP_SECONDS = 0.3

/** An error whose message is shown in the chat input as-is — so it
 *  stays short and free of technical detail. */
export class DictationError extends Error {}

const RECORDING_FAILED = 'Recording failed — try again.'

/** Whether this page can record at all. Microphone access needs a secure
 *  context, so plain-http deployments get no dictation UI. */
export function canRecord(): boolean {
  return (
    typeof window !== 'undefined' &&
    window.isSecureContext &&
    typeof MediaRecorder !== 'undefined' &&
    !!navigator.mediaDevices?.getUserMedia
  )
}

export class BrowserRecorder {
  private stream: MediaStream | null = null
  private recorder: MediaRecorder | null = null
  private chunks: Blob[] = []

  get isRecording(): boolean {
    return this.recorder !== null
  }

  /** Ask for the microphone (prompting the first time) and start capturing. */
  async start(): Promise<void> {
    this.cancel()
    let stream: MediaStream
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          channelCount: 1,
          echoCancellation: true,
          noiseSuppression: true,
        },
      })
    } catch (err) {
      throw new DictationError(describeMicError(err))
    }
    const recorder = new MediaRecorder(stream)
    this.chunks = []
    recorder.ondataavailable = (e) => {
      if (e.data.size > 0) this.chunks.push(e.data)
    }
    recorder.start()
    this.stream = stream
    this.recorder = recorder
  }

  /** Stop capturing and return the clip as a base64 PCM WAV. */
  async stop(): Promise<string> {
    const recorder = this.recorder
    if (!recorder) throw new DictationError(RECORDING_FAILED)
    const recorded = await new Promise<Blob>((resolve) => {
      recorder.onstop = () =>
        resolve(new Blob(this.chunks, { type: recorder.mimeType }))
      recorder.stop()
    })
    this.release()

    let samples: Float32Array
    try {
      samples = await decodeToMono16k(recorded)
    } catch {
      throw new DictationError(RECORDING_FAILED)
    }
    if (samples.length / WAV_SAMPLE_RATE < MIN_CLIP_SECONDS) {
      throw new DictationError('Too short — try again.')
    }
    return blobToBase64(new Blob([encodeWav(samples)]))
  }

  /** Stop capturing and drop the clip. Safe to call when idle. */
  cancel(): void {
    const recorder = this.recorder
    if (recorder && recorder.state !== 'inactive') {
      recorder.onstop = null
      recorder.stop()
    }
    this.release()
  }

  /** Let go of the microphone so the browser's recording indicator clears. */
  private release(): void {
    this.stream?.getTracks().forEach((t) => t.stop())
    this.stream = null
    this.recorder = null
    this.chunks = []
  }
}

function describeMicError(err: unknown): string {
  const name = err instanceof DOMException ? err.name : ''
  return name === 'NotAllowedError' || name === 'SecurityError'
    ? 'Microphone access is blocked.'
    : 'Couldn’t access the microphone.'
}

/** Decode whatever container MediaRecorder produced and resample it to
 *  mono 16 kHz. An OfflineAudioContext does the down-mix and resampling. */
async function decodeToMono16k(recorded: Blob): Promise<Float32Array> {
  const ctx = new AudioContext()
  let decoded: AudioBuffer
  try {
    decoded = await ctx.decodeAudioData(await recorded.arrayBuffer())
  } finally {
    void ctx.close()
  }
  const frames = Math.max(1, Math.ceil(decoded.duration * WAV_SAMPLE_RATE))
  const offline = new OfflineAudioContext(1, frames, WAV_SAMPLE_RATE)
  const source = offline.createBufferSource()
  source.buffer = decoded
  source.connect(offline.destination)
  source.start()
  return (await offline.startRendering()).getChannelData(0)
}

/** Wrap mono float samples (-1..1) as 16-bit PCM in a canonical 44-byte
 *  WAV header. */
export function encodeWav(samples: Float32Array): ArrayBuffer {
  const dataBytes = samples.length * 2
  const view = new DataView(new ArrayBuffer(44 + dataBytes))
  const ascii = (offset: number, s: string): void => {
    for (let i = 0; i < s.length; i++)
      view.setUint8(offset + i, s.charCodeAt(i))
  }
  ascii(0, 'RIFF')
  view.setUint32(4, 36 + dataBytes, true)
  ascii(8, 'WAVE')
  ascii(12, 'fmt ')
  view.setUint32(16, 16, true) // fmt chunk size
  view.setUint16(20, 1, true) // PCM
  view.setUint16(22, 1, true) // mono
  view.setUint32(24, WAV_SAMPLE_RATE, true)
  view.setUint32(28, WAV_SAMPLE_RATE * 2, true) // bytes per second
  view.setUint16(32, 2, true) // block align
  view.setUint16(34, 16, true) // bits per sample
  ascii(36, 'data')
  view.setUint32(40, dataBytes, true)
  for (let i = 0; i < samples.length; i++) {
    const s = Math.max(-1, Math.min(1, samples[i]!))
    view.setInt16(44 + i * 2, s < 0 ? s * 0x8000 : s * 0x7fff, true)
  }
  return view.buffer
}

function blobToBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onerror = () => reject(reader.error)
    reader.onload = () => {
      // "data:<type>;base64,<payload>" — the endpoint wants the payload only.
      const url = reader.result as string
      resolve(url.slice(url.indexOf(',') + 1))
    }
    reader.readAsDataURL(blob)
  })
}
