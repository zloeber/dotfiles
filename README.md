# Zach Loeber's dotfiles



```bash
# To initialize on a new system
cd ~
git clone https://github.com/zloeber/dotfiles.git
cd dotfiles
./configure.sh
mise use -g chezmoi
mise install -y
```

To use this you will need the chezmoi age encryption key from elsewhere pasted into `~/.config/chezmoi/key.txt` then you can go to the home path and use chezmoi to complete configuration.

```bash
cd
chezmoi init https://github.com/zloeber/dotfiles.git
```
