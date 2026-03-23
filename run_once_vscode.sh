#!/bin/zsh
VSCODE_DIR="$HOME/Library/Application Support/Code/User"
mkdir -p "$VSCODE_DIR"

ln -sf "{{ .chezmoi.sourceDir }}/dot_vscode/settings.json" "$VSCODE_DIR/settings.json"
ln -sf "{{ .chezmoi.sourceDir }}/dot_vscode/keybindings.json" "$VSCODE_DIR/keybindings.json"
