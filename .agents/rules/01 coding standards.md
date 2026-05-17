---
trigger: always_on
---

---
name: coding-standards
description: General coding standards applied across all languages in the Sangeet AI codebase
activation: always
---

# Coding Standards

Universal rules that apply regardless of language. Language-specific rules are layered on top in `02-swift-macos.md` and `03-python-inference.md`.

## Naming

- Names describe what something *is* or *does*, not how it is implemented. `restorationPipeline` not `pipelineV2Manager`.
- No Hungarian notation, no `m_` prefixes, no type prefixes (`strName`, `iCount`). The type system tells us the type.
- Acronyms are uppercase only when at most two characters: `UI`, `DSP`, `URL` are fine; `Lufs` not `LUFS`, `Json` not `JSON` in identifiers. This matches Swift's API design guidelines and reads better in long names.
- Boolean names read as questions: `isReady`, `hasFinished`, `shouldRetry`. Never `flag`, `status`, `state` for a boolean.
- Avoid `Manager`, `Handler`, `Helper`, `Util` suffixes — they signal that the class does not have a clear responsibility. Rename until the name describes the actual job.

## Function design

- A function does one thing. If you need the word "and" in the function name, split it.
- Max 40 lines per function as a soft cap. Beyond that, extract sub-functions. Exception: top-level orchestration functions where breaking up would obscure flow.
- Max 3 positional parameters. Beyond that, take a struct/dataclass/options object.
- No flag parameters (`doRestoration(audio, fast=True)`). Split into two functions or pass a strategy enum.
- Return early. Avoid deeply nested conditionals. Guard clauses at the top of functions are preferred over nested `else` branches.

## Comments

- Code says *what*, comments say *why*. Do not comment what the code already says.
- Comment when:
  - The reason for a non-obvious choice (`// using FFT size 2048 to balance frequency resolution vs transient smearing for tabla`)
  - A workaround for a library bug, with a link to the issue
  - A performance constraint that the next reader needs to know
  - Domain knowledge that is not in the code (audio engineering rationale, restoration theory)
- Do not write TODO comments without an owner and a ticket reference: `// TODO(rahul, SAI-142): handle 24-bit input`.
- Doc comments on every public API. Internal helpers can be undocumented if names are clear.

## Error handling

- Errors are values, not exceptions, where the language supports it (Swift `Result`, Python `Result`-like patterns where appropriate, or typed exception hierarchies).
- Never silently swallow errors. Every `except Exception` or `try?` needs a comment explaining why.
- User-facing error messages are written in plain English. No stack traces shown to users. No "Error code 0x80004005". Instead: "Sangeet couldn't read this file — it may be corrupted or in an unsupported format."
- Log errors with enough context to reproduce: input file path, parameters, timestamps. Never log audio sample data.

## Logging

- Three levels only: `debug`, `info`, `error`. Drop `warn`, `trace`, `verbose` — they create decision fatigue.
- `info` for state transitions a user would care about ("restoration started", "stage 3 of 5 complete").
- `error` only for things that genuinely block work. A degraded stage that falls back to a simpler path is `info`, not `error`.
- Never log file contents, audio samples, or full file paths in production builds. Hash file paths if you need a stable identifier.

## Imports and dependencies

- Imports grouped: stdlib first, third-party second, local third, separated by blank lines.
- Within each group, alphabetical.
- No wildcard imports (`from x import *`).
- New dependencies require ADR (see `AGENTS.md` §5). Adding a dependency to "save a few lines" is rejected by default.

## Commits

- Conventional Commits format: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`. Scope optional but encouraged: `feat(router): add hum detection at 50/60 Hz harmonics`.
- One logical change per commit. If the PR has 12 commits and the message is "fixes", the PR is not ready for review.
- Commit subject under 72 characters. Body wrapped at 80.
- Reference the issue: `Closes SAI-142` at the bottom of the body.

## What we do not do

- We do not write code that exists only to satisfy a future hypothetical requirement.
- We do not introduce abstractions before we have two concrete use cases.
- We do not refactor outside the scope of the PR. File a follow-up issue instead.
- We do not commit commented-out code. Delete it; git remembers.
- We do not commit binary files larger than 100 KB into the repo. Use Git LFS or the eval corpus storage.