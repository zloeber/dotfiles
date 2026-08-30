#!/usr/bin/env bash
#
# backup-identity.sh — collect your PORTABLE identity (keys, tokens, cloud &
# dev credentials) into a single age-encrypted archive to carry to a new Mac.
# macOS oriented, but works anywhere with bash + tar + age.
#
# This is the companion to decommission.sh: run it BEFORE you wipe.
#
#   ┌─ what this DOES capture ─────────────────────────────────────────────┐
#   │ the secrets that do NOT (and should not) live in your chezmoi git     │
#   │ repo: the age identity, SSH/GPG keys, and cloud/dev/AI credentials.   │
#   └───────────────────────────────────────────────────────────────────────┘
#   Your dotfiles/config are already reproducible from the chezmoi repo, so
#   they are intentionally NOT duplicated here. Browser profiles / app data /
#   shell history are also excluded (re-fetched by signing in on the new Mac).
#
# ─────────────────────────────────────────────────────────────────────────────
#  SECURITY MODEL
#  • Output is encrypted with age using a PASSPHRASE by default (age -p).
#    Passphrase (not --recipient) is the default on purpose: your age key is
#    INSIDE this archive, so encrypting to it would lock you out of your own
#    backup. Use a strong, memorable passphrase from your password manager.
#  • The archive holds live secrets. Move it OFF this Mac immediately (USB, or
#    scp to the new machine) and delete the local copy. Do NOT commit it.
#  • Read-only with respect to your system: it only reads and writes the one
#    output file. It never deletes or modifies anything else.
# ─────────────────────────────────────────────────────────────────────────────
#
# USAGE
#   ./backup-identity.sh                 # create ~/identity-backup-<host>-<date>.tar.age
#   ./backup-identity.sh --list          # preview what WOULD be included (no archive)
#   ./backup-identity.sh --list -v       # ... also show absent candidates
#   ./backup-identity.sh --out /Volumes/USB/id.tar.age
#   ./backup-identity.sh --include "$HOME/Documents/Vault.kdbx"   # add extra paths
#   ./backup-identity.sh --recipient age1xxxx   # encrypt to a key you hold ELSEWHERE
#
# RESTORE (on the new Mac)
#   age -d identity-backup-*.tar.age | tar -xzf - -C "$HOME"
#   # (age prompts for the passphrase; for --recipient use: age -d -i key.txt …)

set -u
set -o pipefail
umask 077   # keep any output private by default

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
OUT=""
RECIPIENT=""
LIST_ONLY=0
VERBOSE=0
EXTRA_INCLUDES=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    --out)        OUT="${2:-}"; shift 2 ;;
    --recipient)  RECIPIENT="${2:-}"; shift 2 ;;
    --include)    EXTRA_INCLUDES+=("${2:-}"); shift 2 ;;
    --list)       LIST_ONLY=1; shift ;;
    --verbose|-v) VERBOSE=1; shift ;;
    --help|-h)    usage; exit 0 ;;
    *) printf 'Unknown option: %s\n\n' "$1" >&2; usage; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
blue=$'\033[1;34m'; yellow=$'\033[1;33m'; red=$'\033[1;31m'; reset=$'\033[0m'
section() { printf '\n%s==> %s%s\n' "$blue" "$*" "$reset"; }
info()    { printf '    %s\n' "$*"; }
warn()    { printf '%s!!  %s%s\n' "$yellow" "$*" "$reset" >&2; }
die()     { printf '%s!!  %s%s\n' "$red" "$*" "$reset" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Candidate identity paths (absolute). Only the ones that exist get archived.
# Mirrors the credential categories in decommission.sh so a backup captures
# exactly what a wipe would destroy.
# ---------------------------------------------------------------------------
CANDIDATES=(
  # Keys & encryption identities
  "$HOME/.ssh"
  "$HOME/.gnupg"
  "$HOME/.config/age"
  "$HOME/.config/chezmoi/key.txt"     # the age identity that decrypts this repo
  "$HOME/.netrc"

  # Cloud provider credentials
  "$HOME/.aws"
  "$HOME/.config/gcloud"
  "$HOME/.azure"
  "$HOME/.kube"
  "$HOME/.config/doctl"
  "$HOME/.terraform.d"
  "$HOME/.terraformrc"
  "$HOME/.vault-token"
  "$HOME/.databrickscfg"
  "$HOME/.config/rclone"              # cloud-storage remotes (often overlooked)

  # Developer tokens & registries
  "$HOME/.config/gh"
  "$HOME/.config/glab-cli"
  "$HOME/.docker/config.json"
  "$HOME/.npmrc"
  "$HOME/.yarnrc"
  "$HOME/.yarnrc.yml"
  "$HOME/.pypirc"
  "$HOME/.cargo/credentials.toml"
  "$HOME/.gem/credentials"
  "$HOME/.git-credentials"
  "$HOME/.config/git/credentials"

  # AI / agent credentials
  "$HOME/.claude"                     # may be large (projects/history) — trim if unwanted
  "$HOME/.config/claude"
  "$HOME/.config/anthropic"
  "$HOME/.codex"
  "$HOME/.config/openai"
  "$HOME/.config/secretzero"
  "$HOME/.config/metagit"
  "$HOME/.keeper"
)

# Append any user-supplied extra paths.
if [ "${#EXTRA_INCLUDES[@]}" -gt 0 ]; then
  for extra in "${EXTRA_INCLUDES[@]}"; do
    [ -n "$extra" ] && CANDIDATES+=("$extra")
  done
fi

# ---------------------------------------------------------------------------
# Resolve which candidates exist, as $HOME-relative paths (portable restore).
# ---------------------------------------------------------------------------
REL=()          # $HOME-relative paths that exist and will be archived
HOME_PREFIX="$HOME/"

section "Scanning for identity material"
for abs in "${CANDIDATES[@]}"; do
  if [ -e "$abs" ] || [ -L "$abs" ]; then
    case "$abs" in
      "$HOME_PREFIX"*)
        rel="${abs#"$HOME_PREFIX"}"
        REL+=("$rel")
        if [ "$LIST_ONLY" -eq 1 ]; then
          printf '    [include] %-40s (%s)\n' "$rel" "$(du -sh "$abs" 2>/dev/null | cut -f1)"
        else
          printf '    [include] %s\n' "$rel"
        fi
        ;;
      *)
        warn "Skipping '$abs' — outside \$HOME, so restore would not be portable."
        warn "  (copy it by hand, or symlink it under \$HOME first)"
        ;;
    esac
  elif [ "$VERBOSE" -eq 1 ]; then
    printf '    [absent]  %s\n' "$abs"
  fi
