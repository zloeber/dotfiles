#!/usr/bin/env bash
#
# bundle-identity.sh — copy the MINIMAL secrets needed to bootstrap a new
# machine into a folder (identity-bundle/) that rides along with this repo. Put
# the whole repo on a USB stick, carry it to the new box, and run ./install.sh
# there — it restores this bundle before applying your dotfiles.
#
# By default the bundle is PLAINTEXT (fast, no passphrase to remember). Pass
# --passphrase to instead write a single age-passphrase-encrypted archive
# (bundle.tar.age); ./install.sh decrypts it on restore, prompting for the
# passphrase. Use encryption if the stick might leave your physical control.
#
# This is the deliberately-small, physical-transport counterpart to
# backup-identity.sh (which makes an age-encrypted archive of EVERYTHING). Use
# this when you just want the crown jewels on a stick you keep in your pocket.
#
#   ┌─ what this bundles ─────────────────────────────────────────────────────┐
#   │  • the age identity   ~/.config/chezmoi/key.txt   -> age/key.txt         │
#   │      (this file holds both the private key AND its public recipient,     │
#   │       so "age private/public keys" are both captured here)              │
#   │  • the whole           ~/.ssh/                     -> ssh/               │
#   │  • home-root tokens    ~/<glob *token*.*>          -> home-tokens/       │
#   └───────────────────────────────────────────────────────────────────────┘
#
# On restore, ./install.sh auto-restores ONLY the age identity — that's the key
# that lets chezmoi decrypt your real, checked-in secrets. The ~/.ssh and token
# copies are a "just in case" safety net and are restored only on demand
# (install.sh --with-ssh / --with-tokens / --all).
#
# ─────────────────────────────────────────────────────────────────────────────
#  SECURITY MODEL
#  • Default is PLAINTEXT — anyone holding the USB stick holds your keys. The
#    folder is git-ignored (see .gitignore: /identity-bundle/) so it is never
#    committed, and this script refuses to write it into a git-tracked path.
#  • --passphrase encrypts the contents into bundle.tar.age with age -p, so the
#    stick alone is useless without the passphrase (only MANIFEST.txt stays
#    plaintext — it holds no secrets). Use a strong passphrase you can recall.
#  • The folder + its files are chmod 700/600. Keep the stick physically
#    secure, and delete the bundle once the new machine is set up.
#  • Read-only w.r.t. your system: it only reads secrets and writes the bundle.
# ─────────────────────────────────────────────────────────────────────────────
#
# USAGE
#   ./bundle-identity.sh                 # create ./identity-bundle (plaintext)
#   ./bundle-identity.sh --passphrase    # encrypt contents into bundle.tar.age
#   ./bundle-identity.sh --list          # preview what WOULD be copied (no writes)
#   ./bundle-identity.sh --out /Volumes/USB/identity-bundle
#   ./bundle-identity.sh --force         # overwrite an existing bundle folder
#
# RESTORE
#   ./install.sh    # on the new machine — restores this bundle, then sets up

set -u
set -o pipefail
umask 077   # anything we create is private by default

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
OUT=""
LIST_ONLY=0
FORCE=0
ENCRYPT=0

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
    --out)     OUT="${2:-}"; shift 2 ;;
    --list)    LIST_ONLY=1; shift ;;
    --force|-f) FORCE=1; shift ;;
    --passphrase|--encrypt|-p) ENCRYPT=1; shift ;;
    --help|-h) usage; exit 0 ;;
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
# Sources. AGE_KEY is a single file; SSH_DIR is a directory copied wholesale;
# home-root tokens are discovered by the *token*.* glob (case-insensitive).
# ---------------------------------------------------------------------------
AGE_KEY="$HOME/.config/chezmoi/key.txt"
SSH_DIR="$HOME/.ssh"

TOKENS=()
while IFS= read -r -d '' f; do
  TOKENS+=("$f")
done < <(find "$HOME" -maxdepth 1 -type f -iname '*token*.*' -print0 2>/dev/null)

DEST="${OUT:-$SCRIPT_DIR/identity-bundle}"

