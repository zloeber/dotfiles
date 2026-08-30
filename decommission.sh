#!/usr/bin/env bash
#
# decommission.sh — wipe your identity from THIS Mac before handing it off,
# selling it, or returning it. macOS only.
#
# It quits apps, gracefully stops Syncthing (and removes its synced folders),
# deletes private keys / tokens / cloud credentials, and removes browser +
# application profiles (which logs you out of Firefox, Edge, Brave, Chrome,
# Safari, Signal, Teams, Slack, VS Code, Cursor, Docker, …).
#
# ─────────────────────────────────────────────────────────────────────────────
#  SAFETY MODEL
#  • DRY RUN BY DEFAULT: with no flags it only *prints* what it would delete.
#  • Pass --execute to actually delete. You must then type a confirmation
#    phrase (unless --yes is also given).
#  • Each removal is best-effort and guarded by an existence check, so a
#    missing path never aborts the run.
# ─────────────────────────────────────────────────────────────────────────────
#
# USAGE
#   ./decommission.sh                 # dry run — shows everything, deletes nothing
#   ./decommission.sh --verbose       # dry run, also list paths that are absent
#   ./decommission.sh --execute       # real wipe (prompts for confirmation)
#   ./decommission.sh --execute --yes # real wipe, no prompt (careful!)
#
# EXTRA (opt-in) SWITCHES
#   --reset-keychain    also delete the login Keychain (all saved passwords/
#                       certs). Extremely destructive; breaks the current login
#                       session. Only meaningful with --execute.
#   --remove-dotfiles   also delete the chezmoi source + state at the very end
#                       (this repo, ~/.config/chezmoi, caches). Run last.
#
# NOTE ON SECURE ERASURE
#   On an Apple-Silicon / APFS SSD, `rm` does not forensically shred data, and
#   `srm` no longer exists. If FileVault is ON, your data is already encrypted
#   at rest; the definitive wipe is macOS "Erase All Content and Settings"
#   (System Settings ▸ General ▸ Transfer or Reset), which destroys the
#   encryption keys. This script handles the *identity/logout* layer; see the
#   manual checklist it prints at the end for the final hardware handoff steps.

set -u
set -o pipefail

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
DRY_RUN=1
ASSUME_YES=0
RESET_KEYCHAIN=0
REMOVE_DOTFILES=0
VERBOSE=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  # Print the leading comment banner (everything from line 2 up to, but not
  # including, the first line of actual code), with the leading "# " stripped.
  awk '
    NR == 1        { next }              # skip the shebang
    /^#/           { sub(/^# ?/, ""); print; next }
    /^[[:space:]]*$/ { print; next }     # keep blank separators inside the banner
    { exit }                             # first real code line ⇒ stop
  ' "${BASH_SOURCE[0]}"
}

for arg in "$@"; do
  case "$arg" in
    --execute)         DRY_RUN=0 ;;
    --yes|-y)          ASSUME_YES=1 ;;
    --reset-keychain)  RESET_KEYCHAIN=1 ;;
    --remove-dotfiles) REMOVE_DOTFILES=1 ;;
    --verbose|-v)      VERBOSE=1 ;;
    --help|-h)         usage; exit 0 ;;
    *) printf 'Unknown option: %s\n\n' "$arg" >&2; usage; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------
if [ "$(uname -s)" != "Darwin" ]; then
  printf 'This script only runs on macOS.\n' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
bold=$'\033[1m'; blue=$'\033[1;34m'; yellow=$'\033[1;33m'; red=$'\033[1;31m'; reset=$'\033[0m'
section() { printf '\n%s==> %s%s\n' "$blue" "$*" "$reset"; }
info()    { printf '    %s\n' "$*"; }
warn()    { printf '%s!!  %s%s\n' "$yellow" "$*" "$reset" >&2; }

REMOVED=0
ABSENT=0

# Remove a single path (file, dir, or symlink). Honours DRY_RUN.
nuke() {
  local target="$1"
  if [ -e "$target" ] || [ -L "$target" ]; then
    REMOVED=$((REMOVED + 1))
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '    [dry-run] %s\n' "$target"
    elif rm -rf -- "$target" 2>/dev/null; then
      printf '    [removed] %s\n' "$target"
    else
      printf '    %s[FAILED]%s  %s\n' "$red" "$reset" "$target"
    fi
  else
    ABSENT=$((ABSENT + 1))
    [ "$VERBOSE" -eq 1 ] && printf '    [absent]  %s\n' "$target"
  fi
  return 0
}

