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
  top-level keys merge into the template root. `.chezmoidata/syncthing.json`
  (`{"syncthing": {...}}`) is kept here so it lives in the source tree without
  being deposited in `$HOME`; it is the Syncthing spec, read directly (via `jq`)
  by the out-of-band `syncthing-setup.sh` — **not** consumed by any template or
  `chezmoi apply` step (see the Syncthing section below).

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

## Syncthing (out of band — not part of `chezmoi apply`)

Syncthing setup is deliberately **decoupled from the idempotent install**: neither
`chezmoi apply`, `configure.sh`, nor `install.sh` installs or reconfigures it, so
bootstrapping a machine never silently touches file-sync. (It used to run as
`run_onchange_after_40-syncthing.sh.tmpl`; that script is gone, and `syncthing`
was removed from the Brewfile.) Everything now lives in the repo-root, cross-platform
`syncthing-setup.sh` (`syncthing:` namespace tasks wrap it):
- **Install** — if `syncthing` is already on PATH (e.g. a prior `brew install`),
  it's used as-is; otherwise the official release binary for this OS/arch is
  downloaded from GitHub into `~/.local/bin` (no root, any distro). `task
  syncthing:install` / `--install-only` does just this.
- **Start** — a Homebrew service (macOS) or `systemctl --user` unit (Linux) if one
  exists, else a direct background `syncthing serve` launch as a universal fallback.
- **Configure** — reads the spec's `.syncthing` object from
  `home/.chezmoidata/syncthing.json` **directly with `jq`** (no chezmoi
  templating), then reconciles devices/folders/options via the REST API. Still
  idempotent and **additive** (PUTs listed items, never prunes hand-added ones),
  and still the setup-side mirror of `decommission.sh`'s teardown. Depends on
  `jq` + `curl`; no-ops with a warning if a dep is missing or the API is
  unreachable. Run with `task syncthing:apply`; edit the spec with
  `task syncthing:edit`; flags `--no-install` (reconcile only) / `--install-only`.

Two repo-root scripts form a **back-up-first, wipe-second** pair, never deployed
into `$HOME`:
- `backup-identity.sh` — passphrase-encrypted archive of non-reproducible secrets
  (age key, SSH/GPG keys, cloud/dev creds). Read-only; refuses to write into this
  git repo.
- `decommission.sh` — **dry-run by default**; deletes nothing until `--execute`
  *and* a typed confirmation. Stops Syncthing via its REST API and reads synced
  folder paths from `config.xml` before deleting it; refuses `/`, `$HOME`, or
  non-absolute paths as a guard. Keep these safety invariants when editing.

A second, lighter pair handles **physical (USB) transport of just the bootstrap
crown jewels** — the minimal secrets a fresh box needs before `chezmoi apply` can
decrypt anything:
- `bundle-identity.sh` (`task identity:bundle`, preview with `task identity:list`)
  — copies `~/.config/chezmoi/key.txt` (the age identity, which carries both the
  private key and its public recipient), all of `~/.ssh` (live agent sockets
  skipped), and home-root `*token*.*` files into `identity-bundle/` at the repo
  root. **Plaintext by default**; `--passphrase` (alias `--encrypt`) instead
  stages the tree, `tar | age -p`s it into a single `bundle.tar.age`, and scrubs
  the plaintext (an EXIT trap scrubs the staging on failure too) — only
  `MANIFEST.txt` stays plaintext. The folder is git-ignored (`/identity-bundle/`
  in `.gitignore`) and the script refuses to write into a git-tracked path; its
  gitignore-coverage check probes a path *under* the dir because a trailing-slash
  pattern won't match a not-yet-created directory.
- `install.sh` — the restore/new-machine side. Idempotent (skips existing files
  unless `--force`). It resolves a `SRC` dir — the plaintext `identity-bundle/`,
  or a `mktemp -d` it decrypts `bundle.tar.age` into (via `age`, prompting for the
  passphrase; the temp dir is scrubbed immediately after and via an EXIT trap).
  **Only the age key is auto-restored** — it's all that's needed to bootstrap
  chezmoi, and real SSH keys are meant to live age-encrypted *in* chezmoi. The
  bundled `~/.ssh` and tokens are a just-in-case safety net, restored only with
  `--with-ssh` / `--with-tokens` / `--all` (perms fixed on restore — keys `600`,
  `.ssh` `700`, `.pub` `644`). Then it runs `configure.sh` and
  `chezmoi init --apply --source <repo>`. Other flags: `--restore-only`,
  `--no-apply`, `--bundle DIR`, `--force`. For an encrypted bundle on a fresh box,
  `age` may not exist yet, so `install.sh` pulls `configure.sh` forward (guarded
  by a `TOOLS_DONE` flag so it runs at most once) to get `age` before decrypting.
