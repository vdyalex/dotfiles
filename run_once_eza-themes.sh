#!/usr/bin/env bash

mkdir -p ~/.config/eza/light ~/.config/eza/dark

curl -so ~/.config/eza/light/theme.yml \
  https://raw.githubusercontent.com/eza-community/eza-themes/main/themes/catppuccin-latte.yml

curl -so ~/.config/eza/dark/theme.yml \
  https://raw.githubusercontent.com/eza-community/eza-themes/main/themes/catppuccin-mocha.yml
