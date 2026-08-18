# NixOS options search

A self-hosted [NuschtOS/search](https://github.com/NuschtOS/search) site that renders one
or more pre-generated `options.json` files as a fast, static option search — like
[search.nixos.org](https://search.nixos.org), but for arbitrary or unmerged option sets
(a PR branch, a personal flake, a downstream module set, …) that the official search does
not index.

Options are organised into **scopes** (searchable/filterable module sets, one `options.json`
each) and grouped into **views** — one NuschtOS site per comparison. Each view is published at
its own subpath, so the repo can host several in parallel, with a landing page listing them.

## Structure

```
flake.nix                     # the `views` list (each = title + subpath name + scopes)
options/<name>.options.json   # one pre-generated options.json per scope
nix/gen-options.nix           # derivation behind the gen-options app
.github/workflows/pages.yml   # builds `.#site` with Nix and deploys to GitHub Pages
```

- Each entry in the `views` list becomes a NuschtOS site at `<repoBase>/<view-name>/` and its
  own `packages.<view-name>`. `repoBase` (top of `flake.nix`) is the GitHub Pages project path,
  e.g. `/nixos-search`; use `""` for a user/org site or a root host.
- `packages.site` (also `default`) is what Pages publishes: a landing `index.html` listing the
  views, every view under its subpath, and a root `404.html` SPA fallback.

## Add or change a view

Add an entry to the `views` list in `flake.nix`:

```nix
{
  name = "my-comparison";                    # subpath: <repoBase>/my-comparison/
  title = "My comparison";                   # heading + landing-page label
  scopes = [
    {
      name = "Scope A";                                      # label in the scope dropdown
      optionsJSON = ./options/a.options.json;
      optionsPrefix = "";                                    # see note
      urlPrefix = "https://github.com/OWNER/REPO/blob/REV/"; # base for Declarations links
    }
    # more scopes, compared side by side …
  ];
}
```

- `optionsPrefix` is only needed when the option names in the JSON are relative to a module
  (it prepends `<prefix>.`); for a full-system `options.json` leave it empty.
- `urlPrefix` + a declaration must form a working source URL, so the JSON's declarations should
  be repo-relative — the `gen-options` app does that (see below).

## Build / preview locally

```sh
nix build .#site                       # landing + all views  (or .#<view-name> for just one)
mkdir -p www && cp -rL result/. "www<repoBase>/"
python3 -m http.server -d www 8080
# open http://127.0.0.1:8080<repoBase>/            (landing)
#      http://127.0.0.1:8080<repoBase>/<view>/     (a view)
```

## Deploy to GitHub Pages

1. **`repoBase` must match the Pages path.** For a project site at
   `https://<user>.github.io/<repo>/`, set `repoBase = "/<repo>"`. For a user/org site or a
   root host, use `""`.
2. Repo → Settings → Pages → **Source: GitHub Actions**.
3. Push to `main`; `.github/workflows/pages.yml` builds `.#site` and deploys. Views land at
   `https://<user>.github.io/<repo>/<view-name>/`.

## Generate a scope's `options.json`

The `options.json` files are generated, not hand-written. The `gen-options` app produces one
for any nixpkgs revision, passed on the command line — it evaluates a minimal NixOS system at
that revision, runs `nixosOptionsDoc`, filters to a prefix, and rewrites declaration paths to
be repo-relative (so `urlPrefix` + declaration is a working source URL):

```sh
nix run .#gen-options -- <nixpkgs-flake-ref> [option-prefix] > options/<name>.options.json
```

- `<nixpkgs-flake-ref>` — any flake reference: `github:OWNER/nixpkgs/<rev>`, a branch, or a
  local `path:/checkout`.
- `[option-prefix]` — keep only options whose name starts with it (omit / `""` keeps all).

Examples:

```sh
# a PR-branch commit, only services.foo.* options
nix run .#gen-options -- github:OWNER/nixpkgs/<rev> services.foo > options/foo.options.json
# a local checkout, all options
nix run .#gen-options -- path:/path/to/nixpkgs > options/bar.options.json
```

Then add the matching scope to `scopes` in `flake.nix`, with `urlPrefix` pointing at the same
revision (e.g. `https://github.com/OWNER/nixpkgs/blob/<rev>/`).

---

Built with [NuschtOS/search](https://github.com/NuschtOS/search).
