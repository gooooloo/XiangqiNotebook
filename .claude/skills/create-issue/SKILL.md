---
name: create-issue
description: Create a new GitHub issue with label (bug or enhancement)
argument-hint: [description of the issue]
---

Create a new GitHub issue on the current repository.

## Steps

### 1. Determine issue type and content

- If `$ARGUMENTS` is provided, analyze the text to recommend a default issue type (`bug` or `enhancement`) and draft a title and body
- Ask the user to confirm or change the issue type using `AskUserQuestion`:
  - Question: "Issue 类型？"
  - Options: `bug` and `enhancement`
  - If you have a recommendation based on `$ARGUMENTS`, mark it with "(Recommended)"
- If `$ARGUMENTS` is empty, ask the user to describe the issue first, then ask for the type

### 2. Draft issue title and body

- If `$ARGUMENTS` is provided, draft a concise Chinese title and a body based on the input
- The body should be written in Chinese, structured clearly:
  - For **bug**: include "问题描述" and "期望行为" sections
  - For **enhancement**: include "功能描述" and "动机" sections
- Show the drafted title and body to the user for confirmation
- Apply any changes the user requests

### 3. Create the issue

- Use `gh issue create` with:
  - `--title`: the confirmed title
  - `--body`: the confirmed body
  - `--label`: `bug` or `enhancement` based on user's choice
- Show the issue URL to the user
