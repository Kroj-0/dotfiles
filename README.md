# dotfiles

My shell and Claude Code setup, shared by every machine I use: a Mac and a Windows PC running WSL Ubuntu.

| File | Installed at | What it is |
|---|---|---|
| `zsh/.zshrc` | `~/.zshrc` | oh-my-zsh with the oh-my-posh `agnoster` prompt, history settings, fnm, zoxide, fzf, eza and bat aliases, and the `claude` / `claude-yolo` helpers |
| `claude/statusline-command.sh` | `~/.claude/statusline-command.sh` | A three-line Claude Code status line: model and git state, a context bar with cache stats, then cost and rate limits |

## Install on a new machine

```sh
git clone git@github.com:Kroj-0/dotfiles.git ~/code/kroj/dotfiles
~/code/kroj/dotfiles/install.sh
```

`install.sh` replaces each target with a symlink into this repo, so editing `~/.zshrc` edits the repo copy. It is safe to re-run. A target that differs from the repo copy is kept as `<file>.bak-<timestamp>`.

## Private settings stay out of the repo

Everything committed here must be publishable. Secrets and machine-specific settings go in two untracked files, which `.gitignore` excludes:

- `~/.zshrc.pre.local` is sourced first, before oh-my-zsh. Use it for early `exec` hooks and `zstyle` settings that oh-my-zsh reads.
- `~/.zshrc.local` is sourced last. Use it for tokens, ssh-agent setup, extra PATH entries and per-machine functions. See `zsh/zshrc.local.example`.

The GitHub token for Claude Code's GitHub plugin is not exported globally. The `claude` wrapper fetches it from `gh` and passes it to Claude only.

## Requirements

- zsh, git, and [oh-my-zsh](https://ohmyz.sh) with the `zsh-autosuggestions` and `zsh-syntax-highlighting` custom plugins
- [oh-my-posh](https://ohmyposh.dev) and a Nerd Font in the terminal
- fnm, zoxide, fzf, eza and bat. Every tool is optional: the `.zshrc` skips whatever is not installed. On Ubuntu, `bat` is `batcat`, so link it as `~/.local/bin/bat`.
- jq, for the status line

## Notes

- Codex CLI cannot use the status line script. It only offers built-in items, set with `tui.status_line` in `~/.codex/config.toml`.
