{
  description = "Static NuschtOS/search views for arbitrary NixOS options.json scopes";

  inputs = {
    search.url = "github:NuschtOS/search";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, search, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      inherit (pkgs) lib;
      mkMultiSearch = search.packages.${system}.mkMultiSearch;

      # Served at https://<user>.github.io<repoBase>/<view>/ — each view's baseHref
      # must match its subpath. Set repoBase to "/<repo>" for a GitHub Pages project
      # site, or "" for a user/org site or a root host.
      repoBase = "/nixos-search";

      # One entry per view. Add more to host several comparisons in parallel; each
      # gets its own subpath and its own `packages.<name>`.
      views = [
        {
          name = "pr553100-vs-attrtag";
          title = "Traefik module options — PR #553100 vs attrTag";
          scopes = [
            {
              name = "PR #553100 (4ff7df0e)";
              optionsJSON = ./options/pr553100.options.json;
              urlPrefix = "https://github.com/NixOS/nixpkgs/blob/4ff7df0e2e4722d59d9e6075bf7db810b8b0d365/";
            }
            {
              name = "attrTag (7c01005a)";
              optionsJSON = ./options/attrtag.options.json;
              urlPrefix = "https://github.com/RafaelKr/nixpkgs/blob/7c01005a306fe7e79dea85ef36f580c6a1cdc2a3/";
            }
          ];
        }
      ];

      builtViews = map (
        v:
        v
        // {
          drv = mkMultiSearch {
            baseHref = "${repoBase}/${v.name}/";
            inherit (v) title scopes;
          };
        }
      ) views;

      # Landing page listing the views.
      indexHtml = pkgs.writeText "index.html" ''
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>NixOS options search</title>
        <style>
          body{font-family:system-ui,-apple-system,sans-serif;max-width:44rem;margin:3rem auto;padding:0 1.2rem;line-height:1.6;color:#1a2130}
          h1{font-size:1.5rem} a{color:#3b5bdb} ul{padding-left:1.1rem} li{margin:.5rem 0}
          .sub{color:#5b6577;font-size:.95rem}
        </style>
        </head>
        <body>
          <h1>NixOS options search</h1>
          <p class="sub">Static <a href="https://github.com/NuschtOS/search">NuschtOS/search</a> views:</p>
          <ul>
          ${lib.concatStrings (map (v: ''<li><a href="${v.name}/">${v.title}</a></li>'') builtViews)}
          </ul>
        </body>
        </html>
      '';

      # GitHub Pages serves one root 404.html for any missing path. Redirect a deep
      # client-side route under a view back to that view's index so reloads/shared
      # deep links still land in the right app (query and hash preserved).
      notFoundHtml = pkgs.writeText "404.html" ''
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><title>Redirecting…</title>
        <script>
          (function () {
            var m = location.pathname.match(new RegExp("^(${repoBase}/[^/]+/)"));
            location.replace(m ? m[1] + location.search + location.hash : "${repoBase}/");
          })();
        </script></head><body></body></html>
      '';

      site = pkgs.runCommand "nixos-search-site" { } ''
        mkdir -p $out
        cp ${indexHtml} $out/index.html
        cp ${notFoundHtml} $out/404.html
        ${lib.concatStringsSep "\n" (
          map (v: ''
            mkdir -p "$out/${v.name}"
            cp -r ${v.drv}/. "$out/${v.name}/"
          '') builtViews
        )}
      '';

      # `nix run .#gen-options -- <nixpkgs-flake-ref> [option-prefix] > options/<name>.options.json`
      gen-options = pkgs.writeShellApplication {
        name = "gen-options";
        text = ''
          if [ "$#" -lt 1 ]; then
            echo "usage: nix run .#gen-options -- <nixpkgs-flake-ref> [option-prefix] > options/<name>.options.json" >&2
            echo "  e.g. nix run .#gen-options -- github:NixOS/nixpkgs/<rev> services.traefik > options/foo.options.json" >&2
            exit 2
          fi
          NIXPKGS_REF="$1" OPT_PREFIX="''${2:-}" \
            nix build --impure --no-link --print-out-paths \
              --extra-experimental-features 'nix-command flakes' \
              -f ${./nix/gen-options.nix} | { read -r out; cat "$out"; }
        '';
      };
    in
    {
      packages.${system} =
        (lib.listToAttrs (map (v: lib.nameValuePair v.name v.drv) builtViews))
        // {
          # What the Pages workflow publishes: landing index + every view in its subpath.
          site = site;
          default = site;
        };

      apps.${system}.gen-options = {
        type = "app";
        program = "${gen-options}/bin/gen-options";
      };
    };
}
