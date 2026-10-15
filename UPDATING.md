# UPDATING

## End-user update

`fedora/scripts/update.sh` updates the **Fedora** packages:

```bash
sudo ./fedora/scripts/update.sh
```

It refreshes dnf metadata and upgrades installed packages. It does not blindly
`git pull` a live install.

## Development sync

The live upstream pull is opt-in. With `OMARCHY_FEDORA_UPDATE_UPSTREAM=1` in a
git checkout that has an `upstream` remote and the `git subtree` helper
(`dnf install git-subtree`), it pulls the latest upstream `quattro` subtree:

```bash
sudo dnf install -y git-subtree
OMARCHY_FEDORA_UPDATE_UPSTREAM=1 ./fedora/scripts/update.sh
```

`upstream/` is a **squashed** subtree (the workflow adds it with `--squash`), so
the pull must use `--squash` as well; a plain `git subtree pull` fails with
`refusing to merge unrelated histories`. Without the env var, `omarchy update`
re-applies whatever `upstream/` is already committed and never rewrites the
checkout.

## Upstream change model

- Upstream changes are classified per `UPSTREAM.md`.
- The `upstream-sync` GitHub workflow runs daily and attempts a `SAFE` PR.
- When upstream adds/removes a package, update `fedora/mappings/packages.yaml`
  and re-run `fedora/tests/static.sh`.

## Full target updater (spec section 20)

`omarchy update` on Fedora runs `fedora/scripts/update.sh` (wired via a
`/usr/bin/omarchy-update` shim installed by `install.sh`). It performs:

1. Fetch Fedora repository metadata — `dnf makecache`
2. Update Fedora packages — `dnf upgrade` (now includes the first-party
   binaries shipped as RPMs from the `whelanh/omarchy` COPR)
3. (optional) Sync the Omarchy userspace to upstream `quattro` —
   `git subtree pull --squash`, only with `OMARCHY_FEDORA_UPDATE_UPSTREAM=1` and
   a git checkout that has the `upstream` remote and the `git-subtree` package
4. Re-apply the userspace — `install.sh --update` (idempotent: re-copies the
   tree, re-wires `omarchy-*` onto PATH, re-installs the uwsm-app / chromium /
   sudoers / fonts compat shims, validates)
5. Migrations — `omarchy_fedora_migrate` runs our **Fedora-native** migrations
   (`fedora/migrations/*.sh`, once each, as root) for package
   removals/replacements and distro-neutral config changes. Upstream's
   Arch-specific `omarchy-migrate` is intentionally not run (see
   `fedora/migrations/README.md`).
6. Update mise tools — `omarchy_fedora_update_mise` runs
   `MISE_MINIMUM_RELEASE_AGE=0 mise upgrade` for the target user, mirroring
   upstream's `omarchy-update-mise`. The cooldown override is the point: mise
   otherwise withholds releases younger than its release age, so `omarchy
   update` is the user asking for current versions now. Best-effort: a failed
   tool build warns and continues. Skipped when mise is not installed.
7. Validate — `install.sh --update` reports package + CLI wiring + version

Step 3 requires the development checkout (and is opt-in). Step 4 runs for any
install. For a purely end-user install (no git checkout), the Omarchy userspace
is refreshed from the `quattro` tarball rather than `dnf`; see "Limitations"
below.

Agent/toolchain CLIs (opencode, codex, claude, ...) are **not** RPMs. Upstream
installs them through mise at user setup (`install/user/mise.sh` →
`omarchy-mise-install`), and the Fedora layer does the same on a fresh install
(`fedora/scripts/lib/mise.sh`). Machines installed before that wiring get them
from the one-time `fedora/migrations/*-mise-agents.sh` migration (step 5); step
6 then keeps them current. One consequence: `openai-codex-bin` was a Fedora
repack of the Codex CLI, but upstream moved Codex to mise and removes the old
pacman package, so it is now retired here too (`fedora/mappings/
retired-packages.conf` prunes it). The `openai-codex-desktop` ChatGPT GUI stays
in the COPR.

### Limitations

- The Omarchy **userspace** (the `/usr/share/omarchy` tree) is a rolling branch
  (`quattro`), not a versioned release. For a git checkout, `omarchy update`
  re-applies the committed `upstream/` tree; advancing it is a review step
  (`git pull` of the merged upstream-sync PR, or an opt-in live
  `git subtree pull --squash`, see "Development sync"). For a non-git install it
  falls back to a direct download of the `quattro` tarball rsynced into
  `/usr/share/omarchy` (see `omarchy_fedora_sync_userspace_tarball` in
  `update.sh`). Both paths then re-apply wiring via `install.sh --update`.
  Packaging the userspace as an RPM is intentionally avoided: a static RPM would
  drift immediately against the rolling branch; a live fetch has no staleness
  window.
- The upstream `omarchy-update` flow is pacman/AUR-specific (`pacman -Syu`,
  `paccache`, `yay`, `pacman-key`); those steps have no Fedora equivalent and
  are replaced by `dnf upgrade` + the first-party COPR RPMs.
