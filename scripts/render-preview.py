#!/usr/bin/env python3
"""Render the Claude Code status line to docs/statusline.svg for the README.

The status line is run for real, against tests/fixtures/typical.json and a
throwaway git repository, so the picture always matches what the script
prints. Standard library only. Run it after changing the status line output.
"""

import html
import json
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
STATUSLINE = REPO / "claude" / "statusline-command.sh"
FIXTURE = REPO / "tests" / "fixtures" / "typical.json"
OUTPUT = REPO / "docs" / "statusline.svg"

COLUMNS = 130
FONT_SIZE = 13
CHAR_WIDTH = 7.8  # advance of one monospace cell at FONT_SIZE
LINE_HEIGHT = 21
PADDING = 18
TITLE_BAR = 30
BACKGROUND = "#1e1e1e"  # the status line palette is tuned against this
DEFAULT_FG = "#d4d4d4"

SGR = re.compile(r"\x1b\[([0-9;]*)m")
CLOCK = re.compile(r"(?<!\d)\d{2}:\d{2}(?!\d)")  # the colour codes around it defeat \b
PREVIEW_CLOCK = "09:41"


def xterm_color(index):
    """Hex value of an xterm 256-colour palette entry."""
    base = ["000000", "cd0000", "00cd00", "cdcd00", "0000ee", "cd00cd", "00cdcd", "e5e5e5",
            "7f7f7f", "ff0000", "00ff00", "ffff00", "5c5cff", "ff00ff", "00ffff", "ffffff"]
    if index < 16:
        return "#" + base[index]
    if index < 232:
        index -= 16
        steps = [0, 95, 135, 175, 215, 255]
        rgb = (steps[index // 36], steps[(index // 6) % 6], steps[index % 6])
        return "#%02x%02x%02x" % rgb
    grey = 8 + (index - 232) * 10
    return "#%02x%02x%02x" % (grey, grey, grey)


def styled_runs(line):
    """Split one line of terminal output into (text, colour, bold, italic) runs."""
    runs, colour, bold, italic, position = [], DEFAULT_FG, False, False, 0
    for match in SGR.finditer(line):
        if match.start() > position:
            runs.append((line[position:match.start()], colour, bold, italic))
        codes = [int(code) for code in match.group(1).split(";") if code] or [0]
        i = 0
        while i < len(codes):
            code = codes[i]
            if code == 0:
                colour, bold, italic = DEFAULT_FG, False, False
            elif code == 1:
                bold = True
            elif code == 3:
                italic = True
            elif code == 38 and codes[i + 1:i + 2] == [5]:
                colour = xterm_color(codes[i + 2])
                i += 2
            i += 1
        position = match.end()
    if position < len(line):
        runs.append((line[position:], colour, bold, italic))
    return runs


def git(repo, *args):
    env = {**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1",
           "GIT_AUTHOR_NAME": "preview", "GIT_AUTHOR_EMAIL": "preview@example.com",
           "GIT_COMMITTER_NAME": "preview", "GIT_COMMITTER_EMAIL": "preview@example.com"}
    subprocess.run(["git", "-C", str(repo), *args], env=env, check=True, capture_output=True)


def build_workspace(root):
    """A repository one commit ahead of its upstream, with staged, modified and new files."""
    home = root / "home"
    origin = root / "origin.git"
    project = home / "code" / "webapp"
    project.mkdir(parents=True)
    subprocess.run(["git", "init", "-q", "--bare", str(origin)], check=True)
    git(project, "init", "-q", "-b", "main")
    for name in ("app.py", "billing.py", "usage.py"):
        (project / name).write_text("# placeholder\n")
    git(project, "add", ".")
    git(project, "commit", "-q", "-m", "initial")
    git(project, "remote", "add", "origin", str(origin))
    git(project, "switch", "-q", "-c", "feat/usage-dashboard")
    git(project, "push", "-q", "-u", "origin", "feat/usage-dashboard")
    (project / "app.py").write_text("# routes\n")
    git(project, "commit", "-q", "-am", "add routes")
    (project / "billing.py").write_text("# staged change\n")
    git(project, "add", "billing.py")
    (project / "usage.py").write_text("# unstaged change\n")
    (project / "charts.py").write_text("# new file\n")
    transcript = root / "transcript.jsonl"
    transcript.write_text('{"permissionMode":"plan"}\n')
    return home, project, transcript


def render_statusline(root):
    home, project, transcript = build_workspace(root)
    payload = json.loads(FIXTURE.read_text())
    now = int(time.time())
    payload["workspace"].update(current_dir=str(project), project_dir=str(project))
    payload["transcript_path"] = str(transcript)
    # 30 spare seconds keep the countdowns from rounding down mid-run.
    payload["rate_limits"]["five_hour"]["resets_at"] = now + 2 * 3600 + 13 * 60 + 30
    payload["rate_limits"]["seven_day"]["resets_at"] = now + 3 * 86400 + 5 * 3600 + 30
    env = {**os.environ, "HOME": str(home), "COLUMNS": str(COLUMNS)}
    result = subprocess.run(["sh", str(STATUSLINE)], input=json.dumps(payload), cwd=project,
                            env=env, capture_output=True, text=True, check=True)
    lines = result.stdout.rstrip("\n").split("\n")
    # Pin the wall clock so regenerating the image only changes it when the output does.
    lines[-1] = CLOCK.sub(PREVIEW_CLOCK, lines[-1], count=1)
    return lines


def to_svg(lines):
    widest = max(len(SGR.sub("", line)) for line in lines)
    width = round(PADDING * 2 + widest * CHAR_WIDTH)
    height = TITLE_BAR + PADDING + LINE_HEIGHT * (len(lines) - 1) + PADDING
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" role="img" aria-label="Claude Code status line preview">',
        f'<rect width="{width}" height="{height}" rx="10" fill="{BACKGROUND}"/>',
    ]
    for offset, dot in zip((20, 40, 60), ("#ff5f57", "#febc2e", "#28c840")):
        parts.append(f'<circle cx="{offset}" cy="16" r="6" fill="{dot}"/>')
    parts.append(
        f'<g font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, \'DejaVu Sans Mono\', monospace" '
        f'font-size="{FONT_SIZE}" style="white-space:pre" xml:space="preserve">'
    )
    for row, line in enumerate(lines):
        y = TITLE_BAR + PADDING + row * LINE_HEIGHT
        spans = []
        for text, colour, bold, italic in styled_runs(line):
            attrs = f'fill="{colour}"'
            if bold:
                attrs += ' font-weight="700"'
            if italic:
                attrs += ' font-style="italic"'
            spans.append(f"<tspan {attrs}>{html.escape(text, quote=False)}</tspan>")
        parts.append(f'<text x="{PADDING}" y="{y}">{"".join(spans)}</text>')
    parts.append("</g></svg>")
    return "\n".join(parts) + "\n"


def main():
    with tempfile.TemporaryDirectory() as scratch:
        lines = render_statusline(Path(scratch))
    OUTPUT.parent.mkdir(exist_ok=True)
    OUTPUT.write_text(to_svg(lines))
    print(f"wrote {OUTPUT.relative_to(REPO)}")


if __name__ == "__main__":
    main()
