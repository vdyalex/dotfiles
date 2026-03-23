#!/usr/bin/env bash

VSCODE_DIR="$HOME/Library/Application Support/Code/User"
mkdir -p "$VSCODE_DIR"

ln -sf ~/.vscode/settings.json "$VSCODE_DIR/settings.json"
ln -sf ~/.vscode/keybindings.json "$VSCODE_DIR/keybindings.json"
