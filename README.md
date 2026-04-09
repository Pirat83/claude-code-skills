# Claude Code Skills

Reusable, production-tested skills for [Claude Code](https://claude.ai/code) — Anthropic's CLI coding agent. Each skill adds a visual feedback loop or structured workflow that Claude Code can't do out of the box.

**Core idea:** Claude Code is multimodal. It can render output to PNG or take screenshots, then `Read` the image back to review its own work. These skills formalize that into structured verify-and-iterate workflows.

## Quick Start

Copy any skill directory into your project's `.claude/skills/`:

```bash
# Clone the repo
git clone https://github.com/Pirat83/claude-code-skills.git

# Copy the skill you want
cp -r claude-code-skills/matplotlib-render-review/ /path/to/your/project/.claude/skills/
```

That's it. Claude Code auto-discovers skills in `.claude/skills/`.

## Skills

| Skill | Description | Use case |
|-------|-------------|----------|
| [`matplotlib-render-review`](matplotlib-render-review/) | Render charts to PNG, read back with vision, iterate | Any matplotlib visualization work |
| [`gws-sheets-verify`](gws-sheets-verify/) | Screenshot Google Sheets via Playwright, verify visually | Google Sheets automation (sorting, formatting, borders) |
| [`tune-up`](tune-up/) | 6-phase audit of your Claude Code setup | Permissions bloat, stale agents, skill quality |

## Features

- **Visual feedback loops** — Claude Code generates output, sees it, and iterates. No more blind code generation.
- **Structured self-review checklists** — each skill includes domain-specific items to check (chart readability, spreadsheet data integrity, permission hygiene).
- **Render-Review-Refine pattern** — max 3 cycles, then report to user. Prevents infinite loops.
- **Multimodal `Read` tool** — Claude Code can read PNG/JPEG files natively. These skills leverage that for visual verification.

## Detailed Installation

### matplotlib-render-review

Adds a render-review-refine workflow for matplotlib charts. After generating chart code, Claude renders it to PNG, reads the image back, and checks layout, data correctness, colors, and axes.

```bash
cp -r matplotlib-render-review/ /path/to/project/.claude/skills/
```

**Requirements:** Python with matplotlib, Poetry (for `poetry run`)

**How it works:**
1. Claude writes chart code as a standalone `.py` script
2. Executes via the included `render_review.py` harness
3. Reads the rendered PNG with the multimodal `Read` tool
4. Applies a self-review checklist (layout, data, colors, axes)
5. Iterates up to 2 more times if issues found

### gws-sheets-verify

Adds a visual feedback loop for Google Sheets operations. After any write (sort, format, insert rows), Claude takes a Playwright screenshot and verifies the result.

```bash
cp -r gws-sheets-verify/ /path/to/project/.claude/skills/
```

**Requirements:** [Playwright MCP server](https://github.com/anthropics/claude-code/tree/main/plugins/playwright), Google Sheets API access, browser authenticated with Google

**How it works:**
1. Claude executes a Sheets API command
2. Opens the spreadsheet in Playwright, takes a screenshot
3. Reads the screenshot, checks data integrity, sort order, borders
4. Fixes and re-verifies if issues found

**Key rules enforced:**
- Sort entire rows, never individual columns
- Use `copyPaste PASTE_FORMAT` for borders (not `updateBorders`)
- Always verify the last data row after bulk operations

### tune-up

Audits your Claude Code workflow across 6 phases: permissions, agents, skills, CLAUDE.md quality, summary, and apply. Each phase has concrete commands and structured output templates.

```bash
cp -r tune-up/ ~/.claude/skills/  # Install globally
# or
cp -r tune-up/ /path/to/project/.claude/skills/  # Install per-project
```

**Requirements:** None beyond Claude Code itself

**How it works:**
1. Scans 4 settings files for permission bloat
2. Checks agents for staleness and generic content
3. Audits skills for hardcoded permissions and stale references
4. Validates CLAUDE.md for contradictions and outdated instructions
5. Presents a severity-ranked summary
6. Applies approved fixes

## Contributing

To add a new skill:

1. Create a directory with a descriptive name (e.g., `docker-compose-verify/`)
2. Add a `SKILL.md` with [Claude Code skill frontmatter](https://docs.anthropic.com/en/docs/claude-code/skills)
3. Include a self-review checklist specific to your domain
4. Test it in a real project
5. Open a PR

## License

MIT
