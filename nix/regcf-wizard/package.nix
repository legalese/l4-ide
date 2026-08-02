{
  base-path ? "/regcf",
  service-url ? "http://localhost:8080",
  deployment ? "regcf",
  buildNpmPackage,
  importNpmLock,
  lib,
  ...
}:
# The Reg CF citizen wizard (Track C, C2b/C2c), built as a static SPA.
#
# Two build-time inputs and they MUST agree with each other:
#   * `service-url`  -> VITE_JL4_BASE_URL, the origin+path of the jl4-service;
#   * the CSP `connect-src` list in ts-apps/regcf-wizard/svelte.config.js.
# When the wizard and the service are served from the SAME host — which is the
# arrangement in nix/configuration.nix — `connect-src 'self'` already covers it
# and no CSP edit is needed. A cross-origin service needs its exact
# scheme+host+port added to that list, or the browser blocks the fetch with only
# a console error and the spinner hangs forever.
#
# `base-path` is baked in at build time (SvelteKit `kit.paths.base`), so the
# nginx location and this value must match.
buildNpmPackage rec {
  pname = "regcf-wizard";
  version = "0-latest";
  src = lib.cleanSourceWith {
    src = ../../.;
    filter =
      path: type:
      let
        relPath = lib.removePrefix (toString ../../. + "/") (toString path);
        baseName = baseNameOf (toString path);
      in
      type == "directory"
      || lib.hasPrefix "ts-apps" relPath
      || lib.hasPrefix "ts-shared" relPath
      || baseName == "package.json"
      || baseName == "package-lock.json";
  };
  npmDeps = importNpmLock { npmRoot = src; };
  npmWorkspace = src;
  buildPhase = ''
    runHook preBuild
    export BASE_PATH=${base-path}
    export VITE_JL4_BASE_URL=${service-url}
    export VITE_JL4_DEPLOYMENT=${deployment}

    # Workspace deps, built by hand in dependency order: npm is not clever
    # enough to figure workspace dependencies out (same HACK as nix/jl4-web).
    # The chain regcf-wizard needs is narrower than jl4-web's:
    #   viz-expr -> boolean-analysis -> ladder-core -> ladder-svg
    #   viz-expr -> jl4-client-rpc
    pushd ./ts-shared
    pushd ./viz-expr && npm run build && popd
    pushd ./boolean-analysis && npm run build && popd
    pushd ./jl4-client-rpc && npm run build && popd
    pushd ./ladder-core && npm run build && popd
    pushd ./ladder-svg && npm run build && popd
    popd

    pushd ./ts-apps/regcf-wizard
    npm run build
    popd
    runHook postBuild
  '';
  installPhase = ''
    mv ts-apps/regcf-wizard/build $out
  '';
  npmConfigHook = importNpmLock.npmConfigHook;
}
