#!/usr/bin/env bash
# Build SRPMs for the Omarchy first-party RPMs and submit them to the
# whelanh/omarchy COPR for remote building.
#
# Usage:
#   fedora/rpm/copr/submit-builds.sh                 # all verified packages, all chroots
#   fedora/rpm/copr/submit-builds.sh aether ttfx     # only these packages
#   fedora/rpm/copr/submit-builds.sh --srpms-only    # build SRPMs, no submit
#   fedora/rpm/copr/submit-builds.sh --no-watch      # submit, return immediately
#   fedora/rpm/copr/submit-builds.sh --retries 3 --retry-delay 120
#   fedora/rpm/copr/submit-builds.sh --chroot fedora-45-x86_64   # only this chroot
#
# By default the script watches the builds and self-heals: a chroot that failed
# for a recognised transient reason (e.g. the per-chroot nett00n/hyprland build
# repo briefly 404ing while COPR's Pulp mirror resyncs) is resubmitted, a bounded
# number of times. Real failures (compile errors, unresolved BuildRequires) are
# reported and never retried. COPR_RETRIES / COPR_RETRY_DELAY override the
# defaults (2 attempts, 60s base backoff).
#
# Requires:
#   - copr-cli (dnf install -y copr-cli) + login (see README.md)
#   - rpm-build, python3 + pyyaml
#
# Each SRPM is produced with `rpmbuild -bs` from fedora/rpm/<pkg>/<pkg>.spec
# (sources are downloaded locally first). Then `copr-cli build` pushes the
# SRPM and COPR builds it in every enabled chroot of the project — or, when
# one or more --chroot flags are given, only those chroots (see
# create-project.sh for how the nett00n/hyprland build repo is wired per
# chroot).
set -euo pipefail

RPM_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$RPM_DIR/manifest.yaml"
COPR="whelanh/omarchy"
SUBMIT=1
WATCH=1
RETRIES="${COPR_RETRIES:-2}"
RETRY_DELAY="${COPR_RETRY_DELAY:-60}"
TOP="${HOME}/rpmbuild-omarchy"
CHROOTS=()

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required tool: $1" >&2; exit 1; }; }
need rpmbuild
need python3

# resolve the RPM Name from a spec (mirrors install-rpms.sh)
spec_name() {
  python3 - "$1" <<'PY'
import re,sys
print(re.search(r'^Name:\s*(\S+)', open(sys.argv[1]).read(), re.M).group(1))
PY
}

# Packages to build: explicit args minus flags, else manifest 'verified' set.
# Flags: --srpms-only (don't submit), --chroot <name> (repeatable; submit to
# only these chroots instead of every enabled project chroot).
pkgs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --srpms-only) SUBMIT=0 ;;
    --no-watch) WATCH=0 ;;
    --retries) RETRIES="${2:?--retries needs a value}"; shift ;;
    --retry-delay) RETRY_DELAY="${2:?--retry-delay needs a value}"; shift ;;
    --chroot) CHROOTS+=("$2"); shift ;;
    *) pkgs+=("$1") ;;
  esac
  shift
done
if [ "${#pkgs[@]}" -eq 0 ]; then
  while IFS= read -r p; do pkgs+=("$p"); done < <(
    python3 - "$MANIFEST" <<'PY'
import yaml,sys
d=yaml.safe_load(open(sys.argv[1]))
print('\n'.join(sorted(p for p,v in d['packages'].items() if v['status']=='verified')))
PY
  )
fi
echo "packages: ${pkgs[*]}"