# Nuke direct children of DIR whose name matches PATTERN (case-insensitive).
# Safe with spaces in paths (Library/Application Support/…). Never recurses
# past one level so we only match top-level app/data folders.
nuke_matches() {
  local dir="$1" pattern="$2" match
  [ -d "$dir" ] || return 0
  while IFS= read -r -d '' match; do
    nuke "$match"
  done < <(find "$dir" -maxdepth 1 -mindepth 1 -iname "$pattern" -print0 2>/dev/null)
  return 0
}

# Quit a GUI app (by its display name). Only acts when executing.
quit_app() {
  local app="$1"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '    [dry-run] would quit: %s\n' "$app"
  else
    osascript -e "quit app \"$app\"" >/dev/null 2>&1 || true
    printf '    [quit]    %s\n' "$app"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Syncthing helpers
# ---------------------------------------------------------------------------
SYNCTHING_CFG=""          # path to the discovered config.xml (empty if none)
SYNCTHING_FOLDERS=()      # synced folder paths parsed from that config

# Locate Syncthing's config.xml across the known macOS / XDG locations.
find_syncthing_config() {
  local c
  for c in \
      "${STHOMEDIR:-}/config.xml" \
      "$HOME/Library/Application Support/Syncthing/config.xml" \
      "$HOME/.config/syncthing/config.xml" \
      "$HOME/.local/state/syncthing/config.xml"; do
    if [ -n "$c" ] && [ -f "$c" ]; then
      printf '%s' "$c"
      return 0
    fi
  done
  return 1
}

# Parse <folder path="…"> values from config.xml into SYNCTHING_FOLDERS.
# Uses xmllint (ships with macOS) for space-safe extraction; falls back to grep.
read_syncthing_folders() {
  local cfg="$1" n i p
  SYNCTHING_FOLDERS=()
  [ -n "$cfg" ] && [ -f "$cfg" ] || return 0
  if command -v xmllint >/dev/null 2>&1; then
    n="$(xmllint --xpath 'count(//folder)' "$cfg" 2>/dev/null || echo 0)"
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    i=1
    while [ "$i" -le "$n" ]; do
      p="$(xmllint --xpath "string((//folder)[$i]/@path)" "$cfg" 2>/dev/null)"
      [ -n "$p" ] && SYNCTHING_FOLDERS+=("$p")
      i=$((i + 1))
    done
  else
    while IFS= read -r p; do
      [ -n "$p" ] && SYNCTHING_FOLDERS+=("$p")
    done < <(grep -o 'path="[^"]*"' "$cfg" 2>/dev/null | sed 's/^path="//; s/"$//')
  fi
  return 0
}

# Expand a leading ~ (Syncthing may store paths like "~/Sync"). The tilde here
# is matched/stripped as a literal string, so SC2088 (no expansion) is expected.
expand_tilde() {
  # shellcheck disable=SC2088
  case "$1" in
    "~")    printf '%s' "$HOME" ;;
    "~/"*)  printf '%s/%s' "$HOME" "${1#\~/}" ;;
    *)      printf '%s' "$1" ;;
  esac
}

