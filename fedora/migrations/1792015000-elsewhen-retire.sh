#!/bin/bash
# Elsewhen retired upstream: moved in-tree as omarchy.elsewhen.
#
# Upstream migrations/1790528634.sh renames omacom.elsewhen entries in
# shell.json (keeping cities/settings) and runs `omarchy-pkg-drop elsewhen`.
# The Fedora port never runs upstream Arch migrations, so this is the
# Fedora-native equivalent. It supersedes 1790092003-elsewhen-plugin.sh, which
# placed the old omacom.elsewhen widget and caused duplicate world clocks on
# fresh installs (the seeded upstream shell.json already carries the in-tree
# omarchy.elsewhen).
#
# For every human user: rename omacom.elsewhen -> omarchy.elsewhen in
# bar.layout / bar.centerAnchor / plugins / disabledPlugins, then deduplicate
# (fresh installs hit by both widgets end up with two omarchy.elsewhen entries
# after the rename; keep the first occurrence with its settings).
# Also removes the dev-checkout symlink, the old cache dir, and the retired
# elsewhen RPM (prune_retired covers the package too; this keeps NO_PRUNE=1
# machines converged like upstream).
set -euo pipefail

rename_user_shell_json() {
  local user="$1" home="$2"
  local shell_json="$home/.config/omarchy/shell.json"
  [ -s "$shell_json" ] || return 0
  runuser -u "$user" -- env HOME="$home" python3 - "$shell_json" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    try:
        data = json.load(f)
    except Exception:
        sys.exit(0)  # not valid JSON yet; leave alone, retry next update via exit 0
changed = False

def rename_id(v):
    global changed
    if v == "omacom.elsewhen":
        changed = True
        return "omarchy.elsewhen"
    if isinstance(v, dict) and v.get("id") == "omacom.elsewhen":
        v = dict(v)
        v["id"] = "omarchy.elsewhen"
        changed = True
        return v
    return v

def key_of(entry):
    if isinstance(entry, dict):
        return ("id:" + str(entry.get("id", "")))
    return ("str:" + str(entry))

def dedup(seq):
    # Fresh installs hit by both widgets end up with two omarchy.elsewhen
    # entries after the rename (seeded in-tree default + old out-of-tree one
    # carrying the user's cities). Keep one, preferring the entry with
    # settings (more keys) so custom zones survive.
    seen = {}
    out = []
    for e in seq:
        k = key_of(e)
        if k in seen:
            global changed
            changed = True
            idx = seen[k]
            old = out[idx]
            if isinstance(e, dict) and isinstance(old, dict) \
               and len(e) > len(old):
                out[idx] = e
            continue
        seen[k] = len(out)
        out.append(e)
    return out

bar = data.get("bar")
if isinstance(bar, dict):
    layout = bar.get("layout")
    if isinstance(layout, dict):
        for zone, arr in list(layout.items()):
            if isinstance(arr, list):
                layout[zone] = dedup([rename_id(e) for e in arr])
    if isinstance(bar.get("centerAnchor"), str):
        bar["centerAnchor"] = rename_id(bar["centerAnchor"])
for lst in ("plugins", "disabledPlugins"):
    if isinstance(data.get(lst), list):
        data[lst] = dedup([rename_id(e) for e in data[lst]])

if changed:
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
PYEOF
  # user symlink created for dev checkouts pointing into the system tree
  local link="$home/.config/omarchy/plugins/omacom.elsewhen"
  if [ -L "$link" ]; then
    local target
    target="$(readlink "$link" || true)"
    case "$target" in
      /usr/share/omarchy/*) runuser -u "$user" -- env HOME="$home" rm -f "$link" ;;
    esac
  fi
  # old cache dir
  local cache="$home/.cache/omacom-elsewhen"
  if [ -e "$cache" ]; then
    runuser -u "$user" -- env HOME="$home" rm -rf "$cache"
  fi
}

# All human users (uid 1000-60000), plus SUDO_USER first if set.
users=""
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
  users="$SUDO_USER"
fi
while IFS=: read -r name _ uid _ _ home _; do
  if [ "$uid" -ge 1000 ] && [ "$uid" -lt 60000 ]; then
    case " $users " in
      *" $name "*) ;;
      *) users="$users $name" ;;
    esac
  fi
done < /etc/passwd

for user in $users; do
  home="$(getent passwd "$user" | cut -d: -f6)"
  [ -n "$home" ] && [ -d "$home" ] || continue
  rename_user_shell_json "$user" "$home" || echo "elsewhen-retire: config migration failed for $user; continuing" >&2
done

# Drop the retired package if present (prune_retired does this too on update;
# explicit here so the duplicate plugin source is gone even with NO_PRUNE=1).
if rpm -q elsewhen >/dev/null 2>&1; then
  echo "elsewhen-retire: removing retired elsewhen RPM"
  dnf -y remove elsewhen || echo "elsewhen-retire: dnf remove failed; prune_retired will retry" >&2
fi

# Leftover from the pre-1.0.0-2 RPM path; the fixed RPM never used it.
for stale in /usr/share/omarchy/plugins/omacom.elsewhen; do
  if [ -e "$stale" ]; then
    echo "elsewhen-retire: removing stale $stale"
    rm -rf "$stale"
  fi
done

echo "elsewhen-retire: omacom.elsewhen renamed/deduped to omarchy.elsewhen"
