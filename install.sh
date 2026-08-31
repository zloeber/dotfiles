#!/usr/bin/env bash
#
# install.sh — set up a NEW machine from this repo (typically carried on a USB
# stick). It is IDEMPOTENT and safe to re-run.
#
# It runs, in order:
#   1. Restore the portable identity bundle IF ./identity-bundle exists locally:
#        age/key.txt      -> ~/.config/chezmoi/key.txt   (0600)
#        ssh/             -> ~/.ssh/                       (dir 0700, keys 0600)
#        home-tokens/*    -> ~/                            (0600)
#      The bundle may be plaintext (age/, ssh/, home-tokens/ dirs) OR encrypted
#      (a single bundle.tar.age from `bundle-identity.sh --passphrase`); an
#      encrypted bundle is decrypted with age, prompting for the passphrase.
#      (create the bundle beforehand with ./bundle-identity.sh)
#   2. ./configure.sh  — install mise + the tools pinned in mise.toml.
#   3. chezmoi init --apply from THIS source tree, so your dotfiles land (the
#      age key restored in step 1 lets chezmoi decrypt encrypted_* files).
#
# Existing files are never clobbered unless you pass --force, so re-running only
# fills in what is missing.
#
# By default only the age identity is restored — it is the one secret needed to
# bootstrap chezmoi (which then decrypts your real, encrypted_* keys). The
# bundled ~/.ssh and home-root *token*.* files are a "just in case" safety net
# and are NOT restored unless you ask:
#   --with-ssh      also restore ~/.ssh from the bundle
#   --with-tokens   also restore home-root *token*.* files
#   --all           restore everything in the bundle (age key + ssh + tokens)
#
# USAGE
#   ./install.sh                 # restore age key only + tools + apply
#   ./install.sh --all           # also restore ~/.ssh and home tokens
#   ./install.sh --with-ssh      # also restore ~/.ssh (tokens still skipped)
#   ./install.sh --force         # overwrite secrets that already exist on disk
#   ./install.sh --no-apply      # restore + tools only; skip chezmoi apply
#   ./install.sh --restore-only  # restore the bundle only; skip tools + apply
#   ./install.sh --bundle DIR    # restore from a bundle at a non-default path

set -eu
set -o pipefail
umask 077   # restored secrets stay private

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
FORCE=0
DO_APPLY=1
RESTORE_ONLY=0
WITH_SSH=0
WITH_TOKENS=0
BUNDLE="$SCRIPT_DIR/identity-bundle"

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
    --force|-f)     FORCE=1; shift ;;
    --no-apply)     DO_APPLY=0; shift ;;
    --restore-only) RESTORE_ONLY=1; shift ;;
    --with-ssh)     WITH_SSH=1; shift ;;
    --with-tokens)  WITH_TOKENS=1; shift ;;
    --all)          WITH_SSH=1; WITH_TOKENS=1; shift ;;
    --bundle)       BUNDLE="${2:?--bundle needs a path}"; shift 2 ;;
    --help|-h)   usage; exit 0 ;;
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

# Resolve a binary via PATH, falling back to mise's shim path (the current shell
# may not have activated mise yet on a fresh machine).
resolve_bin() {
  local n="$1" p
  p="$(command -v "$n" 2>/dev/null || true)"
  if [ -z "$p" ] && command -v mise >/dev/null 2>&1; then
    p="$(mise which "$n" 2>/dev/null || true)"
  fi
  printf '%s' "$p"
}

# Install tooling via configure.sh, at most once per run (it may be pulled
# forward if we need `age` to decrypt an encrypted bundle).
TOOLS_DONE=0
ensure_tools() {
  [ "$TOOLS_DONE" -eq 1 ] && return 0
  section "Tooling (configure.sh)"
  if [ -x "$SCRIPT_DIR/configure.sh" ]; then
    "$SCRIPT_DIR/configure.sh"
  else
    warn "configure.sh not found or not executable — skipping tool install."
  fi
  TOOLS_DONE=1
}