mkdir -p "$TOP"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
# clear stale SRPMs from a prior run so the per-package glob below only matches
# the SRPM just built (avoids resubmitting old versions).
rm -rf "$TOP/SRPMS"/*
SRPMS=()
for pkg in "${pkgs[@]}"; do
  spec="$RPM_DIR/$pkg/$pkg.spec"
  [ -f "$spec" ] || { echo "no spec for $pkg; skipping" >&2; continue; }
  echo "== building SRPM: $pkg =="
  rm -rf "$TOP/SOURCES"/*; mkdir -p "$TOP/SOURCES"
  cp "$spec" "$TOP/SPECS/$pkg.spec"
  # Download spec sources (same expansion logic as build-rpm-in-ci.sh).
  (cd "$TOP/SOURCES" && python3 - "$spec" <<'PY'
import re,sys,urllib.request,os
# Some vendors block the default Python-urllib User-Agent; use a browser one.
_opener = urllib.request.build_opener()
_opener.addheaders = [('User-Agent', 'Mozilla/5.0')]
urllib.request.install_opener(_opener)
spec=open(sys.argv[1]).read()
def f(k):
    m=re.search(r'^%s:\s*(\S+)'%k,spec,re.M); return m.group(1) if m else ''
url,ver,name=f('URL'),f('Version'),f('Name')
macros={}
for m in re.finditer(r'^%global\s+(\S+)\s+(\S+)',spec,re.M):
    macros[m.group(1)]=m.group(2)
def expand(u):
    for k,v in list(macros.items())+[('url',url),('version',ver),('name',name)]:
        u=u.replace('%%{%s}'%k,v)
    return u
for m in re.finditer(r'^Source\d*:\s*(\S+)',spec,re.M):
    u=expand(m.group(1))
    if not u.startswith(('http://','https://')):
        continue
    fn=os.path.basename(u)
    if not os.path.exists(fn):
        print('fetching',u); urllib.request.urlretrieve(u,fn)
PY
)
  # Rust packages build offline in COPR from a vendored crates.io tarball.
  . "$RPM_DIR/vendor-rust.sh"
  generate_rust_vendor "$spec" "$TOP/SOURCES" "/tmp/omarchy-vendor-$pkg"
  rpm_name="$(spec_name "$spec")"
  rpmbuild --define "_topdir $TOP" -bs "$spec" || { echo "SRPM build failed: $pkg" >&2; exit 1; }
  SRPMS+=("$TOP/SRPMS/${rpm_name}"*)
done

[ -n "${SRPMS[*]}" ] || { echo "no SRPMs produced" >&2; exit 1; }
echo
echo "SRPMs:"
printf '   %s\n' "${SRPMS[@]}"

# --- submission, watch, bounded self-heal ------------------------------------
#
# A COPR build can fail for reasons outside our control that clear up on their
# own: the per-chroot build repo (nett00n/hyprland) is served through COPR's
# Pulp mirror, and while it resyncs a fetch can 404 before rpmbuild even starts
# ("Failed to download metadata" / "Usable URL not found"). Rather than leave a
# red build for a human to notice, watch the build and resubmit only the chroots
# that failed for a recognised transient reason, a bounded number of times.
#
# The pattern is deliberately narrow: a compile error or an unresolved
# BuildRequires must never be retried.
TRANSIENT_RE='Failed to download metadata|Usable URL not found|Cannot download repomd\.xml|Status code: (404|502|503|504)|Could not resolve host|Temporary failure in name resolution|Connection (timed out|reset by peer)|No space left on device|Cannot allocate memory'

# Read one field from the COPR build API: state, pkg (source package name) or
# chroots (comma-separated). Prints nothing on error so callers can fall back.
copr_build_field() {  # <build_id> <state|pkg|chroots>
  python3 - "$1" "$2" <<'PY'
import json, sys, urllib.request
bid, field = sys.argv[1], sys.argv[2]
try:
    req = urllib.request.Request(
        "https://copr.fedorainfracloud.org/api_3/build/%s" % bid,
        headers={"User-Agent": "omarchy-submit-builds"})
    d = json.load(urllib.request.urlopen(req, timeout=30))
except Exception:
    print("")
    raise SystemExit(0)
if field == "chroots":
    print(",".join(d.get("chroots") or []))
elif field == "pkg":
    print((d.get("source_package") or {}).get("name", ""))
else:
    print(d.get(field, ""))
PY
}

# results.json is published for a chroot that actually produced packages; a
# chroot that died in buildroot setup or rpmbuild leaves only logs.
copr_chroot_ok() {  # <build_id> <pkg> <chroot>
  curl -sfL -o /dev/null \
    "https://download.copr.fedorainfracloud.org/results/$COPR/$3/$1-$2/results.json"
}

copr_chroot_transient() {  # <build_id> <pkg> <chroot>
  local gz txt rc
  gz="$(mktemp)"; txt="$(mktemp)"
  if curl -sfL \
       "https://download.copr.fedorainfracloud.org/results/$COPR/$3/$1-$2/builder-live.log.gz" \
       -o "$gz" && gunzip -c "$gz" >"$txt" 2>/dev/null; then
    if grep -Eqi "$TRANSIENT_RE" "$txt"; then rc=0; else rc=1; fi
  else
    rc=1
  fi
  rm -f "$gz" "$txt"
  return "$rc"
}

# Submit one SRPM (optionally limited to the given chroots) and print its build
# id. One SRPM per call keeps the SRPM -> build mapping 1:1, which is what makes
# a per-chroot retry possible.
copr_submit_one() {  # <srpm> [chroot...]
  local srpm="$1"; shift
  local -a rargs=()
  local c
  for c in "$@"; do rargs+=(-r "$c"); done
  local out id
  out="$(copr-cli build --nowait "$COPR" "${rargs[@]}" "$srpm" 2>&1)" || {
    printf '%s\n' "$out" >&2
    return 1
  }
  printf '%s\n' "$out" >&2
  id="$(printf '%s\n' "$out" | grep -oE 'build/[0-9]+' | grep -oE '[0-9]+' | head -1)"
  if [ -z "$id" ]; then
    id="$(printf '%s\n' "$out" | sed -n 's/^Created builds:[[:space:]]*//p' \
          | tr -cs '0-9' '\n' | head -1)"
  fi
  [ -n "$id" ] || return 1
  printf '%s\n' "$id"
}