# Refuse to auto-delete catastrophic targets (/, $HOME, non-absolute paths).
is_dangerous_path() {
  local p="$1"
  case "$p" in
    ""|"/"|"$HOME"|"$HOME/") return 0 ;;
  esac
  case "$p" in
    /*) return 1 ;;   # absolute → safe to consider
    *)  return 0 ;;   # relative/odd → treat as dangerous
  esac
}

# Gracefully stop Syncthing: REST-API shutdown first (lets it flush), then the
# brew service, launchd agents, and finally a direct signal as a backstop.
shutdown_syncthing() {
  local cfg="$1" apikey="" address="" lbl
  if [ -n "$cfg" ] && command -v xmllint >/dev/null 2>&1; then
    apikey="$(xmllint --xpath 'string(//gui/apikey)' "$cfg" 2>/dev/null || true)"
    address="$(xmllint --xpath 'string(//gui/address)' "$cfg" 2>/dev/null || true)"
  fi
  [ -n "$address" ] || address="127.0.0.1:8384"

  if [ "$DRY_RUN" -eq 1 ]; then
    info "[dry-run] would POST /rest/system/shutdown to ${address}, stop the brew"
    info "          service / launchd agent, then signal the syncthing process."
    return 0
  fi

  if [ -n "$apikey" ] && command -v curl >/dev/null 2>&1; then
    if curl -fsS -m 5 -X POST -H "X-API-Key: ${apikey}" \
         "http://${address}/rest/system/shutdown" >/dev/null 2>&1; then
      info "Requested graceful shutdown via REST API (${address})."
      sleep 2
    fi
  fi
  command -v brew >/dev/null 2>&1 && { brew services stop syncthing >/dev/null 2>&1 || true; }
  while IFS= read -r lbl; do
    [ -n "$lbl" ] && launchctl bootout "gui/$(id -u)/${lbl}" >/dev/null 2>&1 || true
  done < <(launchctl list 2>/dev/null | awk '/syncthing/ {print $3}')
  pkill -x syncthing >/dev/null 2>&1 || true   # exact name only — no collateral
  info "Syncthing stopped."
  return 0
}

# ---------------------------------------------------------------------------
# Banner + confirmation
# ---------------------------------------------------------------------------
COMPUTER_NAME="$(scutil --get ComputerName 2>/dev/null || hostname)"

printf '%s' "$bold"
cat <<BANNER
╔════════════════════════════════════════════════════════════════════╗
║  IDENTITY DECOMMISSION                                               ║
╚════════════════════════════════════════════════════════════════════╝
BANNER
printf '%s' "$reset"
info "Host:   ${COMPUTER_NAME}"
info "User:   ${USER:-$(id -un)}   Home: ${HOME}"
if [ "$DRY_RUN" -eq 1 ]; then
  printf '%sMode:   DRY RUN — nothing will be deleted. Re-run with --execute to wipe.%s\n' "$yellow" "$reset"
else
  printf '%sMode:   EXECUTE — this WILL permanently delete the items below.%s\n' "$red" "$reset"
fi
[ "$RESET_KEYCHAIN" -eq 1 ]  && warn "login Keychain will be DELETED (--reset-keychain)"
[ "$REMOVE_DOTFILES" -eq 1 ] && warn "chezmoi source + state will be DELETED (--remove-dotfiles)"

if [ "$DRY_RUN" -eq 0 ] && [ "$ASSUME_YES" -ne 1 ]; then
  printf '\n%sThis cannot be undone.%s Type %sERASE MY IDENTITY%s to continue: ' \
    "$red" "$reset" "$bold" "$reset"
  IFS= read -r reply
  if [ "$reply" != "ERASE MY IDENTITY" ]; then
    warn "Confirmation phrase did not match. Aborting — nothing was deleted."
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# 0. Quit apps first, so they don't rewrite their data on exit.
# ---------------------------------------------------------------------------
section "Quitting applications"
APPS=(
  "Firefox" "Microsoft Edge" "Brave Browser" "Google Chrome" "Safari"
  "Signal" "Microsoft Teams" "Slack" "Obsidian"
  "Visual Studio Code" "Cursor" "Zed" "Docker Desktop" "QSyncthingTray"
)
for app in "${APPS[@]}"; do
  quit_app "$app"
done
if [ "$DRY_RUN" -eq 0 ]; then
  # Best-effort backstop for anything that ignored the quit event.
  for proc in firefox "Microsoft Edge" "Brave Browser" "Google Chrome" \
              Signal "Microsoft Teams" Slack Obsidian "Code" "Cursor" "QSyncthingTray"; do
    killall "$proc" >/dev/null 2>&1 || true
  done
fi

# ---------------------------------------------------------------------------
# 0b. Syncthing — discover its folders (before we delete anything) and stop it
#     gracefully so it isn't mid-write when we remove data.
# ---------------------------------------------------------------------------
section "Syncthing (graceful shutdown)"
SYNCTHING_CFG="$(find_syncthing_config || true)"
if [ -n "$SYNCTHING_CFG" ]; then
  read_syncthing_folders "$SYNCTHING_CFG"
  info "Config: ${SYNCTHING_CFG}"
  info "Discovered ${#SYNCTHING_FOLDERS[@]} synced folder(s) (removed later, in step 6b)."
  shutdown_syncthing "$SYNCTHING_CFG"
else
  info "No Syncthing config found — nothing to shut down."
fi

# ---------------------------------------------------------------------------
# 1. SSH / GPG / age / chezmoi identity — the crown jewels.
# ---------------------------------------------------------------------------
section "Keys & encryption identities"
nuke "$HOME/.ssh"
nuke "$HOME/.gnupg"
nuke "$HOME/.config/age"
nuke "$HOME/.config/chezmoi/key.txt"   # the age identity this repo decrypts with
nuke "$HOME/.github_token"
nuke "$HOME/.netrc"

# ---------------------------------------------------------------------------
# 2. Cloud provider credentials.
# ---------------------------------------------------------------------------
section "Cloud provider credentials"
nuke "$HOME/.aws"
nuke "$HOME/.config/gcloud"
nuke "$HOME/.azure"
nuke "$HOME/.kube"
nuke "$HOME/.config/doctl"
nuke "$HOME/.terraform.d"
nuke "$HOME/.databrickscfg"

# ---------------------------------------------------------------------------
# 3. Developer tool tokens / registries.
# ---------------------------------------------------------------------------
section "Developer tokens & registries"
nuke "$HOME/.config/gh"                 # GitHub CLI auth
nuke "$HOME/.config/glab-cli"           # GitLab CLI auth
nuke "$HOME/.docker"                    # registry logins
nuke "$HOME/.npmrc"
nuke "$HOME/.yarnrc"
nuke "$HOME/.yarnrc.yml"
nuke "$HOME/.pypirc"
nuke "$HOME/.cargo/credentials"
nuke "$HOME/.cargo/credentials.toml"
nuke "$HOME/.gem/credentials"
nuke "$HOME/.git-credentials"
nuke "$HOME/.config/git/credentials"

# ---------------------------------------------------------------------------
# 4. AI / agent credentials.
# ---------------------------------------------------------------------------
section "AI & agent credentials"
nuke "$HOME/.claude"                    # Claude Code oauth + projects
nuke "$HOME/.config/claude"
nuke "$HOME/.config/anthropic"
nuke "$HOME/.codex"
nuke "$HOME/.config/openai"
nuke "$HOME/.config/secretzero"
nuke "$HOME/.config/metagit"            # this repo's metagit config holds tokens
nuke "$HOME/.keeper"
nuke "$HOME/.config/keepassxc"          # settings/recent-files (NOT your .kdbx vault)

# ---------------------------------------------------------------------------
# 5. Browsers — deleting the profile removes cookies/sessions ⇒ logs you out.
# ---------------------------------------------------------------------------
section "Browser profiles & caches"
APPSUP="$HOME/Library/Application Support"
CACHES="$HOME/Library/Caches"
nuke "$APPSUP/Firefox"
nuke "$CACHES/Firefox"
nuke "$APPSUP/Microsoft Edge"
nuke "$CACHES/Microsoft Edge"
nuke "$APPSUP/BraveSoftware"
nuke "$CACHES/BraveSoftware"
nuke "$APPSUP/Google/Chrome"
nuke "$CACHES/Google/Chrome"
# Safari is sandboxed — its data lives under Containers / Group Containers.
nuke "$HOME/Library/Safari"
nuke_matches "$HOME/Library/Containers"       "com.apple.Safari*"
nuke_matches "$HOME/Library/Group Containers" "*.com.apple.Safari*"

# ---------------------------------------------------------------------------
# 6. Desktop application data / sessions.
# ---------------------------------------------------------------------------
section "Application data & sessions"
nuke "$APPSUP/Signal"
nuke "$APPSUP/Microsoft/Teams"
nuke "$APPSUP/Slack"
nuke "$APPSUP/obsidian"
nuke "$APPSUP/Code"                     # VS Code (auth, sync, workspace state)
nuke "$HOME/.vscode"
nuke "$APPSUP/Cursor"
nuke "$HOME/.cursor"
nuke "$APPSUP/Zed"
nuke "$HOME/.config/zed"
# Microsoft / Docker shared data lives in Group Containers (bundle-id folders).
nuke_matches "$HOME/Library/Group Containers" "*microsoft*"
nuke_matches "$HOME/Library/Group Containers" "*docker*"
nuke_matches "$HOME/Library/Containers"       "*docker*"

# ---------------------------------------------------------------------------
# 6b. Syncthing — remove the synced folders discovered earlier, then wipe
#     Syncthing's own config/state/identity and the tray app. (Syncthing was
#     already stopped gracefully in step 0b.)
# ---------------------------------------------------------------------------
section "Syncthing synced folders & config"
if [ "${#SYNCTHING_FOLDERS[@]}" -gt 0 ]; then
  for raw in "${SYNCTHING_FOLDERS[@]}"; do
    p="$(expand_tilde "$raw")"
    if is_dangerous_path "$p"; then
      warn "Refusing to auto-delete unsafe synced path '${raw}' — remove it by hand if intended."
      continue
    fi
    nuke "$p"
  done
else
  info "No synced folders to remove."
fi
# Syncthing's config/state hold the device identity, API key, and folder list.
nuke "$HOME/Library/Application Support/Syncthing"
nuke "$HOME/.config/syncthing"
nuke "$HOME/.local/state/syncthing"
nuke_matches "$HOME/Library/Preferences"  "*yncthing*"   # QSyncthingTray plist(s)
nuke_matches "$HOME/Library/LaunchAgents" "*yncthing*"   # any syncthing launch agent

# ---------------------------------------------------------------------------
# 7. Shell history & assorted local history files.
# ---------------------------------------------------------------------------
section "Shell & tool history"
nuke "$HOME/.zsh_history"
nuke "$HOME/.zsh_sessions"
nuke "$HOME/.bash_history"
nuke "$HOME/.lesshst"
nuke "$HOME/.python_history"
nuke "$HOME/.node_repl_history"
nuke "$HOME/.wget-hsts"
nuke "$HOME/.viminfo"

# ---------------------------------------------------------------------------
# 8. Login Keychain (opt-in — nukes ALL saved passwords/certs).
# ---------------------------------------------------------------------------
if [ "$RESET_KEYCHAIN" -eq 1 ]; then
  section "Login Keychain (--reset-keychain)"
  if [ "$DRY_RUN" -eq 0 ]; then
    security lock-keychain "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null || true
  fi
  # Removing the Keychains folder wipes login.keychain-db and local items;
  # macOS recreates an empty login keychain on next unlock/login.
  nuke_matches "$HOME/Library/Keychains" "login.keychain*"
  nuke_matches "$HOME/Library/Keychains" "*.keychain-db"
else
  section "Login Keychain"
  info "Skipped (pass --reset-keychain to also wipe saved passwords/certs)."
fi

# ---------------------------------------------------------------------------
# 9. Remove the dotfiles repo + chezmoi state (opt-in, done LAST).
# ---------------------------------------------------------------------------
if [ "$REMOVE_DOTFILES" -eq 1 ]; then
  section "Dotfiles source & chezmoi state (--remove-dotfiles)"
  nuke "$HOME/.config/chezmoi"
  nuke "$HOME/.cache/chezmoi"
  nuke "$HOME/.local/share/chezmoi"
  # If this script itself lives somewhere other than the standard source dir,
  # remove that copy too (safe even while running — macOS keeps the open inode).
  case "$SCRIPT_DIR" in
    "$HOME/.local/share/chezmoi"|"$HOME/.local/share/chezmoi/"*) : ;;
    *) nuke "$SCRIPT_DIR" ;;
  esac
fi

# ---------------------------------------------------------------------------
# Summary + manual checklist
# ---------------------------------------------------------------------------
section "Summary"
if [ "$DRY_RUN" -eq 1 ]; then
  info "DRY RUN complete: ${REMOVED} item(s) would be removed, ${ABSENT} absent."
  info "Re-run with --execute to perform the wipe."
else
  info "Wipe complete: ${REMOVED} item(s) removed, ${ABSENT} absent."
fi

cat <<'CHECKLIST'

────────────────────────────────────────────────────────────────────────────
 MANUAL STEPS (this script cannot / should not do these for you)
────────────────────────────────────────────────────────────────────────────
 1. Revoke tokens server-side (they may still be valid even though the local
    copies are gone): GitHub/GitLab PATs & SSH keys, cloud IAM keys, Anthropic
    /OpenAI API keys, npm/PyPI tokens.
 2. System Settings ▸ [your name]: Sign out of Apple ID / iCloud.
 3. Turn OFF Find My Mac (disables Activation Lock so the next owner can set up).
 4. Sign out of iMessage & FaceTime (Messages ▸ Settings, FaceTime ▸ Settings).
 5. Deauthorize this Mac in Music/TV (Account ▸ Authorizations ▸ Deauthorize).
 6. Remove any MDM / work profile (Settings ▸ Device Management) if applicable.
 7. Empty the Trash.
 8. FINAL WIPE: reboot to Recovery (or Settings ▸ General ▸ Transfer or Reset ▸
    Erase All Content and Settings). With FileVault on, this destroys the disk
    encryption keys and is the only forensically complete erase.
────────────────────────────────────────────────────────────────────────────
CHECKLIST