# ---------------------------------------------------------------------------
# Preview what will be copied. Bail early if there is genuinely nothing.
# ---------------------------------------------------------------------------
section "Scanning for identity material"
found=0
if [ -f "$AGE_KEY" ]; then info "[include] age identity   $AGE_KEY"; found=1
else                        warn "age identity not found at $AGE_KEY"; fi
if [ -d "$SSH_DIR" ]; then  info "[include] ssh directory  $SSH_DIR/"; found=1
else                        warn "no ~/.ssh directory found"; fi
if [ "${#TOKENS[@]}" -gt 0 ]; then
  for t in "${TOKENS[@]}"; do info "[include] home token    $t"; done
  found=1
else
  info "[absent]  no home-root files match *token*.*"
fi
[ "$found" -eq 1 ] || die "Nothing to bundle — no age key, ~/.ssh, or *token*.* files found."

info ""
info "Destination: $DEST"
if [ "$ENCRYPT" -eq 1 ]; then
  info "Mode:        encrypted (age -p) -> $DEST/bundle.tar.age"
else
  info "Mode:        plaintext"
fi

if [ "$LIST_ONLY" -eq 1 ]; then
  section "Summary"
  info "Re-run without --list to create the bundle."
  exit 0
fi

# age is only needed when encrypting; check before we do any work.
if [ "$ENCRYPT" -eq 1 ]; then
  command -v age >/dev/null 2>&1 || die "age is not installed (pinned in mise.toml: run 'mise install' or 'task deps')."
fi

# ---------------------------------------------------------------------------
# Guard: never write the plaintext bundle into a git-tracked location.
# ---------------------------------------------------------------------------
if git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # git accepts absolute paths inside the worktree for both checks below.
  if git -C "$SCRIPT_DIR" ls-files --error-unmatch -- "$DEST" >/dev/null 2>&1; then
    die "Refusing to write into a git-tracked path ($DEST). It must stay untracked."
  fi
  # Probe a path UNDER the destination: a trailing-slash gitignore pattern
  # (e.g. /identity-bundle/) only matches a path git already knows is a
  # directory, so checking the not-yet-created dir itself would false-negative.
  if ! git -C "$SCRIPT_DIR" check-ignore -q "$DEST/.probe" 2>/dev/null; then
    warn "Heads up: $DEST is not covered by .gitignore. Add '/identity-bundle/' there so"
    warn "  this plaintext bundle can never be accidentally committed."
  fi
fi

# ---------------------------------------------------------------------------
# Build the bundle.
# ---------------------------------------------------------------------------
if [ -e "$DEST" ]; then
  if [ "$FORCE" -eq 1 ]; then
    warn "Overwriting existing bundle at $DEST (--force)."
    rm -rf -- "$DEST"
  else
    die "Bundle already exists: $DEST  (use --force to overwrite, or --out for a new path)."
  fi
fi

section "Writing bundle"
mkdir -p "$DEST"
chmod 700 "$DEST"

# When encrypting we stage the tree in a working dir, then tar+age it into
# $DEST and remove the plaintext. On any failure, scrub the plaintext staging
# so we never leave decrypted secrets lying around.
if [ "$ENCRYPT" -eq 1 ]; then
  STAGE="$DEST/.stage"
  trap 'rm -rf -- "$STAGE"' EXIT
else
  STAGE="$DEST"
fi
mkdir -p "$STAGE"
chmod 700 "$STAGE"

COMPONENTS=()   # top-level names to archive (only those that exist)

if [ -f "$AGE_KEY" ]; then
  mkdir -p "$STAGE/age"
  cp -p "$AGE_KEY" "$STAGE/age/key.txt"
  chmod 600 "$STAGE/age/key.txt"
  COMPONENTS+=("age")
  info "age/key.txt"
fi

