/**
 * Host side of chat dictation: records the microphone and hands back a
 * WAV clip for the ai-proxy's speech-to-text endpoint.
 *
 * A VSCode webview can't open the microphone (its iframe isn't granted
 * the permission), so recording happens here in the extension host
 * through the vendored PvRecorder native module — the same route other
 * extensions' voice input takes. macOS attributes the microphone
 * permission prompt to VSCode itself.
 *
 * Kept free of `vscode` imports so the pure parts are unit-testable.
 */

import * as fs from 'node:fs'
import * as path from 'node:path'
import { Worker } from 'node:worker_threads'
import {
  CONTROL_CANCEL,
  CONTROL_RUN,
  CONTROL_STOP,
  type DictationWorkerInput,
  type DictationWorkerMessage,
} from './dictation-protocol.js'

/** Longest clip the input lets run. Matches the ai-proxy's default
 *  `listen.maxSeconds`; the proxy enforces its own copy server-side. */
export const DICTATION_MAX_SECONDS = 120

// Shorter than this and it was a stray click, not speech.
const MIN_CLIP_SECONDS = 0.3

// The microphone should be delivering frames well within this.
const START_TIMEOUT_MS = 5_000
const STOP_TIMEOUT_MS = 5_000
const CANCEL_GRACE_MS = 2_000

/** Folders of PvRecorder's prebuilt binaries, keyed `platform/arch`. */
const NATIVE_BINARY_DIRS: Record<string, string> = {
  'darwin/arm64': 'mac/arm64',
  'darwin/x64': 'mac/x86_64',
  'linux/x64': 'linux/x86_64',
  'win32/x64': 'windows/amd64',
  'win32/arm64': 'windows/arm64',
}

/**
 * An error whose `message` is shown in the chat input as-is, so it stays
 * short and free of technical detail. What actually went wrong goes in
 * `detail`, for the log.
 */
export class DictationError extends Error {
  constructor(
    message: string,
    readonly detail?: string
  ) {
    super(message)
    this.name = 'DictationError'
  }
}

// Everything the user can be shown about a recording gone wrong.
const MIC_UNAVAILABLE = 'Couldn’t access the microphone.'
const MIC_SILENT = 'No sound — check microphone access.'
const RECORDING_FAILED = 'Recording failed — try again.'
const RECORDING_TOO_SHORT = 'Too short — try again.'

interface ActiveRecording {
  worker: Worker
  control: Int32Array
  /** Settles once the worker has posted its clip (or failed). */
  audio: Promise<Extract<DictationWorkerMessage, { type: 'audio' }>>
}

export class DictationRecorder {
  private active: ActiveRecording | null = null

  constructor(
    private readonly opts: {
      /** `ExtensionContext.extensionPath`. */
      extensionPath: string
      log: (message: string) => void
    }
  ) {}

  private get pvrecorderDir(): string {
    return path.join(this.opts.extensionPath, 'static', 'pvrecorder')
  }

  /** True when a recorder binary for this machine shipped with the
   *  extension. Says nothing about whether a microphone is attached. */
  isSupported(): boolean {
    const dir = NATIVE_BINARY_DIRS[`${process.platform}/${process.arch}`]
    if (!dir) return false
    return fs.existsSync(
      path.join(this.pvrecorderDir, 'lib', dir, 'pv_recorder.node')
    )
  }

  get isRecording(): boolean {
    return this.active !== null
  }

  /** Start capturing. Resolves once the microphone is live. */
  async start(): Promise<void> {
    if (this.active) {
      throw new DictationError(RECORDING_FAILED, 'already recording')
    }

    const control = new Int32Array(new SharedArrayBuffer(4))
    const workerData: DictationWorkerInput = {
      pvrecorderDir: this.pvrecorderDir,
      maxSeconds: DICTATION_MAX_SECONDS,
      control: control.buffer as SharedArrayBuffer,
    }
    const worker = new Worker(
      path.join(this.opts.extensionPath, 'out', 'dictation-worker.js'),
      { workerData }
    )

    let onStarted!: () => void
    let onStartFailed!: (err: Error) => void
    const started = new Promise<void>((resolve, reject) => {
      onStarted = resolve
      onStartFailed = reject
    })
    const audio = new Promise<
      Extract<DictationWorkerMessage, { type: 'audio' }>
    >((resolve, reject) => {
      const fail = (message: string, detail: string): void => {
        const err = new DictationError(message, detail)
        onStartFailed(err)
        reject(err)
      }
      const recorderFailed = (detail: string): void =>
        fail(MIC_UNAVAILABLE, `recorder error: ${detail}`)
      worker.on('message', (msg: DictationWorkerMessage) => {
        if (msg.type === 'started') onStarted()
        else if (msg.type === 'audio') resolve(msg)
        else recorderFailed(msg.message)
      })
      worker.on('error', (err) => recorderFailed(err.message))
      worker.on('exit', () => fail(RECORDING_FAILED, 'worker exited early'))
    })
    // A cancelled or failed recording has nobody awaiting `audio`.
    audio.catch(() => undefined)

    const recording: ActiveRecording = { worker, control, audio }
    this.active = recording
    try {
      await withTimeout(
        started,
        START_TIMEOUT_MS,
        new DictationError(MIC_UNAVAILABLE, 'microphone did not start')
      )
    } catch (err) {
      this.discard(recording)
      throw err
    }
  }

