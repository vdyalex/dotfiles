#!/bin/bash

mkdir -p ~/.config/eza/themes/light ~/.config/eza/themes/dark

curl -so ~/.config/eza/themes/light/theme.yml \
  https://raw.githubusercontent.com/eza-community/eza-themes/main/themes/catppuccin-latte.yml

curl -so ~/.config/eza/themes/dark/theme.yml \
  https://raw.githubusercontent.com/eza-community/eza-themes/main/themes/catppuccin-mocha.yml