copr_submit_watch_heal() {
  local attempt=0
  local -a queue=("${SRPMS[@]}")
  declare -A retry_chroots=()

  while :; do
    local -a ids=()
    local s id c
    for s in "${queue[@]}"; do
      # want = chroots to build this SRPM in (empty = every project chroot).
      local -a want=() rargs=()
      if [ "$attempt" -eq 0 ]; then
        want=("${CHROOTS[@]}")
      else
        # Retry only this SRPM's failed chroots.
        for c in ${retry_chroots[$s]:-}; do want+=("$c"); done
      fi
      for c in "${want[@]}"; do rargs+=(-r "$c"); done
      if ! id="$(copr_submit_one "$s" "${rargs[@]}")"; then
        echo "COPR submission failed for $s" >&2
        return 1
      fi
      ids+=("$id")
      if [ "${#want[@]}" -gt 0 ]; then
        echo "  submitted $s -> build $id (chroots: ${want[*]})"
      else
        echo "  submitted $s -> build $id (all project chroots)"
      fi
    done

    echo "== watching ${#ids[@]} build(s) =="
    copr-cli watch-build "${ids[@]}" || true

    local -a next=()
    retry_chroots=()
    local failed_any=0 retryable=1
    local i state pkg chroots ch
    for i in "${!queue[@]}"; do
      s="${queue[$i]}"; id="${ids[$i]}"
      state="$(copr_build_field "$id" state)"
      # watch-build would normally have blocked until the build finished; if it
      # blipped (network) and the build is still running, watch it once more
      # rather than mistaking "running" for a real failure.
      case "$state" in
        succeeded|failed|canceled|skipped) ;;
        *)
          echo "  build $id not finished (state=${state:-unknown}); re-watching" >&2
          copr-cli watch-build "$id" || true
          state="$(copr_build_field "$id" state)" ;;
      esac
      pkg="$(copr_build_field "$id" pkg)"
      if [ "$state" = "succeeded" ]; then
        echo "  OK: $pkg (build $id)"
        continue
      fi
      failed_any=1
      echo "  FAILED: $pkg (build $id, state=${state:-unknown})" >&2

      chroots="$(copr_build_field "$id" chroots)"
      local -a bad=()
      for ch in ${chroots//,/ }; do
        if copr_chroot_ok "$id" "$pkg" "$ch"; then
          echo "    $ch: ok" >&2
        elif copr_chroot_transient "$id" "$pkg" "$ch"; then
          echo "    $ch: transient (retryable)" >&2
          bad+=("$ch")
        else
          echo "    $ch: real failure (not retryable)" >&2
          retryable=0
        fi
      done
      if [ "${#bad[@]}" -gt 0 ]; then
        retry_chroots["$s"]="${bad[*]}"
        next+=("$s")
      fi
    done

    if [ "$failed_any" -eq 0 ]; then
      echo "== all COPR builds succeeded =="
      return 0
    fi
    if [ "$retryable" -eq 0 ] || [ "${#next[@]}" -eq 0 ]; then
      echo "== COPR build failed; not retrying (non-transient failure) ==" >&2
      return 1
    fi
    if [ "$attempt" -ge "$RETRIES" ]; then
      echo "== COPR build still failing after $RETRIES retries ==" >&2
      return 1
    fi
    attempt=$((attempt + 1))
    local delay=$(( RETRY_DELAY * attempt ))
    echo "== transient failure: retry $attempt/$RETRIES in ${delay}s ==" >&2
    sleep "$delay"
    queue=("${next[@]}")
  done
}

if [ "$SUBMIT" = 1 ]; then
  need copr-cli
  if [ "${#CHROOTS[@]}" -gt 0 ]; then
    echo "== submitting ${#SRPMS[@]} SRPM(s) to $COPR (chroots: ${CHROOTS[*]}) =="
  else
    echo "== submitting ${#SRPMS[@]} SRPM(s) to $COPR (all chroots) =="
  fi
  if [ "$WATCH" = 0 ]; then
    chroot_args=()
    for c in "${CHROOTS[@]}"; do chroot_args+=(-r "$c"); done
    copr-cli build --nowait "$COPR" "${chroot_args[@]}" "${SRPMS[@]}"
    echo
    echo "Submitted (watch disabled). Progress: copr-cli list-builds $COPR"
  else
    copr_submit_watch_heal
  fi
else
  echo "(--srpms-only: not submitting; SRPMs left in $TOP/SRPMS)"
fi