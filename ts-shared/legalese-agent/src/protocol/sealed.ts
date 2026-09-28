/**
 * Sealed secrets for cloud sessions (spec §6.4).
 *
 * The harness generates an ephemeral X25519 key pair at start and
 * publishes the public key in its `session-state: running` event. The
 * extension seals MCP credentials to that key and sends them as an
 * `mcp-credentials` command; only ciphertext ever reaches a file. The
 * private key lives only in the task's memory.
 *
 * Construction (an ECIES / HPKE-base-mode shape, with Node's `crypto`):
 *
 *   ephemeral X25519 key pair (sender)
 *   shared = X25519(ephemeral private, recipient public)
 *   key    = HKDF-SHA256(ikm = shared,
 *                        salt = epk ‖ recipient public,
 *                        info = "legalese-cloud-session/sealed/v1\0" ‖ context,
 *                        32 bytes)
 *   ct‖tag = AES-256-GCM(key, iv = 12 random bytes, aad = context)
 *
 * `context` binds a ciphertext to its purpose and session (e.g.
 * `mcp-credentials:<sid>`): opening with a different context fails, so
 * a sealed blob can't be replayed into another session or command type.
 * Keys are single-use per seal (fresh ephemeral key and IV).
 *
 * Works in plain Node and the VS Code extension host (both Node).
 */
import {
  createCipheriv,
  createDecipheriv,
  createPublicKey,
  diffieHellman,
  generateKeyPairSync,
  hkdfSync,
  randomBytes,
  type KeyObject,
} from 'node:crypto'
import { literal, obj, str, type Check } from './validate.js'

export const SEALED_ALG = 'X25519-HKDF-SHA256-A256GCM'

/** base64url without padding. */
const B64URL_RE = /^[A-Za-z0-9_-]+$/

/** What travels in an `mcp-credentials` command. All fields base64url. */
export interface SealedEnvelope {
  v: 1
  alg: typeof SEALED_ALG
  /** Sender's ephemeral X25519 public key (32 bytes). */
  epk: string
  /** AES-GCM nonce (12 bytes). */
  iv: string
  /** Ciphertext. */
  ct: string
  /** AES-GCM tag (16 bytes). */
  tag: string
}

export const sealedEnvelope: Check<SealedEnvelope> = obj({
  v: literal(1),
  alg: literal(SEALED_ALG),
  epk: str({ min: 43, max: 43, pattern: B64URL_RE }),
  iv: str({ min: 16, max: 16, pattern: B64URL_RE }),
  ct: str({ max: 1_000_000, pattern: /^[A-Za-z0-9_-]*$/ }),
  tag: str({ min: 22, max: 22, pattern: B64URL_RE }),
})

/** The harness's key pair. `publicKey` is what goes in the
 *  `session-state` event; `privateKey` never leaves the process. */
export interface SealingKeyPair {
  /** Raw 32-byte X25519 public key, base64url. */
  publicKey: string
  privateKey: KeyObject
}

export function generateSealingKeyPair(): SealingKeyPair {
  const { publicKey, privateKey } = generateKeyPairSync('x25519')
  return { publicKey: rawPublicKey(publicKey), privateKey }
}

/** Is this a well-formed sealing public key (as published by a harness)? */
export function isSealingPublicKey(value: unknown): value is string {
  if (typeof value !== 'string' || !B64URL_RE.test(value)) return false
  return Buffer.from(value, 'base64url').length === 32
}

function rawPublicKey(key: KeyObject): string {
  const jwk = key.export({ format: 'jwk' }) as { x?: string }
  if (!jwk.x) throw new Error('not an X25519 public key')
  return jwk.x
}

function importPublicKey(raw: string): KeyObject {
  if (!isSealingPublicKey(raw)) {
    throw new Error('invalid sealing public key')
  }
  return createPublicKey({
    key: { kty: 'OKP', crv: 'X25519', x: raw },
    format: 'jwk',
  })
}

function deriveKey(
  shared: Buffer,
  epk: string,
  recipient: string,
  context: string
): Buffer {
  const salt = Buffer.concat([
    Buffer.from(epk, 'base64url'),
    Buffer.from(recipient, 'base64url'),
  ])
  const info = Buffer.concat([
    Buffer.from('legalese-cloud-session/sealed/v1\0', 'utf8'),
    Buffer.from(context, 'utf8'),
  ])
  return Buffer.from(hkdfSync('sha256', shared, salt, info, 32))
}

/**
 * Seal `plaintext` to a harness's public key. `context` must be the
 * same string the harness passes to {@link openSealed}.
 */
export function seal(
  recipientPublicKey: string,
  plaintext: string | Uint8Array,
  context: string
): SealedEnvelope {
  const recipient = importPublicKey(recipientPublicKey)
  const eph = generateKeyPairSync('x25519')
  const epk = rawPublicKey(eph.publicKey)
  const shared = diffieHellman({
    privateKey: eph.privateKey,
    publicKey: recipient,
  })
  const key = deriveKey(shared, epk, recipientPublicKey, context)
  const iv = randomBytes(12)
  const cipher = createCipheriv('aes-256-gcm', key, iv)
  cipher.setAAD(Buffer.from(context, 'utf8'))
  const data =
    typeof plaintext === 'string' ? Buffer.from(plaintext, 'utf8') : plaintext
  const ct = Buffer.concat([cipher.update(data), cipher.final()])
  return {
    v: 1,
    alg: SEALED_ALG,
    epk,
    iv: iv.toString('base64url'),
    ct: ct.toString('base64url'),
    tag: cipher.getAuthTag().toString('base64url'),
  }
}

/**
 * Open an envelope with the harness's key pair. Throws when the
 * envelope is malformed, was sealed to another key or another
 * `context`, or was tampered with.
 */
export function openSealed(
  keyPair: SealingKeyPair,
  envelope: SealedEnvelope,
  context: string
): Buffer {
  const env = sealedEnvelope(envelope, 'sealed')
  const shared = diffieHellman({
    privateKey: keyPair.privateKey,
    publicKey: importPublicKey(env.epk),
  })
  const key = deriveKey(shared, env.epk, keyPair.publicKey, context)
  const decipher = createDecipheriv(
    'aes-256-gcm',
    key,
    Buffer.from(env.iv, 'base64url')
  )
  decipher.setAAD(Buffer.from(context, 'utf8'))
  decipher.setAuthTag(Buffer.from(env.tag, 'base64url'))
  return Buffer.concat([
    decipher.update(Buffer.from(env.ct, 'base64url')),
    decipher.final(),
  ])
}

/** The `context` for MCP credentials in a given session. */
export function mcpCredentialsContext(sessionId: string): string {
  return `mcp-credentials:${sessionId}`
}
