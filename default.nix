with import <nixpkgs> {};
with pkgs.lib;

stdenv.mkDerivation {
  name = "jimzos-nix-env";
  buildInputs = [
    bash
    direnv
    figlet
    git
    jq
    lolcat
    lsof
    ripgrep
    which
    clang_13
    llvmPackages_13.libclang
    llvmPackages_13.llvm
    llvmPackages_13.libllvm
    lld_13
    cmake
    fzf
    qemu
    glibcLocales
  ];

  shellHook = ''
    figlet  -f small -k "JimZOS"| lolcat -F 0.5 -ad 2 -s 30
    
    export LIBCLANG_PATH="${pkgs.llvmPackages.libclang}/lib";
    source "$(fzf-share)/key-bindings.bash"

    # get bash to behave a bit closer to zsh
    bind 'set show-all-if-ambiguous on'
    bind 'set show-all-if-unmodified on'
    bind 'set menu-complete-display-prefix on'
    bind 'TAB:menu-complete'

    # https://nixos.org/nixpkgs/manual/#python-setup.py-bdist_wheel-cannot-create-.whl
    export SOURCE_DATE_EPOCH=315532800

    eval "$(direnv hook bash)"
  '';
}
