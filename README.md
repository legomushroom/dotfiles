# dotfiles

```shell
curl https://raw.githubusercontent.com/legomushroom/dotfiles/main/setup.sh | sh -s
```

## skills

`copilot/skills/` holds agent skills, installed to `~/.copilot/skills/` by
`setup.sh`. Each folder name must match the `name` in its `SKILL.md`. Edit them
here and re-run `setup.sh`; the installer replaces each skill folder wholesale,
so a file deleted here goes away on the next run.

- `pr-review-babysitting` - drive Copilot review on a PR or stack to completion, then a local Claude review until nothing blocking or should-fix is left, and notify when each PR's loop stops
- `pr-approval-babysitting` - keep your approval on others' PRs alive through pushes until they merge, and flag their merge conflicts
- `pr-review-comment` - phrase a finding as a paste-able review comment
