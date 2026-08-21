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

### Typical loop

```bash
# You edited ~/.zshrc directly and want the change tracked:
task update -- ~/.zshrc      # pull live edits into the source
task diff                    # sanity-check
task save -- "tweak zshrc"   # commit + push
```

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
├── .chezmoiroot                 # points chezmoi at ./home
├── .chezmoiignore               # files chezmoi should not manage
├── .chezmoiscripts/             # run_once bootstrap scripts (e.g. key decrypt)
└── home/                        # the actual dotfiles (chezmoi source root)
    ├── .chezmoi.toml.tmpl       # generates ~/.config/chezmoi/chezmoi.toml
    ├── dot_zshrc, dot_p10k.zsh, dot_gitconfig.tmpl, …
    ├── dot_config/…             # ~/.config/* (mise, starship, waveterm, uv, …)
    ├── private_dot_ssh/…        # ~/.ssh (public keys + encrypted private keys)
    └── encrypted_*.age          # age-encrypted secrets
```
