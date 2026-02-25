# Plan Mode 规则

## GUI 变更预览
- 当 plan 涉及 GUI/UI 改动时，必须生成一个静态 HTML 文件供用户审查
- HTML 文件应尽可能还原改动后的界面布局和视觉效果
- 将 HTML 文件写入 `/private/tmp/claude/` 目录，并告知用户文件路径以便在浏览器中打开审查
