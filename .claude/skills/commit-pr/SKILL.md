---
name: commit-pr
description: Create a git commit and open a pull request
disable-model-invocation: true
argument-hint: [issue-number]
---

Create a git commit for the current changes and open a pull request.

Every PR **must** be linked to a GitHub issue. Do NOT skip this step.

## Steps

### 1. Determine the GitHub issue number
- If `$ARGUMENTS` contains an issue number, use it
- Otherwise, search the conversation history for any mention of a GitHub issue (e.g. "issue #8", "Issue 8", references to a specific issue)
- If still not found, ask the user which issue this PR should link to — do NOT proceed without an issue number
- After determining the issue number, ask the user whether this PR should close the issue (default: yes)

### 2. Review changes
- Run `git status` to see all changed files (never use `-uall`)
- Run `git diff` to see staged and unstaged changes
- Run `git log --oneline -5` to see recent commit message style
- Identify which files are relevant to the current task
- Exclude unrelated changes (e.g. local Xcode config like `DEVELOPMENT_TEAM`)

### 3. Create branch
- Create a descriptive branch name based on the changes (e.g. `fix/xxx`, `feature/xxx`)
- Branch off from the current branch

### 4. Commit
- Stage only the relevant files by name (do NOT use `git add -A` or `git add .`)
- Write a detailed commit message:
  - First line: short summary in the style of recent commits (e.g. `Fix: ...`, `Feature: ...`)
  - Blank line, then a body explaining **what changed and why**
  - Include specific details: old values → new values, affected files/components
  - If the user chose to close the issue, add `Closes #<issue-number>`; otherwise add `Related to #<issue-number>`
  - End with `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`

### 5. Push and create PR
- Push the branch to origin with `-u` flag
- Create a PR using `gh pr create` with:
  - A concise title (under 70 chars)
  - Body containing:
    - `## Summary` with bullet points describing the changes
    - `Closes #<issue-number>` or `Related to #<issue-number>` (based on user's choice)
    - `## Test plan` with a checklist of verification steps
    - Footer: `🤖 Generated with [Claude Code](https://claude.com/claude-code)`

### 6. Report
- Show the PR URL to the user
