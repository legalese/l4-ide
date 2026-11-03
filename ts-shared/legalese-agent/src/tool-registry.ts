import type { AiTool } from './ports.js'

/**
 * OpenAI function-tool declarations for the built-in client-side
 * tools. These ship to the AI service in the `tools` field of the chat
 * request; the AI service passes them through to the provider and streams
 * back tool_call deltas when the model invokes one.
 *
 * Names use `category__name` with a double-underscore separator so a
 * prefix split gives the dispatcher the right category. Third-party
 * MCP tools later namespace as `{serverId}__{toolName}` and land in
 * the same switch.
 */
export const BUILTIN_TOOLS: AiTool[] = [
  {
    type: 'function',
    function: {
      name: 'fs__read_file',
      description:
        'Read a file or list a directory, one line per entry. Response prefixed with `[<path> <start>-<end>/<total>]` (or `[<path> keywords="…" matches=N chunks=K/M]` with `search_keywords`); when `<end> < <total>` more lines remain — call again with `startLine=<end>+1`. Capped at 500 lines and 4000 chars per call; naming an `endLine` raises the character cap to 24000, so ask for the range you want. Directories: `name/` for subdirs, directories first. `.git`, `node_modules`, `.DS_Store` hidden.',
      parameters: {
        type: 'object',
        additionalProperties: false,
        properties: {
          path: {
            type: 'string',
            description: 'Workspace path. Use `.` for the workspace root.',
          },
          startLine: { type: 'number', description: '1-based, default 1.' },
          endLine: {
            type: 'number',
            description: '1-based inclusive, default startLine+499.',
          },
          search_keywords: {
            type: 'string',
            description:
              'One or more keywords separated by whitespace; a line is a hit if it matches ANY of them (OR). Each keyword is a case-insensitive regex with literal-substring fallback. For files, matches carry 2 lines of context (hits prefixed `>>>`, context `   `, chunks joined `---`). For directories, the tree is walked recursively and both file and folder NAMES and file CONTENTS are searched, so use this on `.` to find a file: header `[<dir>/ keywords="…" names=N matches=M files=K]`, then name hits as `<path>` rows (folders end in `/`), then content hits as `<path>:<lineno>: <text>` rows. Files over 1 MB are matched by name only, counted as `over1MB=N` in the header. Build output (`dist`, `.turbo` and the like) is left out unless the search starts inside it. Paths can be passed straight back to this tool.',
          },
        },
        required: ['path'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'fs__create_file',
      description:
        'Create a file. Pass `content` with the initial text. If the name is taken, the text goes to the first free `-N` name (`foo.l4` becomes `foo-1.l4`) and the existing file stays as it was: read the result, because it names the file that was really written. Without `content` the file gets a seed line to replace with fs__edit_file, and an existing name is an error. For a large file, create it with a first part and add the rest with fs__edit_file, so a mistake is caught early.',
      parameters: {
        type: 'object',
        additionalProperties: false,
        properties: {
          path: { type: 'string', description: 'Workspace path.' },
          content: {
            type: 'string',
            description: 'Initial text of the file.',
          },
        },
        required: ['path'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'fs__edit_file',
      description:
        'String-anchored find/replace. Without `startLine`, `old` must appear in the file EXACTLY ONCE — include surrounding context lines if the natural snippet repeats. With `startLine`, the first occurrence after that line is taken. **`old` must be a non-empty anchor; whole-file replacement is not supported.** Pass `edits` for up to 5 changes to one file in one call: they run in order, the file is checked after each, and the run stops at the first change that fails or leaves the file worse, so put definitions before the code that uses them. The result lists what was applied. **Prefer smaller edits.** A huge `new` payload risks the model hitting max_tokens mid-stream, leaving the file untouched.',
      parameters: {
        type: 'object',
        additionalProperties: false,
        properties: {
          path: { type: 'string', description: 'Workspace path.' },
          edits: {
            type: 'array',
            maxItems: 5,
            description:
              'Several changes to this file, instead of `old`/`new`. Each `old` must match the file as the earlier changes left it.',
            items: {
              type: 'object',
              additionalProperties: false,
              properties: {
                old: { type: 'string' },
                new: { type: 'string' },
                startLine: { type: 'number' },
              },
              required: ['old', 'new'],
            },
          },
          old: {
            type: 'string',
            description:
              'Exact non-empty text to replace. Must be unique in the file unless `startLine` is set. Empty string is rejected — split big rewrites into multiple smaller fs__edit_file calls.',
          },
          new: {
            type: 'string',
            description:
              'Replacement text. Pass "" to delete the `old` snippet.',
          },
          startLine: {
            type: 'number',
            description:
              'Optional 1-based line to anchor the search — First occurrence of `old` strictly after this line. Leave some buffer (~5-10 lines)',
          },
        },
        required: ['path'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'fs__delete_file',
      description:
        'Delete a file. It stays recoverable, and the user may be asked to confirm.',
      parameters: {
        type: 'object',
        additionalProperties: false,
        properties: {
          path: { type: 'string', description: 'Workspace path.' },
        },
        required: ['path'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'fs__copy_file',
      description:
        'Copy a text file to another path in one step. `overwrite` replaces an existing file at `to`; `deleteSource` removes `from` afterwards, making it a move.',
      parameters: {
        type: 'object',
        additionalProperties: false,
        properties: {
          from: { type: 'string', description: 'Workspace path to copy.' },
          to: {
            type: 'string',
            description: 'Workspace path of the copy.',
          },
          overwrite: {
            type: 'boolean',
            description: 'Replace `to` if it exists. Default false.',
          },
          deleteSource: {
            type: 'boolean',
            description: 'Delete `from` after copying. Default false.',
          },
        },
        required: ['from', 'to'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'l4__refactor',
      description:
        "Apply a structured L4 refactor. The `action` discriminator selects the operation; more actions will be added over time. Today: `rename` substitutes an identifier across the file AND every file that IMPORTs it (driven by the LSP's references provider, so the file must currently type-check — use l4__evaluate first if unsure). Preserves backtick quoting per-occurrence: a source `\\`old name\\`` becomes `\\`new name\\``; if the new name contains spaces or punctuation it's wrapped in backticks everywhere automatically. Pass identifier names WITHOUT surrounding backticks. Prefer this tool over hand-rolling cross-file find/replace via fs__edit_file.",
      parameters: {
        type: 'object',
        additionalProperties: false,
        properties: {
          action: {
            type: 'string',
            enum: ['rename'],
            description:
              'Which refactor to apply. Supported: `rename` — substitute an identifier across the file and every importer. Reserved for future actions (extract, inline, …); pass exactly one of the listed enum values.',
          },
          path: {
            type: 'string',
            description:
              'Workspace path of any L4 file the action anchors on. For `rename`, this is a file containing the identifier (usually where it is DEFINED); the rename then propagates through all importers.',
          },
          oldName: {
            type: 'string',
            description:
              "Required when action='rename'. Current identifier (no surrounding backticks). Must appear in the source of `path`.",
          },
          newName: {
            type: 'string',
            description:
              "Required when action='rename'. New identifier (no surrounding backticks). May contain spaces/punctuation — backticks are added automatically where required.",
          },
        },
        required: ['action', 'path'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'l4__evaluate',
      description:
        'Type-check and run `#EVAL`/`#CHECK`/`#TRACE`. Returns errors if not clean, else directive results.',
      parameters: {
        type: 'object',
        additionalProperties: false,
        properties: {
          path: { type: 'string', description: 'Workspace path.' },
          timeoutMs: {
            type: 'number',
            description: 'Max compile wait ms (default 6000, cap 15000).',
          },
          mode: {
            type: 'string',
            enum: ['changed', 'full'],
            description:
              '`full` (default) prints every directive value. `changed` prints only directives added or whose value changed since the last l4__evaluate call; collapses to a single count line when nothing moved.',
          },
        },
        required: ['path'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'meta__ask_user',
      description:
        'Ask the user a clarifying question and wait for their reply. Use sparingly — only when the task is genuinely ambiguous and you cannot proceed without a decision.',
      parameters: {
        type: 'object',
        additionalProperties: false,
        properties: {
          question: {
            type: 'string',
            description: 'Concise question text.',
          },
          choices: {
            type: 'array',
            items: { type: 'string' },
            description: 'Optional fixed choices. Omit for free-form answers.',
          },
        },
        required: ['question'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'meta__post_status_update',
      description:
        'Stream a brief progress update to the user mid-turn. The text renders inline as plain assistant prose (not as a tool-call card). Use during long multi-step tasks (doc lookups, validation loops, multi-file drafting) Keep it under ~120 characters, present tense, no markdown headings. Do not repeat same status, and do not duplicate final answer.',
      parameters: {
        type: 'object',
        additionalProperties: false,
        properties: {
          text: {
            type: 'string',
            description:
              'Short user-facing status sentence. Plain prose. Will be appended to the assistant message as if written it inline.',
          },
        },
        required: ['text'],
      },
    },
  },
]
