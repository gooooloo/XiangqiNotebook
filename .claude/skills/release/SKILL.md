---
name: release
description: Update CHANGELOG, commit, tag, and push for Xcode Cloud
disable-model-invocation: true
---

Create a new release for 象棋笔记本.

## Steps

### 1. Determine version number
- Run `git rev-list --count HEAD` to get the current commit count
- The new version will be `1.0.<count + 1>` (the +1 accounts for the changelog commit about to be made)
- Tell the user the determined version number

### 2. Gather and draft changelog entries
- Find the most recent version tag (e.g. `git describe --tags --abbrev=0`)
- Run `git log <last-tag>..HEAD --oneline` to get all commits since the last release
- Read the actual code diffs (`git diff <last-tag>..HEAD`) or changed files to understand what each commit actually does
- Filter to **user-facing changes only**: new features, UI improvements, bug fixes that users would notice
- **Exclude**: refactoring, code cleanup, test changes, build config changes, documentation updates, and anything purely internal that users would not experience
- **Do NOT copy-paste git commit messages.** Summarize changes in your own words, written in Chinese from the end user's perspective. Group related commits into single entries when appropriate. (e.g. "新增XX功能", "修复XX问题", "改进XX体验")

### 3. Draft CHANGELOG.md update
- Add a new section above the previous release entry with the determined version number
- Include the filtered changelog entries as a bulleted list
- Keep the `---` separator between versions
- Do NOT include commit hashes in version headings

### 4. Review checkpoint (MUST STOP HERE)
- Show the user the full updated CHANGELOG.md content
- Ask the user to review and confirm, or request changes
- Do NOT proceed until the user explicitly approves
- If the user requests changes, apply them and ask for review again

### 5. Commit
- Only after user approval, stage only `CHANGELOG.md`
- Commit message: `Update CHANGELOG.md with <version> release notes`

### 6. Verify commit count
- Run `git rev-list --count HEAD` and confirm it matches the expected version number
- If it doesn't match, warn the user and stop

### 7. Create git tag
- `git tag v<version>`

### 8. Push tag and main
- `git push origin main --tags`

### 9. Report
- Confirm the tag has been pushed
- Remind the user that Xcode Cloud should pick up the new tag
