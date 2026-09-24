# dotfiles

```shell
curl https://raw.githubusercontent.com/legomushroom/dotfiles/main/setup.sh | sh -s
```

## skills

`copilot/skills/` holds agent skills, installed to `~/.copilot/skills/` by
`setup.sh`. Each folder name must match the `name` in its `SKILL.md`. Edit them
here and re-run `setup.sh`; the installer replaces each skill folder wholesale,
so a file deleted here goes away on the next run.

- `pr-review-babysitting` - drive bot review on a PR or stack to completion
- `pr-review-comment` - phrase a finding as a paste-able review comment