done

if [ "${#REL[@]}" -eq 0 ]; then
  die "No identity material found — nothing to back up."
fi

# ---------------------------------------------------------------------------
# List-only mode stops here.
# ---------------------------------------------------------------------------
if [ "$LIST_ONLY" -eq 1 ]; then
  section "Summary"
  info "${#REL[@]} path(s) would be archived. Re-run without --list to create it."
  exit 0
fi

# ---------------------------------------------------------------------------
# Preconditions for actually building the archive.
# ---------------------------------------------------------------------------
command -v age >/dev/null 2>&1 || die "age is not installed (it is pinned in this repo's mise.toml: run 'mise install')."
command -v tar >/dev/null 2>&1 || die "tar is not available."

HOST="$(scutil --get ComputerName 2>/dev/null || hostname -s 2>/dev/null || hostname)"
STAMP="$(date +%Y%m%d-%H%M%S)"
if [ -z "$OUT" ]; then
  # Spaces in ComputerName → make a filesystem-friendly slug.
  slug="$(printf '%s' "$HOST" | tr ' /' '--')"
  OUT="$HOME/identity-backup-${slug}-${STAMP}.tar.age"
fi

if [ -e "$OUT" ]; then
  die "Refusing to overwrite existing file: $OUT"
fi

# Guard against writing the secret-laden archive into the git working tree.
case "$OUT" in
  "$SCRIPT_DIR"|"$SCRIPT_DIR"/*)
    die "Refusing to write the archive inside the repo ($SCRIPT_DIR). Choose --out elsewhere." ;;
esac

# ---------------------------------------------------------------------------
# Build: tar (relative to $HOME) → age. Fail if any stage fails (pipefail).
# ---------------------------------------------------------------------------
section "Creating encrypted archive"
info "Output: $OUT"
if [ -n "$RECIPIENT" ]; then
  info "Encryption: public-key recipient ($RECIPIENT)"
  warn "Reminder: do NOT use your repo's own age key as the recipient — it is"
  warn "  inside this archive, which would make the backup undecryptable."
  if tar -czf - -C "$HOME" -- "${REL[@]}" | age -r "$RECIPIENT" -o "$OUT"; then
    :
  else
    rm -f "$OUT"; die "Archive creation failed; partial output removed."
  fi
else
  info "Encryption: passphrase (age -p) — you will be prompted now."
  if tar -czf - -C "$HOME" -- "${REL[@]}" | age -p -o "$OUT"; then
    :
  else
    rm -f "$OUT"; die "Archive creation failed; partial output removed."
  fi
fi

chmod 600 "$OUT" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Summary + next steps
# ---------------------------------------------------------------------------
section "Done"
info "Archived ${#REL[@]} path(s) → $OUT"
info "Size: $(du -h "$OUT" 2>/dev/null | cut -f1)"
cat <<NEXT

Next steps:
  1. Verify it decrypts (before you rely on it!):
       age -d "$OUT" | tar -tzf - | head
  2. Move it OFF this Mac now (USB stick, or copy to the new machine):
       scp "$OUT" you@new-mac:~/
  3. On the new Mac, restore into your home directory:
       age -d "$OUT" | tar -xzf - -C "\$HOME"
  4. Delete the local copy once it is safely transferred:
       rm -P "$OUT"    # (plain rm is fine on an encrypted APFS/FileVault volume)

Then, and only then, run ./decommission.sh on this machine.
NEXT
