{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.services.jl4-lsp = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "run the websocket jl4-lsp; the web editor runs the LSP in the browser from WASM and only falls back to this server";
    };
    path = lib.mkOption {
      type = lib.types.str;
      default = "/lsp";
      description = "path relative to the domain the lsp will answer on";
    };
    port = lib.mkOption {
      type = lib.types.int;
      default = 8000;
      description = "port of localhost to run the websocket server of the jl4-lsp on";
    };
  };

  config.services.nginx.virtualHosts.${config.networking.domain}.locations = lib.mkIf config.services.jl4-lsp.enable {
    ${config.services.jl4-lsp.path} = {
      proxyPass = "http://localhost:${toString config.services.jl4-lsp.port}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };

  config.systemd.services.jl4-lsp = lib.mkIf config.services.jl4-lsp.enable {
    enable = true;
    description = "jl4-lsp";
    after = [ "network.target" "nginx.service" ];
    requires = [ "nginx.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = ''
        ${pkgs.callPackage ./package.nix { }}/bin/jl4-lsp ws \
          --host "::" \
          --port ${toString config.services.jl4-lsp.port} \
          --cwd ${../../jl4-core/libraries}
      '';
      Restart = "always";

      # Security
      DynamicUser = true;
      NoNewPrivileges = true;
      # Sandboxing
      ProtectSystem = "full";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      PrivateUsers = true;
      ProtectHostname = true;
      ProtectClock = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [ "AF_UNIX AF_INET AF_INET6" ];
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      PrivateMounts = true;
    };
  };
}
