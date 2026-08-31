# Zach Loeber's dotfiles

Cross-platform (macOS + Linux) dotfiles managed with
[chezmoi](https://chezmoi.io) and [mise](https://mise.jdx.dev), with secrets
encrypted via [age](https://age-encryption.org).

- **chezmoi** templates and applies the config files.
- **mise** installs and pins the required tools (`age`, `chezmoi`, `delta`,
  `task`, `starship`, `gitleaks`) — see [`mise.toml`](./mise.toml).
- **task** ([go-task](https://taskfile.dev)) wraps the common operations — run
  `task` to see them all.

## Prerequisites

Only `git`, `curl`, and a POSIX shell are assumed to already exist. On a bare
Linux box also make sure `zsh` is installed (`apt install zsh`, `dnf install
zsh`, …); everything else is installed by the bootstrap.

## Quick start (new machine)

```bash
# 1. Get the source
git clone https://github.com/zloeber/dotfiles.git ~/.local/share/chezmoi
cd ~/.local/share/chezmoi

# 2. Install mise + required tools (age, chezmoi, delta, task, starship, gitleaks)
./configure.sh          # or: task bootstrap

# 3. Provide the chezmoi age key (needed to decrypt secrets)
#    Option A: paste the key from your password manager into:
#        ~/.config/chezmoi/key.txt      (chmod 600)
#    Option B: if you have the passphrase for the encrypted copy in this repo:
task key:decrypt

# 4. Initialize and apply
chezmoi init --apply zloeber
```

> The age **public** recipient lives in `home/.chezmoi.toml.tmpl`; the matching
> **private** identity (`~/.config/chezmoi/key.txt`) is the one secret you must
> supply out-of-band. Without it, encrypted files (SSH keys, GitHub token)
> can't be decrypted, but everything else still applies.

## Everyday usage

Run `task` for the full list. The common ones:

| Command | What it does |
| --- | --- |
| `task diff` | Preview what `chezmoi apply` would change |
| `task status` | Show which managed files differ |
| `task apply` | Apply the source to `$HOME` |
| `task update` | Capture live edits from `$HOME` back into the source (`chezmoi re-add`) |
| `task edit -- ~/.zshrc` | Edit a managed file through chezmoi |
| `task add -- ~/.config/foo` | Start managing a new file |
| `task pull` | Pull latest from git and apply (`chezmoi update`) |
| `task save -- "message"` | Commit & push source changes to git |
| `task doctor` | Verify required binaries + run `chezmoi doctor` |
| `task key:decrypt` | Decrypt the age identity into `~/.config/chezmoi/key.txt` |
| `task secret:search` | Scan the repo/history for leaked secrets |

Most file-scoped tasks accept a target after `--`, e.g.
`task diff -- ~/.config/mise/config.toml`.

macOS-only helpers (the `mac:` namespace, see below):

| Command | What it does |
| --- | --- |
| `task mac:dump` | Regenerate the Brewfile from the live system into the source |
| `task mac:bundle` | Install everything in the Brewfile now (`brew bundle`) |
| `task mac:wallpaper:backup` | Capture the current desktop picture into the source |
| `task mac:wallpaper:set` | Set the wallpaper to the committed image now |
| `task mac:defaults` | Apply the curated macOS `defaults` immediately |
| `task mac:backup-identity` | Archive keys/tokens/creds into an age-encrypted file |
| `task mac:decommission` | Preview wiping your identity from this Mac (dry run) |

### Typical loop

```bash
# You edited ~/.zshrc directly and want the change tracked:
task update -- ~/.zshrc      # pull live edits into the source
task diff                    # sanity-check
task save -- "tweak zshrc"   # commit + push
```

## macOS system transfer (Mac → Mac)

Beyond config files, this repo can bring a fresh Mac to parity with an existing
one: the Homebrew install base, fonts, wallpaper, and system preferences. These
pieces are **macOS-only** — the scripts self-gate on OS and the data files are
ignored off macOS, so Linux/containers are unaffected.

Everything is driven by `chezmoi apply` (the scripts under
`home/.chezmoiscripts/` run automatically), or on demand via the `mac:` tasks.

- **Brewfile** (`~/.config/homebrew/Brewfile`) — the declarative install base:
  formulae, casks, fonts, and any `vscode`/`npm`/`uv` globals captured by
  `brew bundle dump`. On `chezmoi apply`, `run_onchange_after_10-homebrew`
  installs Homebrew if missing and runs `brew bundle`. It only re-runs when the
  Brewfile changes (its hash is embedded in the script). Refresh the Brewfile
  from your current machine with `task mac:dump`.
- **Fonts** — managed as `font-*-nerd-font` casks inside the Brewfile (e.g.
  `font-hack-nerd-font`). No separate downloader to maintain.
- **Wallpaper** — the image lives in the repo at `~/.config/wallpaper/current.png`
  and is set with [`desktoppr`](https://github.com/scriptingosx/desktoppr) (a
  cask in the Brewfile). `run_onchange_after_30-wallpaper` re-applies only when
  the image changes. Capture your current wallpaper with
  `task mac:wallpaper:backup`, set it now with `task mac:wallpaper:set`.
- **System defaults** — `run_onchange_after_20-macos-defaults` applies a
  curated, well-commented set of `defaults write` tweaks (Finder, keyboard,
  screenshots, Dock, trackpad, save panels) and restarts the affected apps.
  Trim/extend the script freely; bump its `defaults version:` comment to force a
  re-run. Apply immediately with `task mac:defaults`.

> First-run ordering: on a brand-new Mac the wallpaper script may run before
> `brew bundle` has installed `desktoppr` — it just warns and skips. A second
> `chezmoi apply` (or `task mac:wallpaper:set`) sets it once `desktoppr` exists.

### Migrating to a new Mac, then decommissioning the old one

The two scripts at the repo root are a pair — **back up first, wipe second:**

```bash
# 1. On the OLD Mac: capture the secrets that don't live in this git repo
#    (age key, SSH/GPG keys, cloud/dev/AI credentials) into ONE encrypted file.
task mac:backup-identity -- --list      # preview what will be included
task mac:backup-identity                # create ~/identity-backup-<host>-<date>.tar.age

# 2. Move that archive off the Mac, then on the NEW Mac restore it:
age -d identity-backup-*.tar.age | tar -xzf - -C "$HOME"

# 3. Back on the OLD Mac, wipe your identity:
task mac:decommission                   # dry run
./decommission.sh --execute             # real wipe
```

`backup-identity.sh` is passphrase-encrypted by default (your age key is *in*
the archive, so encrypting to that key would lock you out). It is read-only with
respect to your system and refuses to write the archive into this git repo.
Your dotfiles/config aren't included — they're already reproducible from
chezmoi; only the non-reproducible secrets are captured. See
`./backup-identity.sh --help`.

> On the new Mac: it's provisioned fresh and MDM-enrolled by IT, so this repo +
> the restored identity archive rebuild *your* layer on top — not the corporate
> baseline. If the old machine is MDM-managed, coordinate the hand-back with IT
> (Activation Lock / DEP release) rather than relying on a local wipe alone.

### Decommissioning (identity wipe)

When you're finalizing/handing off a Mac, `decommission.sh` (repo root) quits
apps, gracefully stops Syncthing and removes its synced folders, then deletes
private keys, tokens, cloud credentials, and browser/app profiles (logging you
out of Firefox, Edge, Brave, Chrome, Safari, Signal, Teams, Slack, VS Code,
Cursor, Docker, …).

Syncthing is handled carefully: it's shut down via its REST API (then brew
service / launchd / signal) so it isn't mid-write, and the synced folder paths
are discovered from its `config.xml` *before* that config is deleted. Paths
like `/`, `$HOME`, or non-absolute entries are refused as a safety guard.

It is **dry-run by default** — it only prints what it would delete. It deletes
nothing until you pass `--execute` *and* type a confirmation phrase.

```bash
task mac:decommission                 # dry run — review the plan
./decommission.sh --verbose           # dry run, also list absent paths
./decommission.sh --execute           # real wipe (prompts to confirm)
./decommission.sh --execute --reset-keychain --remove-dotfiles   # nuke-everything
task mac:decommission -- --execute    # same, via task
```

The script is repo-only (never deployed into `$HOME`) and prints a manual
checklist at the end for the steps it deliberately won't automate — revoking
tokens server-side, signing out of Apple ID / Find My, and the final "Erase All
Content and Settings". See `./decommission.sh --help`.

## Syncthing (declarative device/folder sync)

Syncthing is configured **declaratively** from a committed spec — the setup-side
counterpart to what `decommission.sh` tears down. The spec lives in the chezmoi
source at `home/.chezmoidata/syncthing.json`:

```json
{
  "syncthing": {
    "options": { "urAccepted": -1 },
    "devices": [
      { "name": "laptop", "id": "AIR6LPZ-7K4PTTV-…" }
    ],
    "folders": [
      { "id": "notes", "label": "Notes", "path": "~/Sync/notes",
        "type": "sendreceive", "devices": ["laptop"] }
    ]
  }
}
```

On `chezmoi apply`, `home/.chezmoiscripts/run_onchange_after_40-syncthing.sh.tmpl`
ensures Syncthing is running (cross-platform: `brew services` on macOS,
`systemctl --user` on Linux) and reconciles the spec into the local instance via
its REST API. It's **idempotent and additive** — it creates/updates the listed
devices and folders but never removes anything you added by hand — and re-runs
automatically whenever the spec changes (its hash is embedded in the script). It
skips cleanly (no-op + warning) in ephemeral/headless environments, when
Syncthing/`jq`/`curl` aren't installed, or when the API isn't reachable.

> Device IDs are **public** (you hand them to peers to pair), so committing them
> is safe. The REST API key is read from the running instance at apply time and
> is never stored in the repo. `folders[].devices` entries may be a device
> `name` from the spec or a raw device ID; this machine is always added to each
> folder automatically.

| Command | What it does |
| --- | --- |
| `task syncthing:edit` | Edit the spec (`.chezmoidata/syncthing.json`) |
| `task syncthing:apply` | Reconcile devices/folders from the spec right now |
| `task syncthing:id` | Print this machine's device ID (share it with peers) |
| `task syncthing:gui` | Open the Syncthing web UI |

## Cross-platform notes

- **Tooling** is provided by mise, so the same versions are used on macOS and
  Linux without relying on Homebrew/apt for anything beyond the prerequisites.
- **`dot_zshrc`** guards every optional integration (brew, mise, starship,
  pnpm, VS Code) so a fresh machine still boots into a usable shell even when a
  tool is missing.
- **`delta`** is the configured diff pager. `home/.chezmoi.toml.tmpl` only wires
  it up when `delta` is on `PATH` (`lookPath "delta"`), so `chezmoi diff` never
  breaks on a box that hasn't installed it yet. If your generated
  `~/.config/chezmoi/chezmoi.toml` still hardcodes delta from an older init,
  re-run `chezmoi init` to regenerate it.
- **`home/.chezmoi.toml.tmpl`** auto-detects ephemeral/headless environments
  (Codespaces, containers, CI) and OS/distro to keep behavior sane everywhere.

## Layout

```
.
├── configure.sh                 # bootstrap: install mise + pinned tools
├── mise.toml                    # tool versions for this repo
├── Taskfile.yml                 # dotfiles management commands (task -l)
├── tasks/Taskfile.github.yml    # optional GitHub helper tasks
├── tasks/Taskfile.mac.yml       # optional macOS helpers (brew/wallpaper/defaults)
├── tasks/Taskfile.syncthing.yml # optional Syncthing helpers (apply/edit/id/gui)
├── .chezmoiroot                 # points chezmoi at ./home
└── home/                        # the actual dotfiles (chezmoi source root)
    ├── .chezmoi.toml.tmpl       # generates ~/.config/chezmoi/chezmoi.toml
    ├── .chezmoiignore           # skips macOS-only assets off macOS
    ├── .chezmoidata/            # template data (e.g. syncthing.json — the Syncthing spec)
    ├── .chezmoiscripts/         # run_onchange scripts (brew, defaults, wallpaper, syncthing)
    ├── dot_zshrc, dot_gitconfig.tmpl, …
    ├── dot_config/…             # ~/.config/* (mise, starship, waveterm, uv, homebrew, wallpaper, …)
    ├── private_dot_ssh/…        # ~/.ssh (public keys + encrypted private keys)
    └── encrypted_*.age          # age-encrypted secrets
```

> Note: chezmoi's source root is `home/` (`.chezmoiroot`), so the operative
> `.chezmoiignore` and `.chezmoiscripts/` live **inside** `home/`. The
> like-named entries at the repo root are repo-management artifacts and are not
> read by `chezmoi apply`.
