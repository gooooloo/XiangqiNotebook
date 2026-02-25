---
name: resolve-issue
description: Guide the full lifecycle of resolving a GitHub issue
argument-hint: [issue-number]
---

Guide the full lifecycle of resolving a GitHub issue — from selection through planning, implementation, PR creation, code review, to final closure.

## Steps

### 1. Select GitHub Issue
- If `$ARGUMENTS` contains an issue number, use it
- Otherwise, list open issues with `gh issue list` and ask the user to pick one
- Fetch issue details with `gh issue view <number>`
- Rename the current session to `GitHub-issue-#<number>` style

### 2. Plan
- Enter plan mode via `EnterPlanMode`
- Explore the codebase to understand the issue
- Design an implementation approach
- Present the plan for user approval

### 3. Implement
- Execute the approved plan
- Run tests to verify changes
- Ask the user to verify the changes look correct

### 4. Commit & Create PR
- Ask the user whether this PR should close the issue (default: yes)
- Run `git status` to see all changed files (never use `-uall`)
- Run `git diff` to see staged and unstaged changes
- Run `git log --oneline -5` to see recent commit message style
- Create a descriptive branch name based on the changes (e.g. `fix/xxx`, `feature/xxx`)
- Stage only the relevant files by name (do NOT use `git add -A` or `git add .`)
- Exclude unrelated changes (e.g. local Xcode config like `DEVELOPMENT_TEAM`)
- Write a detailed commit message:
  - First line: short summary in the style of recent commits
  - Blank line, then a body explaining **what changed and why**
  - If the user chose to close the issue, add `Closes #<issue-number>`; otherwise add `Related to #<issue-number>`
  - End with `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`
- Push the branch to origin with `-u` flag
- Create a PR using `gh pr create` with:
  - A concise title (under 70 chars)
  - Body containing:
    - `## Summary` with bullet points describing the changes
    - `Closes #<issue-number>` or `Related to #<issue-number>` (based on user's choice)
    - `## Test plan` with a checklist of verification steps
    - Footer: `🤖 Generated with [Claude Code](https://claude.com/claude-code)`
- Show the PR URL to the user

### 5. Code Review
- Wait for the user to say review is ready or share review comments
- Fetch review comments with `gh pr view <pr-number>` and `gh api repos/{owner}/{repo}/pulls/<pr-number>/comments`
- Help resolve each comment — make code changes, push updates
- Repeat until review is approved

### 6. Post-Merge Cleanup
- Once the user confirms the PR is merged, verify:
  - PR is merged: `gh pr view <pr-number> --json state`
  - Issue is closed: `gh issue view <issue-number> --json state`
- If the issue is not closed, close it: `gh issue close <issue-number>`
- Switch back to main branch: `git checkout main && git pull`
- Delete the local feature branch
- Report final status
- End the session
