# 跨平台开发规则

- 使用条件编译处理平台差异：`#if os(macOS)`、`#if os(iOS)`
- iPhone: 触控优化，简化界面
- iPad: 增强界面，更多控件
- Mac: 完整桌面体验，支持多窗口和键盘快捷键

## iCloud 文件协调
操作 iCloud 文件时：
- 始终使用 `iCloudFileCoordinator.shared` 进行文件协调
- 使用 `DatabaseStorage.isICloudURL()` 或 `SessionStorage.isICloudURL()` 检查 URL 是否为 iCloud 路径
- 使用 `coordinatedRead()` 读取文件
- 使用 `coordinatedWrite()` 写入文件
- 协调器自动处理基于信号量的同步
