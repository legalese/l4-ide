# jl4-wasm

WASM module for running L4 language features in the browser.

This package produces a standalone WebAssembly binary that can be loaded in any
browser or Node.js environment, enabling L4 language features without a server.

## Prerequisites

Install the GHC WASM toolchain (takes ~30 minutes):

```bash
# Note: Use -L to follow redirects
curl -L https://gitlab.haskell.org/haskell-wasm/ghc-wasm-meta/-/raw/master/bootstrap.sh | FLAVOUR=9.10 bash
```

Then source the environment before any WASM commands:

```bash
source ~/.ghc-wasm/env
```

## Building

### Using the Build Script (Recommended)

```bash
# From jl4-wasm directory
cd jl4-wasm

# Build only
./scripts/build-wasm.sh

# Build and optimize (reduces ~42 MB to ~10 MB)
./scripts/build-wasm.sh --optimize

# Build, optimize, and run tests
./scripts/build-wasm.sh --all
```

The script handles:

1. Sourcing the GHC WASM environment
2. Building with `wasm32-wasi-cabal`
3. Generating JS FFI glue code
4. Deploying to `ts-apps/jl4-web/static/wasm/`
5. Optionally optimizing with `wasm-opt`
6. Optionally running integration tests

### Manual Build

If you prefer to run the commands manually:

```bash
# From project root
source ~/.ghc-wasm/env

# Build jl4-wasm (this also builds jl4-core as a dependency)
wasm32-wasi-cabal build jl4-wasm --project-file=cabal-wasm.project

# Generate JS FFI glue code
$(wasm32-wasi-ghc --print-libdir)/post-link.mjs \
  -i dist-newstyle/build/wasm32-wasi/ghc-*/jl4-wasm-*/x/jl4-wasm/opt/build/jl4-wasm/jl4-wasm.wasm \
  -o dist-newstyle/jl4-wasm.mjs

# Copy to web app static assets
mkdir -p ts-apps/jl4-web/static/wasm
cp dist-newstyle/build/wasm32-wasi/ghc-*/jl4-wasm-*/x/jl4-wasm/opt/build/jl4-wasm/jl4-wasm.wasm \
   ts-apps/jl4-web/static/wasm/jl4-core.wasm
cp dist-newstyle/jl4-wasm.mjs ts-apps/jl4-web/static/wasm/jl4-core.mjs
```

The build produces:

- `jl4-wasm.wasm` (~42 MB unoptimized) - The WebAssembly binary
- `jl4-wasm.mjs` (~5 KB) - JavaScript FFI glue code

### Optimizing the Binary

The raw WASM binary is large (~42 MB) but can be significantly reduced using `wasm-opt`:

```bash
# Install binaryen (provides wasm-opt)
# macOS: brew install binaryen
# Ubuntu: sudo apt install binaryen

# Option 1: Use the build script with --optimize
./scripts/build-wasm.sh --optimize

# Option 2: Run optimization separately (after building)
./scripts/optimize-wasm.sh -Oz --test
```

Optimization results:

| Level       | Size  | Reduction | Notes                                      |
| ----------- | ----- | --------- | ------------------------------------------ |
| Unoptimized | 42 MB | -         | Raw GHC output                             |
| `-Os`       | 22 MB | 47%       | Size-optimized                             |
| `-Oz`       | 10 MB | 76%       | Aggressive size optimization (recommended) |

The `-Oz` level reduces the binary from 42 MB to ~10 MB. With HTTP compression (gzip/brotli), the transfer size is typically 3-4 MB.

## Exported Functions

The following functions are exported via GHC's JavaScript FFI:

| Function               | Signature                                                        | Description                                    |
| ---------------------- | ---------------------------------------------------------------- | ---------------------------------------------- |
| `l4_check`             | `(source: string) => Promise<string>`                            | Parse and type-check, returns JSON diagnostics |
| `l4_hover`             | `(source: string, line: number, col: number) => Promise<string>` | Get hover info at position                     |
| `l4_completions`       | `(source: string, line: number, col: number) => Promise<string>` | Get completion suggestions                     |
| `l4_semantic_tokens`   | `(source: string) => Promise<string>`                            | Get semantic tokens for highlighting           |
| `l4_eval`              | `(source: string) => Promise<string>`                            | Evaluate #EVAL directives                      |
| `l4_set_files`         | `(filesJson: string) => Promise<string>`                         | Supply the files a document can import         |
| `l4_set_document_path` | `(path: string) => Promise<string>`                              | Say where the document lives among those files |

