import Foundation

/// 基于计数的路径枚举器（issue #162）。
///
/// 旧实现物化全部根到叶路径，开局库是含大量换序的 DAG，路径数随深度指数增长，
/// 大库会卡死或耗尽内存。本枚举器只做记忆化计数（O(节点+边)），
/// 用「子节点按 targetFenId 升序」的稳定字典序定义路径序号，
/// 支持 O(深度×分支) 的按序号取路径与路径反查序号，
/// 随机一局 = 均匀随机序号 + 按序号取路径，与旧实现的均匀分布一致。
final class GamePathEnumerator {
    private let databaseView: DatabaseView
    /// 枚举起点前缀（锁定步之前的路径），所有路径都以它开头
    private let prefix: [Int]
    private var countCache: [Int: Int] = [:]
    private var visiting: Set<Int> = []

    init(databaseView: DatabaseView, prefix: [Int]) {
        self.databaseView = databaseView
        self.prefix = prefix
    }

    /// 子节点稳定枚举顺序：targetFenId 升序
    private func children(of fenId: Int) -> [Int] {
        guard databaseView.containsFenId(fenId) else { return [] }
        return databaseView.moves(from: fenId)
            .compactMap { $0.targetFenId }
            .sorted()
    }

    /// 从 fenId 出发到叶的路径数（记忆化）。
    /// 递归栈上再次遇到的节点（环）贡献 0；无可走子节点的局面计 1（自身即叶）。
    /// 在无环图（开局库的常态）上与逐条枚举的计数完全一致
    func pathCount(from fenId: Int) -> Int {
        if let cached = countCache[fenId] { return cached }
        if visiting.contains(fenId) { return 0 }
        visiting.insert(fenId)
        defer { visiting.remove(fenId) }

        var total = 0
        for child in children(of: fenId) {
            total += pathCount(from: child)
        }
        let result = total == 0 ? 1 : total
        countCache[fenId] = result
        return result
    }

    /// 以 prefix 为前缀的根到叶路径总数
    var totalCount: Int {
        guard let start = prefix.last, databaseView.containsFenId(start) else { return 0 }
        return pathCount(from: start)
    }

    /// fenId → 路径数 的完整映射（与旧 generateAllGamePaths 的第二个返回值语义一致：
    /// 前缀节点计 1，起点为总数，其余为各自出发的路径数）
    func pathCountMap() -> [Int: Int] {
        let total = totalCount
        var map = countCache
        for fenId in prefix.dropLast() { map[fenId] = 1 }
        if let start = prefix.last { map[start] = total }
        return map
    }

    /// 第 index 条路径（0-based，字典序）；序号越界返回 nil
    func path(at index: Int) -> [Int]? {
        guard index >= 0, index < totalCount else { return nil }
        var path = prefix
        var pathSet = Set(prefix)
        var idx = index
        var fenId = prefix.last!

        while true {
            // 排除已在路径上的节点（环防护，与计数语义近似一致）
            let kids = children(of: fenId).filter { !pathSet.contains($0) }
            if kids.isEmpty { return path }

            var advanced = false
            for child in kids {
                let count = pathCount(from: child)
                if idx < count {
                    path.append(child)
                    pathSet.insert(child)
                    fenId = child
                    advanced = true
                    break
                }
                idx -= count
            }
            // 子节点计数耗尽（仅环等退化情况）：当前节点视为叶
            if !advanced { return path }
        }
    }

    /// 路径 → 序号。路径必须以 prefix 开头；
    /// 传入非完整路径（未到叶）时返回「以它为前缀的第一条路径」的序号
    func index(of path: [Int]) -> Int? {
        guard path.count >= prefix.count,
              Array(path.prefix(prefix.count)) == prefix else { return nil }

        var idx = 0
        var pathSet = Set(prefix)
        var fenId = prefix.last!

        for next in path.dropFirst(prefix.count) {
            let kids = children(of: fenId).filter { !pathSet.contains($0) }
            var found = false
            for child in kids {
                if child == next {
                    found = true
                    break
                }
                idx += pathCount(from: child)
            }
            guard found else { return nil }
            pathSet.insert(next)
            fenId = next
        }
        return idx
    }
}
