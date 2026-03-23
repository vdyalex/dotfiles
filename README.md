A curated macOS development environment with modern CLI tools, ergonomic shell configuration, VS Code setup, and system preferences, managed by [chezmoi](https://chezmoi.io).

## ⚡ Settings

- **Fast navigation:** `eza` (ls replacement), `fzf` + `fd` (fuzzy search), `enhancd` (intelligent cd with fzf preview)
- **Better diffs:** `delta` with side-by-side view, Catppuccin theme that syncs with system dark/light mode
- **Productive shell:** Zsh with instant prompt (powerlevel10k), plugin manager (antidote), history substring search
- **Editor:** VS Code with language tools (PHP, JavaScript, Python, Go, Terraform, etc.) and custom keybindings
- **Secure Git:** SSH commit signing via 1Password, configured delta diffs
- **macOS tweaks:** Optimized Dock, Finder, keyboard, trackpad, screensaver, accessibility

## 🚀 Setup

### Install chezmoi

   ```bash
   brew install chezmoi
   ```

### Initialize from this repo

   ```bash
   chezmoi init git@github.com:vdyalex/dotfiles.git
   ```

   This clones the repo to `~/.local/share/chezmoi` and prompts for template variables:
   - `git_name`: Name
   - `git_email`: Email
   - `git_signingkey`: SSH public key (for commit signing)

### Review the changes

   ```bash
   chezmoi diff
   ```

   Preview all the files that will be created or modified.

### Apply the configuration

   ```bash
   chezmoi apply
   ```

### Update later

   ```bash
   chezmoi update
   ```

   Pulls the latest changes from the repo and applies them.

## ‼️ Important

- **Source:** `~/.local/share/chezmoi/` (the repo)
- **Target:** `$HOME/` (your actual dotfiles)
- Files starting with `dot_` are deployed as `.` files (e.g., `dot_zshrc` → `~/.zshrc`)
- Files starting with `run_` are scripts executed during apply
- Template files (`.tmpl`) use variables from `.chezmoidata.toml`
- Use `chezmoi diff` to preview changes before applying
- Use `chezmoi apply -v` to apply with verbose output