All functions return JSON-encoded results as strings.

The table is not the whole list: `l4_eval_directive`, `l4_visualize_by_name`, `l4_state_graph_by_name`, `l4_code_lenses`, `l4_definition`, `l4_references` and `l4_query_plan` are exported too.
`ts-apps/jl4-web/src/lib/wasm/wasm-bridge.ts` types all of them.

### Files a document can import

`IMPORT` is resolved among the standard library built into the module and the files the host hands it:

- `l4_set_files('{"rows/b/mod.l4": "..."}')` replaces the files, as one JSON object from path to source text.
  It answers `{"files": n}`, or `{"error": "..."}` and changes nothing when the text is not an object of strings, or when a key is refused.
  A key is a path from the top of the files (found by a path import such as ``IMPORT `../b/mod` ``) or a module name (found by `IMPORT mod`), with or without `.l4`, and it has no leading `/`.
  A key with a leading `/`, such as `/rows/b/mod.l4`, is refused, because no import could find it; write `rows/b/mod.l4`.
  A table in which two keys are one path (`core.l4` and `./core.l4`, or `core` and `core.l4`) is refused too, and the message names both keys.
  A key that appears twice in the JSON text is taken once, with the value of the first (measured with the `aeson` this tree pins); `JSON.stringify` never writes one.
- `l4_set_document_path('rows/a/main.l4')` says where the document being analysed lives among them, so that a path import in it starts from `rows/a`.
  The empty string puts it back at the top of the files, where it is until this is called.
  The path is read as written, with `/` as the only separator and a leading `/` ignored: `rows/a/` makes the document the file `rows/a.l4`, a `\` is part of a file's name and not a separator, a path that climbs above the top of the files is accepted and then every path import from the document is refused, and the reply repeats the text it was given and not the path it came to.

Both are kept by the module until they are replaced, and every function that resolves imports reads them when it starts.
The files change when the project does, and the source changes at every keystroke, so only the source is an argument.
The module holds one context and analyses one document at a time: a call that has been issued runs under the path that is set when it starts, so a host must let an analysis finish before it changes the path, and sending the path again between two calls that are both in flight does not separate them.
Before anything is set, the module has no files and the document at the top, as it had before these existed, and answers as it did, with two exceptions.
An imported library that uses its own imports now evaluates, where `l4_eval` and `l4_eval_directive` said it was not in scope (measured on 193 corpus files with no files set: 10 differed, and every difference was of this kind).
A document that imports a module with a type error now carries an error saying so, and is not evaluated.

[How a path import is resolved in the browser](../doc/reference/libraries/resolution.md#in-the-browser) says what is reachable and what is refused.

## Usage from JavaScript

GHC WASM uses a two-phase loading process:

````javascript
// 1. Load the JS FFI glue code
const jsModule = await import("./jl4-core.mjs");
const generateImports = jsModule.default;

// 2. Load and compile the WASM module
const wasmBuffer = await fetch("./jl4-core.wasm").then((r) => r.arrayBuffer());
const wasmModule = await WebAssembly.compile(wasmBuffer);

// 3. Create exports proxy (needed for FFI callbacks)
const exportsProxy = {};
const jsFFIImports = generateImports(exportsProxy);

// 4. WASI imports (minimal stubs for reactor mode)
const wasiImports = {
  clock_time_get: (_clockId, _precision, out) => {
    const view = new DataView(exportsProxy.memory.buffer);
    view.setBigUint64(out, BigInt(Date.now()) * BigInt(1_000_000), true);
    return 0;
  },
  fd_write: () => 0,
  fd_read: () => 0,
  fd_close: () => 0,
  fd_seek: () => 0,
  fd_fdstat_get: () => 0,
  fd_fdstat_set_flags: () => 0,
  fd_filestat_get: () => 0,
  fd_filestat_set_size: () => 0,
  fd_prestat_get: () => 8, // EBADF
  fd_prestat_dir_name: () => 8,
  path_create_directory: () => 63, // ENOSYS
  path_filestat_get: () => 63,
  path_open: () => 63,
  poll_oneoff: () => 0,
  proc_exit: (code) => console.warn("proc_exit:", code),
  args_sizes_get: (argc, argvBufSize) => {
    const view = new DataView(exportsProxy.memory.buffer);
    view.setUint32(argc, 0, true);
    view.setUint32(argvBufSize, 0, true);
    return 0;
  },
  args_get: () => 0,
  environ_sizes_get: (environc, environBufSize) => {
    const view = new DataView(exportsProxy.memory.buffer);
    view.setUint32(environc, 0, true);
    view.setUint32(environBufSize, 0, true);
    return 0;
  },
  environ_get: () => 0,
};

// 5. Instantiate with all imports
const instance = await WebAssembly.instantiate(wasmModule, {
  wasi_snapshot_preview1: wasiImports,
  ghc_wasm_jsffi: jsFFIImports,
});

// 6. Copy exports to proxy (required for FFI callbacks to work)
Object.assign(exportsProxy, instance.exports);

// 7. Initialize the WASI reactor (Haskell RTS)
instance.exports._initialize();

// 8. Now you can call L4 functions!
const diagnostics = await instance.exports.l4_check("DECIDE x IS 1 + 2");
console.log(JSON.parse(diagnostics)); // []

const hover = await instance.exports.l4_hover("DECIDE x IS 42", 0, 7);
console.log(JSON.parse(hover)); // { contents: { kind: "markdown", value: "```\nNUMBER\n```" }, ... }
````

## Testing

### Browser Test Page

A test page is available when running the web app:

```bash
cd ts-apps/jl4-web && npm run dev
# Open http://localhost:5173/wasm-test.html
```

### Node.js Test

```bash
source ~/.ghc-wasm/env
cd ts-apps/jl4-web/static/wasm

