{
  socket-url ? "localhost:5007",
  session-url ? "localhost:5008",
  secure ? false,
  buildNpmPackage,
  importNpmLock,
  pkg-config,
  libsecret,
  lib,
  fetchurl,
  ...
}:
let
  # The in-browser LSP the editor prefers (VITE_PREFER_WASM in
  # ts-apps/jl4-web/.env.production), as a release of main-tag.yml built it.
  # Bump the tag and both hashes after a release to keep it up to date; the
  # tag is also the cache key browsers keep the WASM under.
  wasm-release = "l4-ide-build-98";
  fetchWasm = name: hash: fetchurl {
    url = "https://github.com/legalese/l4-ide/releases/download/${wasm-release}/${name}";
    inherit hash;
  };
  jl4-core-wasm = fetchWasm "jl4-core.wasm" "sha256-IR6Y+A5eYUFtxHbfWoGQ1mi6YApmIvisaqAh1/dqZHU=";
  jl4-core-mjs = fetchWasm "jl4-core.mjs" "sha256-eeDBcTyysrsjtLvhOHMhynMp6QfcFR1/DqV54yIihuY=";
in
buildNpmPackage rec {
  pname = "jl4-web";
  version = "0-latest";
  src = lib.cleanSourceWith {
    src = ../../.;
    filter = path: type:
      let
        relPath = lib.removePrefix (toString ../../. + "/") (toString path);
        baseName = baseNameOf (toString path);
      in
        # Include all directories to maintain path structure for copy-examples.ts, while only copying specific files
        type == "directory" ||
        lib.hasPrefix "ts-apps" relPath ||
        lib.hasPrefix "ts-shared" relPath ||
        baseName == "package.json" ||
        baseName == "package-lock.json" ||
        lib.hasPrefix "jl4/examples/legal" relPath;
  };
  npmDeps = importNpmLock { npmRoot = src; };
  npmWorkspace = src;
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ libsecret.dev ];
  buildPhase = ''
    runHook preBuild
    set -x
    export VITE_SOCKET_URL=${if secure then "wss" else "ws"}://${socket-url};
    export VITE_SESSION_URL=${if secure then "https" else "http"}://${session-url};
    export VITE_WASM_VERSION=${wasm-release};
    mkdir -p ./ts-apps/jl4-web/static/wasm
    cp ${jl4-core-wasm} ./ts-apps/jl4-web/static/wasm/jl4-core.wasm
    cp ${jl4-core-mjs} ./ts-apps/jl4-web/static/wasm/jl4-core.mjs

    pushd ./ts-shared

    pushd ./type-utils
    npm run build
    popd

    pushd ./viz-expr
    npm run build
    popd

    pushd ./boolean-analysis
    npm run build
    popd

    pushd ./jl4-client-rpc
    npm run build
    popd

    pushd ./l4-highlight
    npm run build
    popd

    pushd ./layout-ir
    npm run build
    popd

    pushd ./l4-ladder-visualizer
    npm run build
    popd

    popd

    pushd ./ts-apps

    pushd ./webview
    npm run build
    popd

    # HACK: we need to build workspace dependencies by hand because npm
    # isn't clever enough to figure out workspace dependencies

    pushd ./jl4-web
    npm run build
    set +x
    runHook postBuild
  '';
  installPhase = ''
    mv build $out
  '';
  npmConfigHook = importNpmLock.npmConfigHook;
}
