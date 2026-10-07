# iPhone TestFlight 自动发布

GitHub 仓库 `gooooloo/XiangqiNotebook` 的 `main` 分支发生 push 时，Xcode Cloud 的 `Default` workflow 自动运行：

1. 使用共享 scheme `XiangqiNotebook` 归档 iOS。
2. 使用 App Store Connect 分发准备并上传构建。
3. Apple 处理完成后，自动分发到内部测试群组「自己测试」。

同分支的新构建会取消尚未完成的旧构建。workflow 只包含 iOS Archive；macOS helper 的本地构建不在此流程中。

## 版本编号

- `Config/Version.xcconfig` 控制 `MARKETING_VERSION`。当前测试版本为 `1.0.9`。
- Xcode Cloud 使用 `CI_BUILD_NUMBER` 自动递增构建编号，本地构建继续使用 git commit 数。
- 一个版本在 App Store 发布后，再上传测试构建前需要提高 `MARKETING_VERSION`，否则 Apple 会拒绝已关闭版本的上传。
- `Info.plist` 已声明仅使用免申报加密。如果以后引入其他加密实现，需要重新评估该声明。

## 手机更新

iPhone 的 TestFlight 中打开「象棋笔记本」并开启自动更新。Apple 处理和设备安装有延迟；也可在 TestFlight 中手动点击更新。

## 查看结果

在 App Store Connect 的 Xcode Cloud 中查看归档及 TestFlight 后续操作；在 App 的 TestFlight 页确认版本已处理并加入「自己测试」。云端 Archive 成功不等于手机已经安装更新。
