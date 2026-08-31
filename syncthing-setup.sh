#!/usr/bin/env bash
#
# syncthing-setup.sh — install, start, and declaratively configure Syncthing.
# Cross-platform (macOS + Linux). Runs OUT OF BAND — it is deliberately NOT part
# of `chezmoi apply` / `configure.sh` / `install.sh`, so setting up your dotfiles
# never installs or reconfigures Syncthing behind your back. Run it when you
# actually want Syncthing on this machine:
#
#   ./syncthing-setup.sh            # ensure installed + running, then reconcile
#   ./syncthing-setup.sh --install-only   # just install the binary; don't touch config
#   ./syncthing-setup.sh --no-install     # reconcile only; never install/download
#   ./syncthing-setup.sh --help
#
# It reconciles the desired peer *devices* and shared *folders* from the spec in
#   home/.chezmoidata/syncthing.json  (the ".syncthing" object)
# into the local instance via its REST API. Reconciliation is create-or-update
# and ADDITIVE — it never removes devices/folders you added by hand. Idempotent
# and safe to re-run. Edit the spec with:  task syncthing:edit
#
# Install strategy: if `syncthing` is already on PATH (e.g. a Homebrew install),
# it is used as-is. Otherwise the official release binary for this OS/arch is
# downloaded from GitHub into ~/.local/bin — no root, works on any distro.
#
# Symmetric teardown lives in ./decommission.sh (stops Syncthing gracefully and
# reads folder paths from config.xml before wiping).

set -eu

INSTALL_ONLY=0
NO_INSTALL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"

usage() {
  awk '
    NR == 1        { next }
    /^#/           { sub(/^# ?/, ""); print; next }
    /^[[:space:]]*$/ { print; next }
    { exit }
  ' "${BASH_SOURCE[0]}"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-only) INSTALL_ONLY=1; shift ;;
    --no-install)   NO_INSTALL=1; shift ;;
    --help|-h)      usage; exit 0 ;;
    *) printf 'Unknown option: %s\n\n' "$1" >&2; usage; exit 2 ;;
  esac
done

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Put Homebrew (macOS) on PATH so brew-installed jq/curl/syncthing resolve
#    even from a non-login shell. Also make sure ~/.local/bin is visible.
# ---------------------------------------------------------------------------
if [ "$(uname -s)" = "Darwin" ]; then
  for c in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$c" ] && { eval "$("$c" shellenv)"; break; }
  done
fi
case ":$PATH:" in *":$LOCAL_BIN:"*) : ;; *) PATH="$LOCAL_BIN:$PATH" ;; esac

# ---------------------------------------------------------------------------
# 1. Locate the declarative spec and load its ".syncthing" object.
# ---------------------------------------------------------------------------
SPEC_FILE="$SCRIPT_DIR/home/.chezmoidata/syncthing.json"
if [ ! -f "$SPEC_FILE" ] && command -v chezmoi >/dev/null 2>&1; then
  alt="$(chezmoi source-path 2>/dev/null)/.chezmoidata/syncthing.json"
  [ -f "$alt" ] && SPEC_FILE="$alt"
fi

# ---------------------------------------------------------------------------
# 2. Dependencies (needed both to download and to talk to the REST API).
# ---------------------------------------------------------------------------
for bin in jq curl; do
  command -v "$bin" >/dev/null 2>&1 || die "'$bin' not found (pinned in mise.toml: run 'task deps')."
done

