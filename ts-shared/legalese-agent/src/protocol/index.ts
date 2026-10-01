/**
 * @repo/legalese-agent/protocol — the cloud-session wire and file
 * contracts shared by the cloud harness, the VS Code extension and
 * (mirrored) the Sessions API: spec §4.2, §6, §7.1, §8, §15.5.
 *
 * Types plus hand-written runtime validators (`Check<T>` functions that
 * return a clean copy or throw `ProtocolError`), and the sealed-secret
 * envelope with seal / open helpers.
 */
export * from './validate.js'
export * from './common.js'
export * from './files.js'
export * from './events.js'
export * from './commands.js'
export * from './api.js'
export * from './sealed.js'
