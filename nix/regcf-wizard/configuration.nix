{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.services.regcf-wizard = {
    enable = lib.mkEnableOption "the Regulation Crowdfunding citizen wizard";
    path = lib.mkOption {
      type = lib.types.str;
      default = "/regcf/";
      description = ''
        Path, relative to the domain, at which the wizard SPA is served.
        `nix/jl4-web` already owns "/" (the IDE), so the wizard takes a
        sub-path. This value is baked into the BUILD (SvelteKit
        `kit.paths.base`), so changing it here rebuilds the app.
      '';
    };
    deployment = lib.mkOption {
      type = lib.types.str;
      default = "regcf";
      description = "jl4-service deployment id the wizard talks to.";
    };
  };

  config = lib.mkIf config.services.regcf-wizard.enable {
    # The corpus the wizard asks. It is contributed HERE, under the same `mkIf`
    # as the page, and deliberately NOT in `jl4-service`'s bundle defaults: a
    # bundle in that default is pre-seeded by EVERY host that imports
    # `nix/configuration.nix` — which includes production, `jl4.legalese.com` —
    # so the corpus would have gone public on the next unrelated
    # `nixos-rebuild switch`, with nobody having enabled the wizard. Keeping it
    # here is what makes `enable = true` the single act that publishes anything.
    #
    # Copying the WHOLE directory is safe, and is what the pre-seed script does:
    # the loader takes the two .l4 files and ignores `figures/`, `tests/`,
    # `README.md` and `PROJECTIONS.md`. Verified by replicating that script
    # against a loopback service, which reported `exportCount: 6` from
    # `regcf-wizard.l4` and `ready:1, total:1`.
    services.jl4-service.bundles.regcf = ../../jl4/examples/legal/regcf;

    services.nginx.virtualHosts.${config.networking.domain}.locations = {
      ${config.services.regcf-wizard.path} = {
        alias =
          "${
            pkgs.callPackage ./package.nix {
              # `paths.base` must carry no trailing slash; the nginx location must.
              base-path = lib.removeSuffix "/" config.services.regcf-wizard.path;
              # Same-origin with the service, so the app's CSP `connect-src 'self'`
              # already covers it and no CSP edit is needed to deploy.
              service-url = "https://${config.networking.domain}${
                lib.removeSuffix "/" config.services.jl4-service.path
              }";
              deployment = config.services.regcf-wizard.deployment;
            }
          }/";
        # A prerendered SPA: real files first, then the SvelteKit fallback shell,
        # so a deep link or a reload does not 404.
        tryFiles = "$uri $uri/index.html ${config.services.regcf-wizard.path}404.html";
      };
    };
  };
}
