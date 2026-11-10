# Working rules

The conventions this repository is written to. They were previously kept in
root `AGENTS.md` and `CLAUDE.md`. Those files are no longer committed: the
plugin directory is installed into `~/.config/omarchy/plugins/`, where a
coding agent that wanders in can read a root instruction file as though the
project had authored instructions for it. Keeping them out of the published
tree removes that surface. Keep your own copy locally if you use an agent;
both names are ignored by git.

## Commits

- Never author or co-author a commit on someone's behalf without being asked.
- At the end of a complete piece of work, propose three commit messages rather
  than committing. Fifty characters at most.

## Comments

- Very few, usually one line.
- Plain English, no jargon.
- No dates. A comment that says when something was decided goes stale the day
  after it is written.

## Tests

- Red then green. Write the failing test first, watch it fail, then make it
  pass.

## Checks

- `./scripts/test.sh` is the whole suite, and CI runs exactly that script. It never
  opens a window on the live desktop.
- `./scripts/lint-qml.sh` runs qmllint against the real Omarchy controls, and any
  warning fails it.
- `tests/integration/PagesSmoke.qml` walks the keyboard cursor over every real page,
  and any QML warning fails it.
- `./scripts/ui-preview.sh` screenshots every page, in any theme and size, without
  touching the desktop or a real account. Look at them when changing the interface.

## Dependencies

- When one does not behave as expected, research and test it before writing a
  replacement. All code is a liability, and the best liability is one someone
  else maintains.
- Pin the latest version when adding one.
