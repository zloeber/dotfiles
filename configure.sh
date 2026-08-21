#!/usr/bin/env bash
#
# configure.sh — bootstrap the tools this dotfiles repo needs.
#
# Installs mise (if missing) and the binaries pinned in ./mise.toml
# (age, chezmoi, delta, task, starship, gitleaks). Safe to re-run.
# Works on macOS and Linux; only `git`, `curl`, and a POSIX shell are
# assumed to already be present.

set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# 1. Locate or install mise
# ---------------------------------------------------------------------------
find_mise() {
  if command -v mise >/dev/null 2>&1; then command -v mise; return 0; fi
  for candidate in \
      "$HOME/.local/bin/mise" \
      /opt/homebrew/bin/mise \
      /usr/local/bin/mise \
      /home/linuxbrew/.linuxbrew/bin/mise; do
    [ -x "$candidate" ] && { echo "$candidate"; return 0; }
  done
  return 1
}

if ! MISE_BIN="$(find_mise)"; then
  warn "mise is not installed."
  printf 'Install mise now via https://mise.run ? [y/N] '
  read -r response
  case "$response" in
    [Yy]*)
      curl -fsSL https://mise.run | sh
      MISE_BIN="$HOME/.local/bin/mise"
      ;;
    *)
      warn "mise is required to continue. Aborting."
      exit 1
      ;;
  esac
fi
info "Using mise at: $MISE_BIN"

# ---------------------------------------------------------------------------
# 2. Activate mise for this shell so freshly installed shims resolve
# ---------------------------------------------------------------------------
eval "$("$MISE_BIN" activate bash)" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. Install the tools pinned in mise.toml
# ---------------------------------------------------------------------------
info "Installing tools from $REPO_DIR/mise.toml"
( cd "$REPO_DIR" && "$MISE_BIN" install -y )

# ---------------------------------------------------------------------------
# 4. Next steps
# ---------------------------------------------------------------------------
cat <<EOF

$(info "Tools installed.")

Next steps:

  1. Make mise available in new shells (if it isn't already):

       echo 'eval "\$(${MISE_BIN} activate zsh)"' >> ~/.zshrc

  2. Put the chezmoi age key at ~/.config/chezmoi/key.txt
     (paste it from your password manager, or if you have the
     passphrase for the encrypted copy in this repo, run:  task key:decrypt)

  3. Initialize and apply your dotfiles:

       chezmoi init --apply zloeber

  Tip: run 'task' to see all available dotfiles management commands,
  and 'task doctor' to verify everything is wired up correctly.

EOF
