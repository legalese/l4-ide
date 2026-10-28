/**
 * Microphone capture for chat dictation, run as a `worker_threads`
 * worker. PvRecorder's read call blocks until the next audio frame is
 * ready, so driving it from the extension host's own thread would stall
 * everything else the extension does for as long as the user is talking.
 *
 * Bundled separately to `out/dictation-worker.js` (see scripts/build.mjs)
 * and spawned by `DictationRecorder` in dictation.ts.
 */

import { parentPort, workerData } from 'node:worker_threads'

import {
  CONTROL_RUN,
  CONTROL_STOP,
  type DictationWorkerInput,
  type DictationWorkerMessage,
} from './dictation-protocol.js'

interface PvRecorderInstance {
  readonly sampleRate: number
  start(): void
  stop(): void
  readSync(): Int16Array
  release(): void
}

// 32 ms at PvRecorder's 16 kHz — short enough that a stop request is
// noticed without a perceptible lag.
const FRAME_LENGTH = 512

// How long a clip that ran into the length cap is kept waiting for the
// host to collect it before the worker gives up and exits.
const COLLECT_TIMEOUT_MS = 60_000

function post(message: DictationWorkerMessage, transfer?: ArrayBuffer[]): void {
  parentPort?.postMessage(message, transfer ?? [])
}

function run(): void {
  const { pvrecorderDir, maxSeconds, control } =
    workerData as DictationWorkerInput
  const flag = new Int32Array(control)

  let recorder: PvRecorderInstance
  try {
    // Runtime path, not a bundled dependency: the package finds its
    // native binary relative to its own folder.
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const { PvRecorder } = require(pvrecorderDir) as {
      PvRecorder: new (frameLength: number) => PvRecorderInstance
    }
    recorder = new PvRecorder(FRAME_LENGTH)
    recorder.start()
  } catch (err) {
    post({ type: 'error', message: errorMessage(err) })
    return
  }
  post({ type: 'started' })

  const sampleRate = recorder.sampleRate
  const maxSamples = maxSeconds * sampleRate
  const frames: Int16Array[] = []
  let samples = 0
  let peak = 0
  try {
    while (Atomics.load(flag, 0) === CONTROL_RUN && samples < maxSamples) {
      const frame = recorder.readSync()
      frames.push(frame)
      samples += frame.length
      for (let i = 0; i < frame.length; i++) {
        const v = Math.abs(frame[i]!)
        if (v > peak) peak = v
      }
    }
  } catch (err) {
    post({ type: 'error', message: errorMessage(err) })
    return
  } finally {
    try {
      recorder.stop()
      recorder.release()
    } catch {
      // Already torn down — nothing left to free.
    }
  }

  // Reached the cap before being told to stop: hold the audio until the
  // host asks for it.
  if (Atomics.load(flag, 0) === CONTROL_RUN) {
    Atomics.wait(flag, 0, CONTROL_RUN, COLLECT_TIMEOUT_MS)
  }
  if (Atomics.load(flag, 0) !== CONTROL_STOP) return

  const pcm = new Int16Array(samples)
  let offset = 0
  for (const frame of frames) {
    pcm.set(frame, offset)
    offset += frame.length
  }
  post({ type: 'audio', pcm, sampleRate, peak }, [pcm.buffer as ArrayBuffer])
}

function errorMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err)
}

run()
