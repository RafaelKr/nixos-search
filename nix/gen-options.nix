# Generate a filtered, declaration-relativized options.json for an arbitrary nixpkgs
# revision. Driven entirely by two environment variables so it needs no CLI-arg
# interpolation into Nix source:
#
#   NIXPKGS_REF  a flake reference, e.g. "github:NixOS/nixpkgs/<rev>" or "path:/checkout"
#   OPT_PREFIX   only keep options whose name starts with this (empty = keep all)
#
# Build with:  nix build --impure -f nix/gen-options.nix
# (the `gen-options` app wires this up; see flake.nix)
let
  ref = builtins.getEnv "NIXPKGS_REF";
  prefix = builtins.getEnv "OPT_PREFIX";
  nixpkgs = builtins.getFlake ref;
  system = builtins.currentSystem;
  pkgs = import nixpkgs { inherit system; };
  eval = import (nixpkgs + "/nixos/lib/eval-config.nix") {
    inherit system;
    modules = [
      {
        system.stateVersion = "25.05";
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "/dev/sda1";
          fsType = "ext4";
        };
      }
    ];
  };
  doc = (pkgs.nixosOptionsDoc { inherit (eval) options; warningsAreErrors = false; }).optionsJSON;
in
pkgs.runCommand "options.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
  jq --arg prefix ${pkgs.lib.escapeShellArg prefix} '
    (if $prefix == "" then . else with_entries(select(.key | startswith($prefix))) end)
    | map_values(
        if has("declarations")
        then .declarations |= map(if type == "string" then sub(".*?(?<p>nixos/.*)$"; "\(.p)") else . end)
        else . end
      )
  ' ${doc}/share/doc/nixos/options.json > $out
''