# Copy SRC->DST unless DST exists (idempotent), honoring --force. MODE chmods
# the destination. Returns without error if SRC is missing.
install_file() {
  local src="$1" dst="$2" mode="$3"
  [ -f "$src" ] || return 0
  if [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then
    info "[keep]    $dst already exists (use --force to overwrite)"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  cp -p "$src" "$dst"
  chmod "$mode" "$dst"
  info "[restore] $dst"
}

# ---------------------------------------------------------------------------
# 1. Restore the identity bundle (only if it is present on this machine).
#    Resolve SRC to a directory holding age/, ssh/, home-tokens/ — either the
#    plaintext bundle folder, or a temp dir we decrypt an encrypted bundle into.
# ---------------------------------------------------------------------------
section "Identity bundle"
SRC=""
CLEANUP_SRC=""

if [ -f "$BUNDLE/bundle.tar.age" ]; then
  info "Found encrypted bundle: $BUNDLE/bundle.tar.age"
  AGE="$(resolve_bin age)"
  if [ -z "$AGE" ]; then
    # Decryption needs age; on a fresh box it may not be installed yet.
    [ "$RESTORE_ONLY" -eq 1 ] && \
      die "age is required to decrypt this bundle but isn't installed. Run ./install.sh without --restore-only (it installs age), or install age first."
    info "age not found yet — installing tooling first so we can decrypt."
    ensure_tools
    AGE="$(resolve_bin age)"
    [ -n "$AGE" ] || die "age still not found after configure.sh; cannot decrypt the bundle."
  fi
  SRC="$(mktemp -d "${TMPDIR:-/tmp}/identity-restore.XXXXXX")"
  CLEANUP_SRC="$SRC"
  trap 'rm -rf -- "$CLEANUP_SRC"' EXIT
  info "Decrypting (you may be prompted for the passphrase)…"
  "$AGE" -d "$BUNDLE/bundle.tar.age" | tar -xzf - -C "$SRC"
elif [ -d "$BUNDLE" ]; then
  info "Found bundle: $BUNDLE"
  SRC="$BUNDLE"
else
  info "No bundle at $BUNDLE — skipping identity restore."
  info "(create one on the old machine with ./bundle-identity.sh)"
fi

if [ -n "$SRC" ]; then
  # 1a. age identity -> ~/.config/chezmoi/key.txt  (ALWAYS restored: it is the
  #     one secret needed to bootstrap chezmoi's decryption of everything else).
  install_file "$SRC/age/key.txt" "$HOME/.config/chezmoi/key.txt" 600

  # 1b. ~/.ssh — OPT-IN (--with-ssh). Bundled as a just-in-case safety net; the
  #     source of truth for real keys is age-encrypted inside chezmoi.
  if [ -d "$SRC/ssh" ]; then
    if [ "$WITH_SSH" -eq 1 ]; then
      mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
      while IFS= read -r -d '' f; do
        rel="${f#"$SRC"/ssh/}"
        install_file "$f" "$HOME/.ssh/$rel" 600
      done < <(find "$SRC/ssh" -type f -print0 2>/dev/null)
      # Public keys are not secret — make them world-readable as ssh expects.
      find "$HOME/.ssh" -type f -name '*.pub' -exec chmod 644 {} + 2>/dev/null || true
    else
      info "[skip]    ~/.ssh not restored (safety-net copy; pass --with-ssh to restore)"
    fi
  fi

  # 1c. home-root token files -> ~/  — OPT-IN (--with-tokens).
  if [ -d "$SRC/home-tokens" ]; then
    if [ "$WITH_TOKENS" -eq 1 ]; then
      while IFS= read -r -d '' f; do
        install_file "$f" "$HOME/$(basename "$f")" 600
      done < <(find "$SRC/home-tokens" -maxdepth 1 -type f -print0 2>/dev/null)
    else
      info "[skip]    home *token*.* files not restored (pass --with-tokens to restore)"
    fi
  fi
fi

# Scrub the decrypted temp dir now (don't wait for the EXIT trap).
if [ -n "$CLEANUP_SRC" ]; then
  rm -rf -- "$CLEANUP_SRC"; CLEANUP_SRC=""; trap - EXIT
fi

if [ "$RESTORE_ONLY" -eq 1 ]; then
  section "Done"
  info "Identity restore complete (--restore-only: tools + chezmoi skipped)."
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Install tooling (mise + pinned tools). configure.sh is itself idempotent,
#    and ensure_tools no-ops if it already ran to provide age above.
# ---------------------------------------------------------------------------
ensure_tools

# ---------------------------------------------------------------------------
# 3. Apply dotfiles with chezmoi from THIS source tree.
# ---------------------------------------------------------------------------
section "Dotfiles (chezmoi)"
if [ "$DO_APPLY" -eq 1 ]; then
  CHEZMOI="$(resolve_bin chezmoi)"
  if [ -n "$CHEZMOI" ]; then
    info "Using: $CHEZMOI"
    # --source points chezmoi at this repo; --apply runs the prompts then applies.
    "$CHEZMOI" init --apply --source "$SCRIPT_DIR"
  else
    warn "chezmoi not on PATH yet. Open a new shell (so mise activates), then run:"
    warn "  chezmoi init --apply --source \"$SCRIPT_DIR\""
  fi
else
  info "Skipped (--no-apply)."
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
section "Done"
info "Machine setup complete."
if [ -d "$BUNDLE" ]; then
  warn "Reminder: the identity bundle still exists. Delete it when finished:"
  warn "  rm -rf \"$BUNDLE\""
fi
