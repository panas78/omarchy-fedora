# Agent notes

## XERJ (code search) — reference coding

This project uses XERJ for **reference coding**: retrieve how a project that
already solved a problem did it, *before* writing code. Prefer the index over
grubbing through source. Cite `path:line` for anything you rely on.

- Go-to-definition (you know the name): `xerj def --prefix <p> "<symbol>"`
- Ranked passages (you have a question): `xerj search --prefix <p> "<plain words>"`
- The default prefix is `ax`; **our corpora use their own, so always pass `--prefix`.**
  A bare `xerj search` will not find them.
- Index/refresh a folder: `xerj autoindex <folder> --prefix <p> --state-dir ~/xerj-state/<p>`
- Node: `http://localhost:9200` (started `--insecure`, data-dir `~/xerj-data`,
  default **lexical** embedder). Start with:
  `nohup xerj --insecure --data-dir ~/xerj-data > ~/xerj-node.log 2>&1 & echo $! > ~/xerj-node.pid`

### Corpora (one prefix per repo)

| prefix | repo | why it's here |
|---|---|---|
| `omfed` | this repo (+ vendored `upstream/` Omarchy quattro) | project sources |
| `omadora` | elpritchos/omadora | **nearest reference** — Omarchy ported to **Fedora** |
| `nixarchy` | olafkfreund/nixarchy | Omarchy 4.x vendored for NixOS; same "vendor + shim the distro bits" design |
| `omakub` | basecamp/omakub | Ubuntu sibling of Omarchy; installer/package-acquisition patterns |
| `ublue` | ublue-os/packages | Fedora **COPR RPM specs** + system files (udev/presets) |
| `bluefin` | ublue-os/bluefin | Fedora desktop build; **isolated COPR install**, akmods, dracut |

Clones live under `~/Downloads/omarchy-refs/` (except omadora at `~/Downloads/omadora`).

### Ask in the source's own words (lexical search)

```sh
xerj search --prefix omadora  "authselect PAM system-auth"
xerj search --prefix nixarchy "replace pacman command shim distro coupling"
xerj search --prefix ublue    "copr enable isolated repository install"
xerj search --prefix omakub   "check-version distribution abort"
xerj def    --prefix omfed    omarchy_pkg_install
```