# ---------------------------------------------------------------------------
# 3. Install Syncthing (official GitHub release binary) if it isn't on PATH.
# ---------------------------------------------------------------------------
install_syncthing() {
  command -v syncthing >/dev/null 2>&1 && { info "Syncthing already installed: $(command -v syncthing)"; return 0; }
  if [ "$NO_INSTALL" -eq 1 ]; then
    warn "syncthing not found and --no-install set; skipping install."
    return 1
  fi

  local os ext arch ver asset url tmp bin
  case "$(uname -s)" in
    Darwin) os=macos; ext=zip ;;
    Linux)  os=linux; ext=tar.gz ;;
    *) die "Unsupported OS for auto-install: $(uname -s). Install syncthing manually." ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64)       arch=amd64 ;;
    arm64|aarch64)      arch=arm64 ;;
    armv7l|armv6l|arm)  arch=arm ;;
    i386|i686)          arch=386 ;;
    *) die "Unsupported CPU arch for auto-install: $(uname -m). Install syncthing manually." ;;
  esac

  ver="$(curl -fsSL https://api.github.com/repos/syncthing/syncthing/releases/latest | jq -r '.tag_name')"
  [ -n "$ver" ] && [ "$ver" != "null" ] || die "Could not determine the latest Syncthing version from GitHub."
  asset="syncthing-${os}-${arch}-${ver}.${ext}"
  url="https://github.com/syncthing/syncthing/releases/download/${ver}/${asset}"

  info "Installing Syncthing ${ver} (${os}-${arch}) into ${LOCAL_BIN} ..."
  tmp="$(mktemp -d)"
  if ! curl -fsSL "$url" -o "$tmp/$asset"; then rm -rf "$tmp"; die "Download failed: $url"; fi
  case "$ext" in
    zip)
      command -v unzip >/dev/null 2>&1 || { rm -rf "$tmp"; die "'unzip' not found (needed to unpack the macOS archive)."; }
      unzip -q -o "$tmp/$asset" -d "$tmp" ;;
    tar.gz)
      tar -xzf "$tmp/$asset" -C "$tmp" ;;
  esac
  bin="$(find "$tmp" -type f -name syncthing | head -n1)"
  [ -n "$bin" ] || { rm -rf "$tmp"; die "syncthing binary not found inside $asset."; }
  mkdir -p "$LOCAL_BIN"
  install -m 0755 "$bin" "$LOCAL_BIN/syncthing"
  rm -rf "$tmp"
  hash -r 2>/dev/null || true
  info "Installed: $("$LOCAL_BIN/syncthing" --version 2>/dev/null | head -n1)"
  case ":$PATH:" in
    *":$LOCAL_BIN:"*) : ;;
    *) warn "Add ${LOCAL_BIN} to your PATH to use 'syncthing' directly." ;;
  esac
}

install_syncthing || true

if [ "$INSTALL_ONLY" -eq 1 ]; then
  command -v syncthing >/dev/null 2>&1 && info "Install-only mode: done." || warn "syncthing is not installed."
  exit 0
fi

command -v syncthing >/dev/null 2>&1 || { warn "syncthing not available; cannot configure. Re-run without --no-install."; exit 0; }

# ---------------------------------------------------------------------------
# 4. Load the spec; bail early if there is nothing to reconcile.
# ---------------------------------------------------------------------------
if [ ! -f "$SPEC_FILE" ]; then
  warn "Spec file not found ($SPEC_FILE) — Syncthing is installed but there is nothing to reconcile."
  exit 0
fi
SPEC="$(jq -c '.syncthing // {}' "$SPEC_FILE")"
if [ "$(printf '%s' "$SPEC" | jq -r '((.devices // [])|length) + ((.folders // [])|length) + ((.options // {})|length)')" = "0" ]; then
  info "Syncthing spec is empty — nothing to reconcile. Add devices/folders with: task syncthing:edit"
  exit 0
fi

