#!/bin/bash
# omarchy-fedora mise user-toolchain setup
#
# Upstream Omarchy installs its coding-agent CLIs (opencode, codex, claude,
# crush, copilot, grok, ...) and a few dev tools through mise at user setup,
# not as system packages: install/user/all.sh sources install/user/mise.sh,
# which calls `omarchy-mise-install <tool>`. That helper writes a
# ~/.local/bin/<cmd> wrapper that runs `mise use -g <tool>` and then `mise x`
# it, so the tool lives under the user's $HOME. `omarchy-upgrade-to-quattro`
# correspondingly removes the old pacman `opencode` / `openai-codex-bin`
# packages, because Quattro moved these to mise.
#
# This library mirrors that on Fedora: the vendored upstream
# install/user/mise.sh is the single source of truth for the tool list, so an
# upstream subtree sync keeps the agent set current without a second copy to
# drift. Sourced by install.sh (fresh install) and the mise-agents migration
# (existing installs). Safe to source repeatedly.

if [ -n "${OMARCHY_FEDORA_MISE_LIB:-}" ]; then return 0 2>/dev/null || exit 0; fi
OMARCHY_FEDORA_MISE_LIB=1

# Install Omarchy's mise-backed agent/toolchain set for $user, as $user, by
# running the vendored upstream install/user/mise.sh.
#
# Best-effort: a single tool that fails to build (network, upstream release
# churn) must not abort the install or the update, so failures are reported and
# swallowed. No-op when mise is absent, the user does not exist, or the vendored
# script is missing.
#
#   $1 user         (required; no-op if empty or unknown)
#   $2 omarchy root (optional; directory containing upstream/ and fedora/)
omarchy_fedora_install_mise_tools() {
  local user="$1" root="${2:-}"
  [ -n "$user" ] || return 0
  id "$user" >/dev/null 2>&1 || return 0

  if ! command -v mise >/dev/null 2>&1; then
    echo "omarchy: mise not installed; skipping mise agent tools" >&2
    return 0
  fi

  if [ -z "$root" ]; then
    root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
  fi
  local script="$root/upstream/install/user/mise.sh"
  if [ ! -f "$script" ]; then
    echo "omarchy: no $script; skipping mise agent tools" >&2
    return 0
  fi

  local home
  home="$(getent passwd "$user" | cut -d: -f6)"
  [ -n "$home" ] || return 0

  # Run as the target user (tools land in their $HOME). When already that user,
  # run in place; when root, drop to them.
  local -a runner=()
  if (( EUID == 0 )); then
    if command -v runuser >/dev/null 2>&1; then
      runner=(runuser -u "$user" --)
    else
      runner=(sudo -u "$user")
    fi
  fi

  echo "omarchy: installing Omarchy agent/toolchain CLIs via mise for $user" >&2
  # HOME must point at the target user's home; PATH must include /usr/bin so the
  # vendored script finds `omarchy-mise-install` (wired to /usr/bin) and `mise`.
  "${runner[@]}" env \
    HOME="$home" \
    PATH="/usr/local/bin:/usr/bin:/bin:$home/.local/bin" \
    bash "$script" \
    || echo "omarchy: mise agent setup failed for $user; continuing" >&2
  return 0
}
