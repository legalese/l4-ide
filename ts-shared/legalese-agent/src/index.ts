/**
 * @repo/legalese-agent — the Legalese AI agent core, free of `vscode`.
 *
 * The same harness runs in the VS Code extension host and headless in
 * a cloud session; hosts supply the ports in `ports.ts`.
 */

// Ports
export * from './ports.js'

// Agent loop and events
export * from './chat-service.js'
export * from './events.js'
export * from './context-messages.js'

// ai-proxy
export * from './ai-proxy-client.js'

// Tools
export * from './tool-dispatcher.js'
export * from './tool-registry.js'
export * from './permissions.js'
export * from './pending-interactions.js'
export * from './mcp-client.js'
export * from './tools/builtin-tools.js'
export * from './tools/directive-snapshot.js'
export * from './tools/fs.js'
export * from './tools/l4-evaluate.js'
export * from './tools/lsp.js'
export * from './tools/refactor.js'
export * from './tools/ask-user.js'

// Persistence
export * from './conversation-store.js'

// Utilities
export * from './text-positions.js'