# Use the GHC WASM Node.js (has all required features)
~/.ghc-wasm/nodejs/bin/node -e "
const fs = require('fs');

async function main() {
  const jsModule = await import('./jl4-core.mjs');
  const generateImports = jsModule.default;

  const wasmBuffer = fs.readFileSync('./jl4-core.wasm');
  const wasmModule = await WebAssembly.compile(wasmBuffer);

  const exportsProxy = {};
  const jsFFIImports = generateImports(exportsProxy);

  // ... (WASI imports as above) ...

  const instance = await WebAssembly.instantiate(wasmModule, {
    wasi_snapshot_preview1: wasiImports,
    ghc_wasm_jsffi: jsFFIImports,
  });

  Object.assign(exportsProxy, instance.exports);
  instance.exports._initialize();

  const result = await instance.exports.l4_check('DECIDE x IS 42');
  console.log('Diagnostics:', result); // []
}

main();
"
```

## Architecture

This package is a thin wrapper that:

1. Re-exports `L4.API` from `jl4-core`
2. Provides a `Main.hs` that references the API (reactor mode has no main)
3. Configures the build for WASI reactor mode

The actual implementation is in `jl4-core/src/L4/API.hs`, which:

- Provides pure Haskell functions for all L4 features
- Exports JavaScript FFI wrappers when compiled for `wasm32` architecture
- Uses `foreign export javascript` syntax from GHC's JS FFI

## File Sizes

| File          | Unoptimized | Optimized (-Oz) | Compressed     |
| ------------- | ----------- | --------------- | -------------- |
| jl4-core.wasm | ~42 MB      | ~10 MB          | ~3-4 MB (gzip) |
| jl4-core.mjs  | ~5 KB       | ~5 KB           | ~2 KB (gzip)   |

The CI pipeline automatically runs `wasm-opt -Oz` on all builds. For local development,
run `./scripts/optimize-wasm.sh -Oz` after building.

## Related Documentation

- [GHC WASM User Guide](https://ghc.gitlab.haskell.org/ghc/doc/users_guide/wasm.html)
- [GHC WASM Meta](https://gitlab.haskell.org/haskell-wasm/ghc-wasm-meta) - Toolchain bootstrap
- [TypeScript Bridge](../ts-apps/jl4-web/src/lib/wasm/README.md) - Browser integration
