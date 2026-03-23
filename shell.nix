{ pkgs, ... }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    erlang
    rebar3
    gleam
    nixfmt
    treefmt
    tailwindcss
  ];
}
