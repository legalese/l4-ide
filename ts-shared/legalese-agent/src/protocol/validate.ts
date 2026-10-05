/**
 * Tiny hand-written runtime validators (the repo has no zod). A
 * `Check<T>` either returns a clean `T` or throws a {@link ProtocolError}
 * naming the offending path.
 *
 * Objects come back as fresh objects holding only the declared keys, so
 * unknown fields from a hostile or newer peer never flow further (and
 * `__proto__` can't be smuggled in).
 */

export class ProtocolError extends Error {
  constructor(
    message: string,
    readonly path: string
  ) {
    super(path ? `${path}: ${message}` : message)
    this.name = 'ProtocolError'
  }
}

export type Check<T> = (value: unknown, path: string) => T

/** Marks an object field as optional. */
export interface Optional<T> {
  readonly optional: Check<T>
}

export type Shape = Record<string, Check<unknown> | Optional<unknown>>

type RequiredKeys<S extends Shape> = {
  [K in keyof S]: S[K] extends Optional<unknown> ? never : K
}[keyof S]
type OptionalKeys<S extends Shape> = {
  [K in keyof S]: S[K] extends Optional<unknown> ? K : never
}[keyof S]

export type Infer<S extends Shape> = {
  [K in RequiredKeys<S>]: S[K] extends Check<infer T> ? T : never
} & {
  [K in OptionalKeys<S>]?: S[K] extends Optional<infer T> ? T : never
}

/** Parse, or return a result instead of throwing. */
export function tryParse<T>(
  check: Check<T>,
  value: unknown
): { ok: true; value: T } | { ok: false; error: string } {
  try {
    return { ok: true, value: check(value, '') }
  } catch (err) {
    if (err instanceof ProtocolError) return { ok: false, error: err.message }
    throw err
  }
}

function fail(path: string, message: string): never {
  throw new ProtocolError(message, path)
}

export function str(
  opts: { max?: number; min?: number; pattern?: RegExp } = {}
): Check<string> {
  const max = opts.max ?? 1_000_000
  const min = opts.min ?? 0
  return (v, path) => {
    if (typeof v !== 'string') fail(path, 'expected a string')
    if (v.length < min) fail(path, `shorter than ${min}`)
    if (v.length > max) fail(path, `longer than ${max}`)
    if (opts.pattern && !opts.pattern.test(v))
      fail(path, 'has an invalid format')
    return v
  }
}

export function int(opts: { min?: number; max?: number } = {}): Check<number> {
  const min = opts.min ?? 0
  const max = opts.max ?? Number.MAX_SAFE_INTEGER
  return (v, path) => {
    if (typeof v !== 'number' || !Number.isSafeInteger(v)) {
      fail(path, 'expected an integer')
    }
    if (v < min || v > max) fail(path, `out of range ${min}..${max}`)
    return v
  }
}

export function num(): Check<number> {
  return (v, path) => {
    if (typeof v !== 'number' || !Number.isFinite(v)) {
      fail(path, 'expected a number')
    }
    return v
  }
}

export function bool(): Check<boolean> {
  return (v, path) => {
    if (typeof v !== 'boolean') fail(path, 'expected a boolean')
    return v
  }
}

export function literal<T extends string | number | boolean | null>(
  ...values: readonly T[]
): Check<T> {
  return (v, path) => {
    if (!values.includes(v as T)) {
      fail(
        path,
        `expected one of ${values.map((x) => JSON.stringify(x)).join(', ')}`
      )
    }
    return v as T
  }
}

/** Any JSON value, passed through as-is (deep-copied via JSON). */
export function json(opts: { maxBytes?: number } = {}): Check<unknown> {
  const max = opts.maxBytes ?? 1_000_000
  return (v, path) => {
    let text: string | undefined
    try {
      text = JSON.stringify(v)
    } catch {
      fail(path, 'is not JSON-serialisable')
    }
    if (text === undefined) return undefined
    if (text.length > max) fail(path, `larger than ${max} bytes`)
    return JSON.parse(text) as unknown
  }
}

export function arr<T>(
  item: Check<T>,
  opts: { max?: number } = {}
): Check<T[]> {
  const max = opts.max ?? 10_000
  return (v, path) => {
    if (!Array.isArray(v)) fail(path, 'expected an array')
    if (v.length > max) fail(path, `more than ${max} items`)
    return v.map((x, i) => item(x, `${path}[${i}]`))
  }
}

/** A string → string map with bounded keys and values. */
export function stringMap(
  opts: { maxEntries?: number; key?: Check<string>; value?: Check<string> } = {}
): Check<Record<string, string>> {
  const key = opts.key ?? str({ min: 1, max: 256 })
  const value = opts.value ?? str({ max: 16_384 })
  const maxEntries = opts.maxEntries ?? 64
  return (v, path) => {
    if (!isPlainObject(v)) fail(path, 'expected an object')
    const entries = Object.entries(v)
    if (entries.length > maxEntries)
      fail(path, `more than ${maxEntries} entries`)
    const out: Record<string, string> = Object.create(null) as Record<
      string,
      string
    >
    for (const [k, val] of entries) {
      key(k, `${path}{key}`)
      out[k] = value(val, `${path}.${k}`)
    }
    return { ...out }
  }
}

export function optional<T>(check: Check<T>): Optional<T> {
  return { optional: check }
}

function isOptional(
  c: Check<unknown> | Optional<unknown>
): c is Optional<unknown> {
  return typeof c === 'object' && c !== null && 'optional' in c
}

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v)
}

/** An object with exactly the declared keys in the output. `undefined`
 *  and absent optional fields are both omitted. */
export function obj<S extends Shape>(shape: S): Check<Infer<S>> {
  return (v, path) => {
    if (!isPlainObject(v)) fail(path, 'expected an object')
    const out: Record<string, unknown> = {}
    for (const [key, c] of Object.entries(shape)) {
      const sub = path ? `${path}.${key}` : key
      const raw = Object.prototype.hasOwnProperty.call(v, key)
        ? v[key]
        : undefined
      if (isOptional(c)) {
        if (raw === undefined || raw === null) continue
        out[key] = c.optional(raw, sub)
      } else {
        out[key] = c(raw, sub)
      }
    }
    return out as Infer<S>
  }
}

/**
 * A discriminated union on `tag`. Each variant's check sees the whole
 * object and should include the tag as a literal.
 */
export function union<T>(
  tag: string,
  variants: Record<string, Check<T>>
): Check<T> {
  return (v, path) => {
    if (!isPlainObject(v)) fail(path, 'expected an object')
    const t = v[tag]
    if (
      typeof t !== 'string' ||
      !Object.prototype.hasOwnProperty.call(variants, t)
    ) {
      fail(path ? `${path}.${tag}` : tag, `unknown ${tag} ${JSON.stringify(t)}`)
    }
    return variants[t]!(v, path)
  }
}

/** Combine two object checks (e.g. an envelope and a payload). */
export function both<A extends object, B extends object>(
  a: Check<A>,
  b: Check<B>
): Check<A & B> {
  return (v, path) => ({ ...a(v, path), ...b(v, path) })
}