# ---------------------------------------------------------------------------
# 5. Ensure the service is running (service manager if present, else launch it).
# ---------------------------------------------------------------------------
if ! pgrep -x syncthing >/dev/null 2>&1; then
  info "Starting Syncthing..."
  started=0
  case "$(uname -s)" in
    Darwin)
      if command -v brew >/dev/null 2>&1 && brew services list 2>/dev/null | grep -q '^syncthing'; then
        brew services start syncthing >/dev/null 2>&1 && started=1 || true
      fi
      ;;
    Linux)
      if command -v systemctl >/dev/null 2>&1 && \
         systemctl --user list-unit-files 2>/dev/null | grep -q '^syncthing\.service'; then
        systemctl --user enable --now syncthing.service >/dev/null 2>&1 && started=1 || true
      fi
      ;;
  esac
  if [ "$started" -ne 1 ]; then
    # Universal fallback: launch it ourselves in the background.
    if syncthing serve --help >/dev/null 2>&1; then
      nohup syncthing serve --no-browser >/dev/null 2>&1 &
    else
      nohup syncthing -no-browser >/dev/null 2>&1 &
    fi
    disown 2>/dev/null || true
  fi
fi

# ---------------------------------------------------------------------------
# 6. Resolve the local GUI address + API key.
# ---------------------------------------------------------------------------
ADDR="$(syncthing cli config gui raw-address get 2>/dev/null | tr -d '[:space:]' || true)"
[ -n "$ADDR" ] || ADDR="127.0.0.1:8384"
ADDR="${ADDR/0.0.0.0/127.0.0.1}"   # wildcard bind -> talk to localhost
ADDR="${ADDR/#:/127.0.0.1:}"       # ":8384" -> "127.0.0.1:8384"
BASE="http://${ADDR}"

# Wait for the REST API (unauthenticated health endpoint).
ready=0
for _ in $(seq 1 30); do
  if curl -fsS -m 2 "${BASE}/rest/noauth/health" >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  warn "Syncthing REST API not reachable at ${BASE}."
  warn "Start it (macOS: 'brew services start syncthing'; Linux: 'systemctl --user start syncthing';"
  warn "or run 'syncthing' once), then re-run: ./syncthing-setup.sh"
  exit 0
fi

APIKEY="$(syncthing cli config gui apikey get 2>/dev/null | tr -d '[:space:]' || true)"
if [ -z "$APIKEY" ]; then
  # Fall back to parsing config.xml (same locations decommission.sh scans).
  for c in \
      "${STHOMEDIR:-}/config.xml" \
      "$HOME/Library/Application Support/Syncthing/config.xml" \
      "$HOME/.local/state/syncthing/config.xml" \
      "$HOME/.config/syncthing/config.xml"; do
    [ -n "$c" ] && [ -f "$c" ] || continue
    if command -v xmllint >/dev/null 2>&1; then
      APIKEY="$(xmllint --xpath 'string(//gui/apikey)' "$c" 2>/dev/null || true)"
    else
      APIKEY="$(sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "$c" | head -n1)"
    fi
    [ -n "$APIKEY" ] && break
  done
fi
[ -n "$APIKEY" ] || { warn "Could not determine Syncthing API key; skipping."; exit 0; }

# ---------------------------------------------------------------------------
# 7. REST helpers.
# ---------------------------------------------------------------------------
api() {  # METHOD PATH [JSON-BODY]
  local method="$1" path="$2" data="${3:-}"
  if [ -n "$data" ]; then
    curl -fsS -m 15 -X "$method" \
      -H "X-API-Key: ${APIKEY}" -H 'Content-Type: application/json' \
      --data "$data" "${BASE}${path}"
  else
    curl -fsS -m 15 -X "$method" -H "X-API-Key: ${APIKEY}" "${BASE}${path}"
  fi
}
# GET that tolerates 404 (item does not exist yet) — echoes body only on 200.
api_get_opt() {
  local path="$1" tmp code
  tmp="$(mktemp)"
  code="$(curl -sS -m 15 -o "$tmp" -w '%{http_code}' -H "X-API-Key: ${APIKEY}" "${BASE}${path}" 2>/dev/null || echo 000)"
  [ "$code" = "200" ] && cat "$tmp"
  rm -f "$tmp"
}
# Resolve a spec device name (or raw id) to its device ID.
resolve_id() {
  printf '%s' "$SPEC" | jq -r --arg k "$1" \
    'first(.devices[]? | select(.name==$k or .id==$k) | .id) // $k'
}

