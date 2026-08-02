{
  pkgs ? import <nixpkgs> { },
  ...
}:
{
  jl4-web = pkgs.callPackage ./jl4-web/package.nix { };
  regcf-wizard = pkgs.callPackage ./regcf-wizard/package.nix { };
  jl4-lsp = pkgs.callPackage ./jl4-lsp/package.nix { };
  jl4-service = pkgs.callPackage ./jl4-service/package.nix { };
  jl4-websessions = pkgs.callPackage ./jl4-websessions/package.nix { };
  fibo-sparql = pkgs.callPackage ./fibo-sparql/package.nix { };
}
