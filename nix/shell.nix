{
  pkgs ? import <nixpkgs> { },
  ...
}:
let
  # Use a static-friendly GHC setup
  haskellPackages = pkgs.haskell.packages.ghc96.override {
    overrides = self: super: {
      # Enable more static-friendly compilation for some base packages
    };
  };
in
pkgs.mkShell {
  buildInputs = [
    haskellPackages.ghc
    haskellPackages.haskell-language-server
    pkgs.cabal-install
    pkgs.ghciwatch
    pkgs.zlib
    pkgs.xz
    pkgs.pkg-config
    pkgs.nodejs
    pkgs.typescript
    pkgs.nixos-anywhere
    pkgs.sqlite
    pkgs.upx
    pkgs.nodePackages.prettier
    
    # Static libraries
    pkgs.glibc.static  
    pkgs.gmp6.dev
    pkgs.libffi.dev
    pkgs.zlib.dev
    pkgs.ncurses.dev
    
    # Additional tools for static linking
    pkgs.binutils
    pkgs.gcc
  ];
  
  shellHook = ''
    # Configure for static linking
    export NIX_LDFLAGS="$NIX_LDFLAGS -L${pkgs.glibc.static}/lib"
    export NIX_LDFLAGS="$NIX_LDFLAGS -L${pkgs.gmp6}/lib"
    export NIX_LDFLAGS="$NIX_LDFLAGS -L${pkgs.libffi}/lib"  
    export NIX_LDFLAGS="$NIX_LDFLAGS -L${pkgs.zlib}/lib"
    export NIX_LDFLAGS="$NIX_LDFLAGS -L${pkgs.ncurses}/lib"
    
    # Include paths
    export NIX_CPPFLAGS="$NIX_CPPFLAGS -I${pkgs.gmp6.dev}/include"
    export NIX_CPPFLAGS="$NIX_CPPFLAGS -I${pkgs.libffi.dev}/include"
    
    # Use GNU ld instead of gold for better static support  
    export NIX_LDFLAGS="$NIX_LDFLAGS -fuse-ld=bfd"
    
    # Static linking environment
    export LDFLAGS="$LDFLAGS -static -pthread"
    
    echo "Static linking environment ready"
    echo "Libraries available:"
    echo "  GMP: ${pkgs.gmp6}/lib"
    echo "  LibFFI: ${pkgs.libffi}/lib" 
    echo "  Glibc static: ${pkgs.glibc.static}/lib"
    echo ""
    echo "For static linking, try:"
    echo "  nix develop -c cabal build all"
    echo "  or disable static temporarily:"
    echo "  nix develop -c cabal build all --disable-executable-static"
  '';
}