if [ -d "$SSH_DIR" ]; then
  # Mirror ~/.ssh preserving modes, but skip sockets (live ssh-agent endpoints
  # under ~/.ssh/agent are runtime junk that cp would only warn about).
  mkdir -p "$STAGE/ssh"
  while IFS= read -r -d '' item; do
    rel="${item#"$SSH_DIR"/}"
    if [ -d "$item" ]; then
      mkdir -p "$STAGE/ssh/$rel"
    else
      mkdir -p "$STAGE/ssh/$(dirname "$rel")"
      cp -p "$item" "$STAGE/ssh/$rel"
    fi
  done < <(find "$SSH_DIR" -mindepth 1 ! -type s -print0 2>/dev/null)
  chmod 700 "$STAGE/ssh"
  COMPONENTS+=("ssh")
  info "ssh/ ($(find "$STAGE/ssh" -type f | wc -l | tr -d ' ') file(s))"
fi

if [ "${#TOKENS[@]}" -gt 0 ]; then
  mkdir -p "$STAGE/home-tokens"
  for t in "${TOKENS[@]}"; do
    cp -p "$t" "$STAGE/home-tokens/"
    info "home-tokens/$(basename "$t")"
  done
  chmod -R go-rwx "$STAGE/home-tokens" 2>/dev/null || true
  COMPONENTS+=("home-tokens")
fi

# Collapse the staged tree into an encrypted archive, then drop the plaintext.
if [ "$ENCRYPT" -eq 1 ]; then
  info "Encrypting -> bundle.tar.age (age -p, you will be prompted now)"
  if tar -czf - -C "$STAGE" -- "${COMPONENTS[@]}" | age -p -o "$DEST/bundle.tar.age"; then
    chmod 600 "$DEST/bundle.tar.age"
    rm -rf -- "$STAGE"
    trap - EXIT
  else
    rm -rf -- "$STAGE" "$DEST/bundle.tar.age"
    trap - EXIT
    die "Encryption failed; plaintext staging scrubbed, no archive written."
  fi
fi

# A small manifest so future-you knows what this is and how to restore it. It
# is deliberately plaintext (documentation only — no secrets) in both modes.
# On restore, install.sh auto-restores ONLY age/key.txt; ssh/ and home-tokens/
# are a just-in-case safety net, restored on demand with --with-ssh/--with-tokens.
restore_notes=$'Contents -> restore target:\n  age/key.txt      -> ~/.config/chezmoi/key.txt   (age identity; ALWAYS restored)\n  ssh/             -> ~/.ssh/                       (only with: install.sh --with-ssh)\n  home-tokens/*    -> ~/                            (only with: install.sh --with-tokens)\n\nrestore everything with: install.sh --all'
if [ "$ENCRYPT" -eq 1 ]; then
  layout="bundle.tar.age is decrypted+extracted by ./install.sh, then:"$'\n'"$restore_notes"$'\n\n'"ENCRYPTED with age -p. Restore (prompts for passphrase) with:  ./install.sh"
else
  layout="$restore_notes"$'\n\n'"PLAINTEXT SECRETS — keep this stick physically secure and delete the bundle"$'\n'"once the new machine is set up. Restore with:  ./install.sh"
fi
cat > "$DEST/MANIFEST.txt" <<MANIFEST
Portable identity bundle created by bundle-identity.sh

$layout
MANIFEST
chmod 600 "$DEST/MANIFEST.txt"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
section "Done"
info "Bundle written to: $DEST"
info "Size: $(du -sh "$DEST" 2>/dev/null | cut -f1)"
if [ "$ENCRYPT" -eq 1 ]; then
  cat <<NEXT

Next steps:
  1. Verify it decrypts (before you rely on it!):
       age -d "$DEST/bundle.tar.age" | tar -tzf - | head
  2. Put this whole repo (with the identity-bundle/ folder) on your USB stick.
  3. On the new machine, from the repo root, run  ./install.sh  (it will prompt
     for the passphrase). Delete the bundle when done.
NEXT
else
  cat <<NEXT

Next steps:
  1. Put this whole repo (with the identity-bundle/ folder) on your USB stick.
  2. On the new machine, from the repo root, run:
       ./install.sh
  3. Once set up, delete the bundle so the plaintext keys don't linger:
       rm -rf "$DEST"
NEXT
fi
