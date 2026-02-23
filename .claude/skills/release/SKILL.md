---
name: release
description: Update version, CHANGELOG, commit, tag, and push for Xcode Cloud
disable-model-invocation: true
---

Create a new release for 象棋笔记本.

## Steps

### 1. Determine version number
- Read the current version from `Config/Version.xcconfig` (the `MARKETING_VERSION` value)
- Suggest incrementing the patch version (e.g. `1.0.1` → `1.0.2`)
- Ask the user to confirm or specify a different version number

### 2. Gather and draft changelog entries
- Find the most recent version tag (e.g. `git describe --tags --abbrev=0`)
- Run `git log <last-tag>..HEAD --oneline` to get all commits since the last release
- Read the actual code diffs (`git diff <last-tag>..HEAD`) or changed files to understand what each commit actually does
- Filter to **user-facing changes only**: new features, UI improvements, bug fixes that users would notice
- **Exclude**: refactoring, code cleanup, test changes, build config changes, documentation updates, and anything purely internal that users would not experience
- **Do NOT copy-paste git commit messages.** Summarize changes in your own words, written in Chinese from the end user's perspective. Group related commits into single entries when appropriate. (e.g. "新增XX功能", "修复XX问题", "改进XX体验")

### 3. Update version and draft CHANGELOG.md
- Update `MARKETING_VERSION` in `Config/Version.xcconfig` to the new version
- Add a new section above the previous release entry in `CHANGELOG.md` with the new version number
- Include the filtered changelog entries as a bulleted list
- Keep the `---` separator between versions
- Do NOT include commit hashes in version headings

### 4. Review checkpoint (MUST STOP HERE)
- Show the user the changes to `Config/Version.xcconfig` and the full updated `CHANGELOG.md` content
- Ask the user to review and confirm, or request changes
- Do NOT proceed until the user explicitly approves
- If the user requests changes, apply them and ask for review again

### 5. Commit
- Only after user approval, stage `CHANGELOG.md` and `Config/Version.xcconfig`
- Commit message: `Update CHANGELOG.md with <version> release notes`

### 6. Create git tag
- `git tag v<version>`

### 7. Push tag and main
- `git push origin main --tags`

### 8. Report
- Confirm the tag has been pushed
- Note the build number (from `git rev-list --count HEAD`) that will be used
- Remind the user that Xcode Cloud should pick up the new tag
