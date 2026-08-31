# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Zach Loeber's cross-platform (macOS + Linux) dotfiles, managed with **chezmoi**,
with tooling pinned by **mise**, common operations wrapped by **go-task**, and
secrets encrypted with **age**. The README is thorough — read it for user-facing
workflows. This file captures the non-obvious mechanics.

## Critical layout gotcha: two source roots

`.chezmoiroot` contains `home`, so **chezmoi's source root is `home/`, not the
repo root**. This means:

- The operative `.chezmoiignore`, `.chezmoiscripts/`, and `.chezmoi.toml.tmpl`
  live **inside `home/`**. The like-named entries at the repo root (including
  `.chezmoiscripts/run_once_before_decrypt-private-key.sh.tmpl`) are outside the
  source root and are *not* read by `chezmoi apply` — treat them as
  repo-management artifacts / legacy, not active chezmoi hooks.
- When editing dotfiles, work in `home/`. When editing management tooling
  (Taskfile, mise, bootstrap/backup/decommission scripts), work at the repo root.
- `chezmoi source-path` prints the effective source dir; the `mac:` tasks rely on
  it to locate the Brewfile and wallpaper in the source tree.

## chezmoi naming conventions (in `home/`)

Filenames encode attributes — renaming changes behavior:
- `dot_foo` → `~/.foo`; `private_` → chmod 600; `encrypted_` → age-decrypt on apply.
- `*.tmpl` → rendered as a Go template against the `[data]` in `.chezmoi.toml.tmpl`.
- `run_once_*` runs once ever; `run_onchange_*` re-runs when its content hash
  changes (scripts embed a hash/version comment to force re-runs). Numeric
  prefixes (`10-`, `20-`, `30-`, `40-`) order execution; `before`/`after` sets phase.
- `.chezmoiremove` lists target paths chezmoi deletes on apply (e.g. legacy `.p10k.zsh`).
- `.chezmoidata/*.json|yaml|toml` are **template data, not targets** — their
  top-level keys merge into the template root (so `.chezmoidata/syncthing.json`
  containing `{"syncthing": {...}}` exposes `.syncthing` to every template). This
  is how the Syncthing spec is carried without depositing a file in `$HOME`.

## Templating & environment detection

`home/.chezmoi.toml.tmpl` prompts once (`promptStringOnce`/`promptBoolOnce`) for
email, GitHub user, full name, and `use_secrets`, then computes:
- `osid` (e.g. `linux-ubuntu`), `ephemeral`/`headless` (Codespaces, remote
  containers, root/ubuntu/vagrant/vscode users, Windows), and a normalized
  `hostname` (darwin ComputerName workaround).
- `[diff] command = delta` is only wired up when `lookPath "delta"` succeeds, and
  the `[edit]`/`[merge]` block only uses VS Code when `code` is on PATH — so a
  fresh box without those tools never breaks. Templates that reference tools
  should guard the same way.

## Secrets (age)

- Recipient (public) is committed in `home/.chezmoi.toml.tmpl`. The private
  identity at `~/.config/chezmoi/key.txt` is the one out-of-band secret.
- `key.txt.age` is a **passphrase**-encrypted copy of the identity;
  `task key:decrypt` (or the run_once decrypt script) restores it. It's
  passphrase-encrypted, not key-encrypted, to avoid a chicken-and-egg lockout.
- `secret_results.json` is gitleaks scratch output (git-ignored / cleaned by
  `task clean`) — don't commit it.

## Commands

Run `task` (no args) for the full list. Key ones:

| Command | Purpose |
| --- | --- |
| `./configure.sh` / `task bootstrap` | Install mise + pinned tools, then `task doctor` |
| `task doctor` | Verify required bins + `chezmoi doctor` |
| `task diff [-- target]` | Preview what `chezmoi apply` would change |
| `task apply [-- target]` | Apply source → `$HOME` |
| `task update -- ~/.zshrc` | Pull a live edit back into the source (`chezmoi re-add`) |
| `task edit -- ~/.zshrc` / `task add -- ...` | Edit / start managing a file |
| `task pull` / `task save -- "msg"` | git pull+apply / commit+push |
| `task secret:search` | gitleaks scan of repo + history |

Most file-scoped tasks take a target after `--`. There is no build/test suite —
this is a config repo; "correctness" = `task diff` shows the intended change and
`task doctor`/`gitleaks` stay clean.

macOS-only helpers live in the `mac:` namespace (`tasks/Taskfile.mac.yml`); every
task self-gates via `_guard` and refuses to run off darwin. GitHub helpers are in
`tasks/Taskfile.github.yml`, Syncthing helpers in `tasks/Taskfile.syncthing.yml`
(`syncthing:` namespace, cross-platform). All are `optional: true` includes in the
root Taskfile.

## macOS system transfer

Driven by `chezmoi apply` via `home/.chezmoiscripts/run_onchange_after_*`:
`10-homebrew` (Homebrew + `brew bundle` from `~/.config/homebrew/Brewfile`),
`20-macos-defaults` (curated `defaults write`), `30-wallpaper` (via `desktoppr`).
These three are darwin-gated and re-run only when their content changes. macOS
data files (`.config/homebrew`, `.config/wallpaper`) are ignored off darwin via
`home/.chezmoiignore`. Refresh the Brewfile with `task mac:dump`.

`40-syncthing` is the odd one out — **cross-platform, not darwin-gated** (only
skipped when `.ephemeral`/`.headless`). It reconciles the declarative spec in
`home/.chezmoidata/syncthing.json` into the local Syncthing via its REST API
(`brew services`/`systemctl --user` to start it; `jq` builds the payloads). It is
idempotent and **additive** — it PUTs the listed devices/folders but never prunes
items added by hand — and is the setup-side mirror of `decommission.sh`'s
teardown. Depends on `jq` + `curl`; it no-ops with a warning if either is missing,
if Syncthing isn't installed/running, or if the API is unreachable. Run on demand
with `task syncthing:apply`; edit the spec with `task syncthing:edit`.

Two repo-root scripts form a **back-up-first, wipe-second** pair, never deployed
into `$HOME`:
- `backup-identity.sh` — passphrase-encrypted archive of non-reproducible secrets
  (age key, SSH/GPG keys, cloud/dev creds). Read-only; refuses to write into this
  git repo.
- `decommission.sh` — **dry-run by default**; deletes nothing until `--execute`
  *and* a typed confirmation. Stops Syncthing via its REST API and reads synced
  folder paths from `config.xml` before deleting it; refuses `/`, `$HOME`, or
  non-absolute paths as a guard. Keep these safety invariants when editing.
