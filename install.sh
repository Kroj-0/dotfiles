#!/usr/bin/env bash
# Link the shared dotfiles into place. Safe to re-run.
# An existing file that differs from the repo copy is moved aside first.
set -euo pipefail

repo=$(cd "$(dirname "$0")" && pwd)
stamp=$(date +%Y%m%d-%H%M%S)

link() {
  local src="$repo/$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "ok      $dst"
    return
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if cmp -s "$src" "$dst"; then
      rm "$dst"
    else
      mv "$dst" "$dst.bak-$stamp"
      echo "backup  $dst.bak-$stamp"
    fi
  fi
  ln -s "$src" "$dst"
  echo "linked  $dst -> $src"
}

link zsh/.zshrc                   "$HOME/.zshrc"
link claude/statusline-command.sh "$HOME/.claude/statusline-command.sh"

[ -e "$HOME/.zshrc.local" ] || echo "hint    no ~/.zshrc.local yet; see zsh/zshrc.local.example"
if ! grep -qs 'statusline-command.sh' "$HOME/.claude/settings.json"; then
  echo 'hint    add to ~/.claude/settings.json:'
  echo '        "statusLine": {"type": "command", "command": "bash ~/.claude/statusline-command.sh"}'
fi
