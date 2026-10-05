# Antigravity Rules — Sangeet AI

This is the agent rules package for the Sangeet AI macOS audio restoration project. Drop these files into your project root and Antigravity (and Cursor, Claude Code, Windsurf — they all read this format as of Antigravity v1.20.3) will pick them up automatically.

## What's in this package

```
AGENTS.md                     ← Root project context (cross-tool standard)
.agents/
├── rules/                    ← Workspace rules, auto-loaded by Antigravity
│   ├── 01-coding-standards.md    (always-on)
│   ├── 02-swift-macos.md         (glob-activated on .swift)
│   ├── 03-python-inference.md    (glob-activated on inference daemon files)
│   ├── 04-audio-dsp.md           (glob-activated on DSP files)
│   ├── 05-grpc-contracts.md      (glob-activated on .proto and generated)
│   ├── 06-testing-and-eval.md    (glob-activated on tests)
│   ├── 07-cultural-fidelity.md   (manual, @-mentioned when relevant)
│   ├── 08-licensing-and-ip.md    (always-on)
│   └── 09-writing-and-comms.md   (glob-activated on .md and user-facing strings)
└── workflows/                ← Slash-command playbooks
    ├── add-restoration-stage.md  (/add-restoration-stage)
    ├── benchmark-pipeline.md     (/benchmark-pipeline)
    ├── ship-release.md           (/ship-release)
    └── debug-audio-quality.md    (/debug-audio-quality)
```

## Activation modes

Antigravity rule files use frontmatter to declare when they activate. This package uses three modes:

| Mode | Behavior | Used for |
|------|----------|----------|
| `always` | Loaded into every agent context | Coding standards, licensing — things that always apply |
| `globs` | Loaded only when the agent is working on matching files | Swift-only rules, Python-only rules — saves context budget |
| `manual` | Loaded only when explicitly referenced with `@rule-name` | Cultural fidelity — long, important, but not always relevant |

The always-on rules are kept short to leave context budget for the codebase itself. The detailed domain knowledge lives in glob-activated and manual rules.

## How to use this

### One-time setup

1. Copy this entire structure into your project root:
   ```bash
   cp AGENTS.md /path/to/sangeet-ai/
   cp -r .agents /path/to/sangeet-ai/
   ```

2. Commit them to git so the whole team sees the same rules:
   ```bash
   cd /path/to/sangeet-ai
   git add AGENTS.md .agents/
   git commit -m "chore: add Antigravity workspace rules"
   ```

3. Open the project in Antigravity. The rules load automatically. Confirm by typing `@` in the agent panel — you should see the rule files listed.

### Day to day

- The agent will follow the always-on rules without prompting. You will see this in the form of the agent rejecting non-permissive licenses, refusing to commit large audio files, using Conventional Commits format, etc.
- Glob-activated rules turn on when the agent works in matching files. Working in `.swift`? It picks up `02-swift-macos.md` and `04-audio-dsp.md` automatically.
- For complex tasks, trigger a workflow with the slash command. The agent walks through the steps and pauses at gates.

### When the agent gets it wrong

The most common failure: the agent follows generic AI-assistant defaults (overly polite, marketing-speak, over-eager to please) instead of the project's voice. When this happens, reference the writing rules explicitly:

> Read `.agents/rules/09-writing-and-comms.md` and rewrite.

Or for restoration-chain changes that smell wrong:

> Reference `.agents/rules/07-cultural-fidelity.md`. Does this change risk any protected signature?

Antigravity sometimes needs an explicit nudge to consult a specific rule file, especially for the `manual`-activation ones. That is by design — manual rules are heavy, and you do not want them in every context.

## Adapting these rules

These rules encode opinionated decisions specific to Sangeet AI. As the project evolves, the rules will need updates.

### Updating rules

- Treat rule changes like code changes. PR with reviewer. Explain why.
- Do not delete rules when they become "obvious" — newcomers do not have the history.
- Do add the date and rationale when superseding a rule.

### Adding new rules

- New rule files: use the same frontmatter format. Pick the right activation mode — `always` is precious, do not abuse it.
- Number rule files in load order if order matters. The current numbering goes from general (01) to specific (09).
- Cross-reference between rules with explicit file paths. Antigravity does not auto-link.

### Removing rules

- A rule that everyone agrees on does not need to be a rule.
- A rule the agent already follows naturally (because it is in the training data) does not need to be a rule.
- Cut rules ruthlessly. Long rule files dilute attention.

## Maintenance

This package was written for the Phase 1 scope defined in `AI_Audio_Restoration_Development_Plan.docx`. As the project enters Phases 2, 3, and 4, expect:

- New rule files for cloud infrastructure (Phase 4)
- New rule files for the Indian-music specialized model training pipeline (Phase 3)
- The `cultural-fidelity` rule to expand as we learn more from real user audio
- The `licensing-and-ip` rule to be updated with new model audits at each integration

When in doubt about what a rule says, read the rule. When the rule is wrong, fix the rule, do not work around it.