MYID="$(api GET /rest/system/status | jq -r '.myID')"

# ---------------------------------------------------------------------------
# 8. Global options (deep-merged onto the current options).
# ---------------------------------------------------------------------------
SPEC_OPTS="$(printf '%s' "$SPEC" | jq -c '.options // {}')"
if [ "$SPEC_OPTS" != "{}" ]; then
  merged="$(api GET /rest/config/options | jq --argjson o "$SPEC_OPTS" '. * $o')"
  api PUT /rest/config/options "$merged" >/dev/null
  info "options: applied ${SPEC_OPTS}"
fi

# ---------------------------------------------------------------------------
# 9. Devices (peers). PUT is create-or-replace; we merge onto defaults/existing.
# ---------------------------------------------------------------------------
while IFS= read -r dev; do
  [ -n "$dev" ] || continue
  id="$(printf '%s' "$dev" | jq -r '.id // empty')"
  name="$(printf '%s' "$dev" | jq -r '.name // .id')"
  [ -n "$id" ] || { warn "device with no id in spec; skipping"; continue; }
  base="$(api_get_opt "/rest/config/devices/${id}")"
  [ -n "$base" ] || base="$(api GET /rest/config/defaults/device)"
  payload="$(printf '%s' "$base" | jq --arg id "$id" --arg name "$name" '.deviceID=$id | .name=$name')"
  api PUT "/rest/config/devices/${id}" "$payload" >/dev/null
  info "device: ${name} (${id%%-*}…)"
done < <(printf '%s' "$SPEC" | jq -c '.devices[]? // empty')

# ---------------------------------------------------------------------------
# 10. Folders. Always shared with this machine plus each resolved peer.
# ---------------------------------------------------------------------------
while IFS= read -r f; do
  [ -n "$f" ] || continue
  fid="$(printf '%s' "$f" | jq -r '.id // empty')"
  label="$(printf '%s' "$f" | jq -r '.label // .id')"
  fpath="$(printf '%s' "$f" | jq -r '.path // empty')"
  ftype="$(printf '%s' "$f" | jq -r '.type // "sendreceive"')"
  [ -n "$fid" ]   || { warn "folder with no id in spec; skipping"; continue; }
  [ -n "$fpath" ] || { warn "folder '${fid}' has no path; skipping"; continue; }
  case "$fpath" in
    "~")   fpath="$HOME" ;;
    "~/"*) fpath="$HOME/${fpath#\~/}" ;;
  esac

  dev_json="$(jq -n --arg my "$MYID" '[{deviceID:$my}]')"
  while IFS= read -r nm; do
    [ -n "$nm" ] || continue
    did="$(resolve_id "$nm")"
    dev_json="$(printf '%s' "$dev_json" | jq --arg d "$did" '(. + [{deviceID:$d}]) | unique_by(.deviceID)')"
  done < <(printf '%s' "$f" | jq -r '.devices[]? // empty')

  base="$(api_get_opt "/rest/config/folders/${fid}")"
  [ -n "$base" ] || base="$(api GET /rest/config/defaults/folder)"
  payload="$(printf '%s' "$base" | jq \
    --arg id "$fid" --arg label "$label" --arg path "$fpath" --arg type "$ftype" --argjson devs "$dev_json" \
    '.id=$id | .label=$label | .path=$path | .type=$type | .devices=$devs')"
  api PUT "/rest/config/folders/${fid}" "$payload" >/dev/null
  mkdir -p "$fpath" 2>/dev/null || true   # so Syncthing doesn't flag a missing path
  info "folder: ${label} -> ${fpath} [${ftype}]"
done < <(printf '%s' "$SPEC" | jq -c '.folders[]? // empty')

# ---------------------------------------------------------------------------
# 11. Summary.
# ---------------------------------------------------------------------------
info "Syncthing configured."
printf '    This device ID: %s\n' "$MYID"
printf '    Web UI:         %s\n' "$BASE"
info "Share the ID above with peers so they can add this machine."
