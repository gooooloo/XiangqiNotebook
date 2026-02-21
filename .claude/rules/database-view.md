# DatabaseView 数据访问规则

## 核心原则
- 基于 fenId 的数据必须通过 `DatabaseView` 访问，禁止直接通过 `DatabaseData` 访问
- 访问基于 fenId 的数据前，使用 `containsFenId(_:)` 进行入口验证
- 所有着法相关方法强制执行严格筛选：起点和终点都必须在范围内
- 禁止直接访问 `DatabaseData.fenObjects2`；必须使用 `DatabaseView.getFenObject(_:)`

## 常用模式

1. **检查局面是否在范围内：**
```swift
if databaseView.containsFenId(fenId) {
    // 该局面在当前视图中可访问
}
```

2. **获取 FenObject：**
```swift
if let fenObject = databaseView.getFenObject(fenId) {
    // 使用 fenObject
}
```

3. **获取某个局面的后续着法：**
```swift
// 先验证起点
guard databaseView.containsFenId(sourceFenId) else { return [] }
let moves = databaseView.moves(from: sourceFenId)
// 返回的所有着法的终点也都在范围内
```

4. **查找特定着法：**
```swift
if let move = databaseView.move(from: sourceFenId, to: targetFenId) {
    // 着法存在且两个端点都在范围内
}
```

## 直接访问（无筛选）
- 对不需要筛选的数据，使用 DatabaseView 的透传属性：
  - `fenToId`、`moveObjects`、`moveToId`、`bookObjects`、`gameObjects`
- 这些属性直接访问底层 DatabaseData，不经过筛选
