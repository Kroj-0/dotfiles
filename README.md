# dotfiles

[![check](https://github.com/Kroj-0/dotfiles/actions/workflows/check.yml/badge.svg)](https://github.com/Kroj-0/dotfiles/actions/workflows/check.yml)

My zsh configuration and my Claude Code status line. The same files run on every machine I use, a Mac and a Windows PC with Ubuntu under WSL. Nothing in the repository is private: secrets and per-machine settings live in local files that git never sees.

![Claude Code status line: model, permission mode and git state; context usage and cache hits; cost, session time and rate limits](docs/statusline.svg)

## What's inside

| Path | Installed as | Purpose |
|---|---|---|
| `zsh/.zshrc` | `~/.zshrc` | Shell setup: oh-my-zsh, the oh-my-posh prompt, shared history, and faster replacements for `cd`, `ls` and `cat` |
| `claude/statusline-command.sh` | `~/.claude/statusline-command.sh` | A three-line status line for Claude Code, described in [docs/statusline.md](docs/statusline.md) |
| `install.sh` | | Links both files into place |

## Install

```sh
git clone https://github.com/Kroj-0/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

The installer replaces `~/.zshrc` and the status line script with symlinks into the clone, so editing either one edits the repository. Running it again changes nothing. When a target already exists with different content, the old file is kept next to the link as `<file>.bak-<timestamp>`.

Claude Code also needs one setting in `~/.claude/settings.json`. The installer reminds you when it is missing.

```json
{
  "statusLine": { "type": "command", "command": "bash ~/.claude/statusline-command.sh" }
}
```

### Requirements

zsh and [oh-my-zsh](https://ohmyz.sh) are required, with the [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) and [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) plugins cloned into `$ZSH_CUSTOM/plugins`. The status line needs [jq](https://jqlang.org).

Everything else is picked up when installed and skipped when not: [oh-my-posh](https://ohmyposh.dev) with a [Nerd Font](https://www.nerdfonts.com), [fnm](https://github.com/Schniz/fnm), [zoxide](https://github.com/ajeetdsouza/zoxide), [fzf](https://github.com/junegunn/fzf), [eza](https://github.com/eza-community/eza), [bat](https://github.com/sharkdp/bat), gh and terraform. Ubuntu installs bat as `batcat`; link it as `~/.local/bin/bat` to enable the alias.

## Private and per-machine settings

The shared `.zshrc` sources two optional files that `.gitignore` keeps out of the repository:

- `~/.zshrc.pre.local` runs first, before oh-my-zsh loads. It holds anything that must happen early, such as a `zstyle` that oh-my-zsh reads, or a hook that replaces the shell with `exec`.
- `~/.zshrc.local` runs last, so it can override anything. It holds tokens, ssh-agent setup, extra `PATH` entries and machine-specific functions. [zsh/zshrc.local.example](zsh/zshrc.local.example) is a starting point.

## The shell

- **Node versions** come from fnm, which switches automatically when you `cd` into a project with a `.node-version` or `.nvmrc` file.
- **Directory jumping** replaces `cd` with zoxide: `cd proj` goes to the directory you use most that matches "proj", and `cdi` picks one interactively.
- **Fuzzy search** from fzf binds Ctrl-R to history, Ctrl-T to files and Alt-C to directories. With the older fzf that Debian and Ubuntu ship, the same bindings come from the package's bundled scripts.
- **Listings and file views** use eza for `ls`, `ll` and `lt`, and bat for `cat`.
- **History** keeps 50,000 entries shared across open shells, drops duplicates, and skips commands typed with a leading space.
- **The prompt** is oh-my-posh's agnoster theme. Its setup output is cached, which saves about 150 ms per new shell, and the cache refreshes itself after an oh-my-posh upgrade.
- **`claude`** runs Claude Code with a GitHub token taken from `gh`, which its GitHub plugin needs. The token reaches Claude only, instead of being exported to every program the shell starts.
- **`claude-yolo`** runs Claude Code without permission prompts, but denies shell commands that touch git remotes, credentials, infrastructure, package registries or the system. The deny list covers shell commands only, not Claude's own file tools.

## The status line

Whenever the session changes, for example when a new message arrives, Claude Code pipes the session data to the script as JSON and shows whatever it prints. This one shows three lines: the model, permission mode, directory and git state; how full the context window is and how well the prompt cache is working; and the session's cost, duration and plan rate limits. Less important details drop out as the terminal narrows. [docs/statusline.md](docs/statusline.md) describes every segment and colour.

## Development

`scripts/check.sh` runs the same checks as CI: syntax and lint for every script, the status line against sample inputs under `sh` and `bash`, the installer against a throwaway home directory, and a secret scan. After changing what the status line prints, regenerate the README image with `scripts/render-preview.py`. [AGENTS.md](AGENTS.md) holds the rules for changing the repository, for people and coding agents alike.

## License

[MIT](LICENSE)
