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
  ];

  shellHook = ''
    figlet  -f small -k "JimZOS"| lolcat -F 0.5 -ad 2 -s 30
    export PROOT="$(git rev-parse --show-toplevel)"
    export PATH="$PROOT/scripts:$PATH"

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
