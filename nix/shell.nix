{
  pkgs ? import <nixpkgs> { },
  ...
}:
pkgs.mkShell {
  buildInputs = [
    pkgs.haskell.compiler.ghc910
    pkgs.cabal-install
    pkgs.ghciwatch
    pkgs.zlib
    pkgs.xz
    pkgs.pkg-config
    pkgs.nodejs
    pkgs.typescript
    pkgs.nodePackages.prettier
    pkgs.graphviz
    pkgs.xdot
  ];
}
