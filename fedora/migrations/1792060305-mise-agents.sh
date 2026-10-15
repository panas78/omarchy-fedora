#!/bin/bash
# Install Omarchy's mise-backed agent/toolchain CLIs for existing installs.
#
# Upstream installs the coding-agent CLIs (opencode, codex, claude, ...) through
# mise at user setup (install/user/mise.sh -> omarchy-mise-install). The Fedora
# installer now does this on fresh installs (fedora/scripts/lib/mise.sh), but
# machines installed before that change have none of these tools. Run the same
# setup once, as the target user, so `omarchy update` converges them.
#
# Fresh installs are already covered by install.sh; running the helper again is
# idempotent (`mise use -g` + wrapper rewrite). Best-effort: the helper swallows
# per-tool failures, so this migration still records completion.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$here/../.." && pwd)"

# shellcheck source=../scripts/lib/mise.sh
. "$root/fedora/scripts/lib/mise.sh"

# Target user: the user who invoked the update (SUDO_USER), else the first
# regular (uid 1000+) account.
user="${SUDO_USER:-}"
if [ -z "$user" ] || [ "$user" = root ]; then
  user="$(awk -F: '$3>=1000 && $3<60000 {print $1; exit}' /etc/passwd)"
fi
[ -n "$user" ] || { echo "mise-agents: no target user; skipping" >&2; exit 0; }

omarchy_fedora_install_mise_tools "$user" "$root"

echo "mise-agents: mise agent/toolchain setup complete for $user"
