/**
 * Contract between the dictation recorder (dictation.ts, extension host
 * thread) and its capture worker (dictation-worker.ts).
 */

/** Control flag values the host writes into the shared buffer. */
export const CONTROL_RUN = 0
export const CONTROL_STOP = 1
export const CONTROL_CANCEL = 2

export interface DictationWorkerInput {
  /** Folder holding the vendored `@picovoice/pvrecorder-node` package. */
  pvrecorderDir: string
  /** Recording stops by itself once this much audio is captured. */
  maxSeconds: number
  /** One Int32 slot: `CONTROL_RUN` until the host stops or cancels. */
  control: SharedArrayBuffer
}

export type DictationWorkerMessage =
  | { type: 'started' }
  | {
      type: 'audio'
      pcm: Int16Array
      sampleRate: number
      /** Largest absolute sample value seen; 0 means digital silence. */
      peak: number
    }
  | { type: 'error'; message: string }