  /** Stop capturing and return the clip as a 16-bit PCM WAV file. */
  async stop(): Promise<Buffer> {
    const recording = this.active
    if (!recording) {
      throw new DictationError(RECORDING_FAILED, 'no recording in progress')
    }
    this.active = null
    signal(recording.control, CONTROL_STOP)
    try {
      const clip = await withTimeout(
        recording.audio,
        STOP_TIMEOUT_MS,
        new DictationError(RECORDING_FAILED, 'no audio back from the worker')
      )
      const seconds = clip.pcm.length / clip.sampleRate
      this.opts.log(
        `dictation: captured ${seconds.toFixed(1)}s (peak ${clip.peak})`
      )
      if (seconds < MIN_CLIP_SECONDS) {
        throw new DictationError(RECORDING_TOO_SHORT)
      }
      if (clip.peak === 0) {
        // Exact zeros are what the OS hands out in place of audio when
        // the app isn't allowed to listen.
        throw new DictationError(MIC_SILENT, 'clip is digital silence')
      }
      return encodeWav(clip.pcm, clip.sampleRate)
    } finally {
      void recording.worker.terminate()
    }
  }

  /** Stop capturing and drop the clip. Safe to call when idle. */
  cancel(): void {
    const recording = this.active
    if (!recording) return
    this.discard(recording)
  }

  private discard(recording: ActiveRecording): void {
    if (this.active === recording) this.active = null
    // Let the worker wind down by itself so it closes the microphone;
    // killing it mid-read would leave the device open. Terminate only
    // if it hasn't gone after a moment.
    signal(recording.control, CONTROL_CANCEL)
    const kill = setTimeout(
      () => void recording.worker.terminate(),
      CANCEL_GRACE_MS
    )
    recording.worker.once('exit', () => clearTimeout(kill))
  }
}

function signal(control: Int32Array, value: number): void {
  if (Atomics.compareExchange(control, 0, CONTROL_RUN, value) === CONTROL_RUN) {
    Atomics.notify(control, 0)
  }
}

function withTimeout<T>(
  promise: Promise<T>,
  ms: number,
  onTimeout: DictationError
): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(onTimeout), ms)
    promise.then(
      (value) => {
        clearTimeout(timer)
        resolve(value)
      },
      (err) => {
        clearTimeout(timer)
        reject(err)
      }
    )
  })
}

/** Wrap mono 16-bit PCM samples in a canonical 44-byte WAV header. */
export function encodeWav(pcm: Int16Array, sampleRate: number): Buffer {
  const dataBytes = pcm.length * 2
  const wav = Buffer.alloc(44 + dataBytes)
  wav.write('RIFF', 0, 'ascii')
  wav.writeUInt32LE(36 + dataBytes, 4)
  wav.write('WAVE', 8, 'ascii')
  wav.write('fmt ', 12, 'ascii')
  wav.writeUInt32LE(16, 16) // fmt chunk size
  wav.writeUInt16LE(1, 20) // PCM
  wav.writeUInt16LE(1, 22) // mono
  wav.writeUInt32LE(sampleRate, 24)
  wav.writeUInt32LE(sampleRate * 2, 28) // bytes per second
  wav.writeUInt16LE(2, 32) // block align
  wav.writeUInt16LE(16, 34) // bits per sample
  wav.write('data', 36, 'ascii')
  wav.writeUInt32LE(dataBytes, 40)
  for (let i = 0; i < pcm.length; i++) {
    wav.writeInt16LE(pcm[i]!, 44 + i * 2)
  }
  return wav
}
