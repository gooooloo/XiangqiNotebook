import Foundation
import SwiftUI

#if os(iOS) || os(tvOS) || os(watchOS)
// Define KeyEquivalent for iOS platforms
typealias KeyEquivalent = Character
#endif

/// 集中定义所有操作和快捷键
class ActionDefinitions {

    /// 所有模式的便捷集合，用于表示一个动作在所有模式下都可见
    static let allModes = Set(AppMode.allCases)
    // 按钮名称常量
    enum ActionKey: String, CaseIterable {
        case toStart
        case stepBack
        case stepForward
        case toEnd
        case nextVariant
        case previousPath  // 新增：复习上局
        case nextPath      // 新增：复习下局
        
        case queryScore
        case openYunku
        case random
        case fix
        
        case save
        case backup
        case restore
        case deleteMove
        case removeMoveFromGame  // 新增：从棋局中删除此招
        case checkDataVersion
        case flip
        case deleteScore
        case flipHorizontal
        case markPath  // 新增：标记路径按钮
        case referenceBoard  // 新增：参考棋盘窗口
        case stepLimitation  // 新增：步数限制按钮
        case inputGame  // 新增：录入棋局按钮
        case browseGames  // 新增：棋局浏览器按钮
        case playRandomNextMove  // 新增：随机走法按钮
        case hintNextMove       // 新增：提示按钮
        case reviewThisGame
        case practiceNewGame
        case focusedPractice
        case searchCurrentMove
        case importPGN  // 新增：导入PGN按钮
        case autoAddToOpening  // 新增：自动完善开局库
        case jumpToNextOpeningGap  // 新增：跳转到下一个开局缺口
        case queryEngineScore  // 手动触发引擎评估
        case queryAllEngineScores  // 搜索本对局每一步的引擎分数

        // toggles
        case setFilterNone
        case toggleFilterRedOpeningOnly
        case toggleFilterBlackOpeningOnly
        case toggleFilterRedRealGameOnly
        case toggleFilterBlackRealGameOnly
        case setFilterFocusedPractice
        case toggleFilterSpecificGame
        case toggleFilterSpecificBook
        case inRedOpening
        case inBlackOpening
        case toggleLock
        case toggleCanNavigateBeforeLockedStep  // 新增：导航锁定按钮
        case toggleAutoExtendGameWhenPlayingBoardFen  // 新增：自动拓展按钮
        case togglePracticeMode  // 新增：练习模式按钮
        case toggleShowPath  // 新增：显示路径按钮
        case toggleShowAllNextMoves  // 新增：显示所有下一步按钮
        case toggleBookmark  // 新增：显示路径按钮
        case toggleIsCommentEditing
        case toggleAllowAddingNewMoves  // 新增：允许增加新走法

        case showBookmarkListIOS
        case showMoreActionsIOS
        case showEditCommentIOS
    }
    
    // MARK: - 快捷键类型定义
    
    enum ShortcutType {
        case single(Character)
        case modified(KeyModifiers, Character)
        case sequence(String)
        
        /// 获取用户友好的显示文本
        func getDisplayText() -> String {
            switch self {
            case .single(let char):
                return Self.arrowDisplayText(char) ?? String(char)
            case .modified(let modifiers, let char):
                return formatModifiedKey(modifiers: modifiers, key: char)
            case .sequence(let sequence):
                return sequence
            }
        }

        /// 箭头键等特殊字符的显示映射
        private static func arrowDisplayText(_ char: Character) -> String? {
            #if os(macOS)
            switch char {
            case KeyEquivalent.leftArrow.character: return "←"
            case KeyEquivalent.rightArrow.character: return "→"
            case KeyEquivalent.upArrow.character: return "↑"
            case KeyEquivalent.downArrow.character: return "↓"
            default: return nil
            }
            #else
            return nil
            #endif
        }
        
        /// 格式化修饰键组合
        private func formatModifiedKey(modifiers: KeyModifiers, key: Character) -> String {
            var result = ""
            if modifiers.contains(.command) { result += "⌘" }
            if modifiers.contains(.control) { result += "⌃" }
            if modifiers.contains(.option) { result += "⌥" }
            if modifiers.contains(.shift) { result += "⇧" }
            result += String(key).uppercased()
            return result
        }
    }
    
    struct KeyModifiers: OptionSet {
        let rawValue: Int
        static let command = KeyModifiers(rawValue: 1 << 0)
        static let control = KeyModifiers(rawValue: 1 << 1)
        static let option = KeyModifiers(rawValue: 1 << 2)
        static let shift = KeyModifiers(rawValue: 1 << 3)
    }
    
    // MARK: - 快捷键统一查找系统
    
    enum ShortcutKey: Hashable {
        case single(Character)
        case modified(KeyModifiers, Character)
        case sequence(String)
        
        func hash(into hasher: inout Hasher) {
            switch self {
            case .single(let char):
                hasher.combine(0)
                hasher.combine(char)
            case .modified(let modifiers, let char):
                hasher.combine(1)
                hasher.combine(modifiers.rawValue)
                hasher.combine(char)
            case .sequence(let sequence):
                hasher.combine(2)
                hasher.combine(sequence)
            }
        }
    }
    
    // MARK: - 序列模式状态
    
    var isInSequenceMode = false
    var pendingSequence: String = ""
    
    private var sequenceTimer: Timer?
    private let sequenceTimeout: TimeInterval = 1.5
    
    /// 定义操作和对应的快捷键 - 统一版本支持所有快捷键类型
    struct ActionInfo {
        let text: String
        let textIPhone: String?
        let shortcuts: [ShortcutType]
        let supportedModes: Set<AppMode>
        let action: () -> Void

        init(text: String, textIPhone: String? = nil, shortcuts: [ShortcutType] = [], supportedModes: Set<AppMode> = ActionDefinitions.allModes, action: @escaping () -> Void) {
            self.text = text
            self.textIPhone = textIPhone
            self.shortcuts = shortcuts
            self.supportedModes = supportedModes
            self.action = action
        }

        /// 所有快捷键的显示文本，用 `/` 分隔，无快捷键返回 nil
        var shortcutsDisplayText: String? {
            guard !shortcuts.isEmpty else { return nil }
            return shortcuts.map { $0.getDisplayText() }.joined(separator: "/")
        }
    }
    
    /// 定义切换按钮操作的结构体
    struct ToggleActionInfo {
        let text: String
        let shortcuts: [ShortcutType]
        let supportedModes: Set<AppMode>
        let isEnabled: () -> Bool
        let isOn: () -> Bool
        let action: (Bool) -> Void

        init(
            text: String,
            shortcuts: [ShortcutType] = [],
            supportedModes: Set<AppMode> = ActionDefinitions.allModes,
            isEnabled: @escaping () -> Bool,
            isOn: @escaping () -> Bool,
            action: @escaping (Bool) -> Void
        ) {
            self.text = text
            self.shortcuts = shortcuts
            self.supportedModes = supportedModes
            self.isEnabled = isEnabled
            self.isOn = isOn
            self.action = action
        }

        /// 所有快捷键的显示文本，用 `/` 分隔，无快捷键返回 nil
        var shortcutsDisplayText: String? {
            guard !shortcuts.isEmpty else { return nil }
            return shortcuts.map { $0.getDisplayText() }.joined(separator: "/")
        }
    }
    
    /// 所有操作的集合
    private var actionMap: [ActionKey: ActionInfo] = [:]
    
    private var toggleActionMap: [ActionKey: ToggleActionInfo] = [:]
  
    
    // MARK: - 统一快捷键查找表
    
    private var shortcutLookup: [ShortcutKey: ActionKey] = [:]
    
    /// 获取指定操作的信息
    func getActionInfo(_ key: ActionKey) -> ActionInfo? {
        return actionMap[key]
    }
  
    func getToggleActionInfo(_ key: ActionKey) -> ToggleActionInfo? {
        return toggleActionMap[key]
    }

    
    /// 获取指定操作的快捷键（仅返回第一个单字符快捷键以保持向后兼容）
    func getShortcut(_ key: ActionKey) -> Character? {
        if let actionInfo = actionMap[key], let shortcut = actionInfo.shortcuts.first {
            if case .single(let char) = shortcut {
                return char
            }
        }

        if let toggleInfo = toggleActionMap[key], let shortcut = toggleInfo.shortcuts.first {
            if case .single(let char) = shortcut {
                return char
            }
        }

        return nil
    }
    
    /// 获取快捷键描述（支持所有快捷键类型，多个用 `/` 分隔）
    func getShortcutDescription(_ key: ActionKey) -> String? {
        if let actionInfo = actionMap[key] {
            return actionInfo.shortcutsDisplayText
        }

        if let toggleInfo = toggleActionMap[key] {
            return toggleInfo.shortcutsDisplayText
        }

        return nil
    }
    
    /// 注册操作 - 统一方法支持所有快捷键类型
    func registerAction(_ key: ActionKey, text: String, textIPhone: String? = nil, shortcuts: [ShortcutType] = [], supportedModes: Set<AppMode> = ActionDefinitions.allModes, action: @escaping () -> Void) {
        let actionInfo = ActionInfo(text: text, textIPhone: textIPhone, shortcuts: shortcuts, supportedModes: supportedModes, action: action)
        actionMap[key] = actionInfo

        // 将每个快捷键都注册到查找表
        for shortcut in shortcuts {
            let shortcutKey: ShortcutKey
            switch shortcut {
            case .single(let char):
                shortcutKey = .single(char)
            case .modified(let modifiers, let char):
                shortcutKey = .modified(modifiers, char)
            case .sequence(let sequence):
                shortcutKey = .sequence(sequence)
            }
            shortcutLookup[shortcutKey] = key
        }
    }
    
  
    /// 注册切换操作
    func registerToggleAction(_ key: ActionKey, text: String, shortcuts: [ShortcutType] = [], supportedModes: Set<AppMode> = ActionDefinitions.allModes, isEnabled: @escaping () -> Bool, isOn: @escaping () -> Bool, action: @escaping (Bool) -> Void) {
        toggleActionMap[key] = ToggleActionInfo(
            text: text,
            shortcuts: shortcuts,
            supportedModes: supportedModes,
            isEnabled: isEnabled,
            isOn: isOn,
            action: action
        )

        // 将每个快捷键都注册到统一快捷键查找表
        for shortcut in shortcuts {
            let shortcutKey: ShortcutKey
            switch shortcut {
            case .single(let char):
                shortcutKey = .single(char)
            case .modified(let modifiers, let char):
                shortcutKey = .modified(modifiers, char)
            case .sequence(let sequence):
                shortcutKey = .sequence(sequence)
            }
            shortcutLookup[shortcutKey] = key
        }
    }

    
    
    // MARK: - 快捷键处理
    
    func handleSwiftUIKeyPress(_ press: KeyPress) -> Bool {
        let character = press.key.character
        
        // 检查修饰符键 (不包括 Shift，以允许输入需要 Shift 的字符如 ^、$ 等)
        var modifiers = KeyModifiers()
        if press.modifiers.contains(.command) { modifiers.insert(.command) }
        if press.modifiers.contains(.control) { modifiers.insert(.control) }
        if press.modifiers.contains(.option) { modifiers.insert(.option) }
        // 不检查 Shift 修饰键，让 Shift+6 能够输入 ^ 字符
        
        // 优先检查修饰符+键的组合
        if !modifiers.isEmpty {
            let shortcutKey = ShortcutKey.modified(modifiers, character)
            if let actionKey = shortcutLookup[shortcutKey] {
                return executeAction(actionKey)
            }
        }
        
        // 处理序列模式
        if isInSequenceMode {
            return handleSequenceInput(character)
        }
        
        // 检查单键快捷键
        if modifiers.isEmpty {
            let shortcutKey = ShortcutKey.single(character)
            if let actionKey = shortcutLookup[shortcutKey] {
                // 执行对应的动作（可能是普通action或toggle action）
                return executeAction(actionKey)
            }
            
            // 开始序列模式检查
            return startSequenceMode(with: character)
        }
        
        return false
    }
    
    /// 处理按键事件（兼容旧版本）
    func handleKeyPress(_ key: KeyEquivalent) -> Bool {
        #if os(iOS) || os(tvOS) || os(watchOS)
        let character = key  // KeyEquivalent is already Character on iOS
        #else
        let character = key.character  // On macOS, extract character
        #endif
        
        // 处理序列模式
        if isInSequenceMode {
            return handleSequenceInput(character)
        }
        
        // 检查单键快捷键
        let shortcutKey = ShortcutKey.single(character)
        if let actionKey = shortcutLookup[shortcutKey] {
            return executeAction(actionKey)
        }
        
        // 开始序列模式检查
        return startSequenceMode(with: character)
    }
    
    // MARK: - 序列模式处理
    
    private func handleSequenceInput(_ character: Character) -> Bool {
        pendingSequence.append(character)
        
        // 检查是否有匹配的序列
        let shortcutKey = ShortcutKey.sequence(pendingSequence)
        if let actionKey = shortcutLookup[shortcutKey] {
            // 完全匹配，执行动作
            let success = executeAction(actionKey)
            exitSequenceMode()
            return success
        }
        
        // 检查是否有以当前序列开头的更长序列
        let hasLongerSequence = shortcutLookup.keys.contains { key in
            if case .sequence(let sequence) = key {
                return sequence.hasPrefix(pendingSequence) && sequence.count > pendingSequence.count
            }
            return false
        }
        
        if hasLongerSequence {
            // 重启超时计时器
            resetSequenceTimer()
            return true
        } else {
            // 没有匹配的序列，退出序列模式
            exitSequenceMode()
            return false
        }
    }
    
    private func startSequenceMode(with character: Character) -> Bool {
        // 检查是否有以此字符开头的序列
        let hasSequenceStartingWith = shortcutLookup.keys.contains { key in
            if case .sequence(let sequence) = key {
                return sequence.first == character
            }
            return false
        }
        
        if hasSequenceStartingWith {
            isInSequenceMode = true
            pendingSequence = String(character)
            resetSequenceTimer()
            return true
        }
        
        return false
    }
    
    private func resetSequenceTimer() {
        sequenceTimer?.invalidate()
        sequenceTimer = Timer.scheduledTimer(withTimeInterval: sequenceTimeout, repeats: false) { [weak self] _ in
            self?.exitSequenceMode()
        }
    }
    
    private func exitSequenceMode() {
        isInSequenceMode = false
        pendingSequence = ""
        sequenceTimer?.invalidate()
        sequenceTimer = nil
    }
    
    // MARK: - 辅助方法
    
    private func modifierKeyString(modifiers: KeyModifiers, key: Character) -> String {
        var components: [String] = []
        if modifiers.contains(.command) { components.append("cmd") }
        if modifiers.contains(.control) { components.append("ctrl") }
        if modifiers.contains(.option) { components.append("opt") }
        if modifiers.contains(.shift) { components.append("shift") }
        components.append(String(key))
        return components.joined(separator: "+")
    }
    
    private func formatModifiedKey(modifiers: KeyModifiers, key: Character) -> String {
        var result = ""
        if modifiers.contains(.command) { result += "⌘" }
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        result += String(key).uppercased()
        return result
    }
    
    // MARK: - 动作执行
    
    /// 执行指定的动作（支持普通动作和切换动作）
    private func executeAction(_ actionKey: ActionKey) -> Bool {
        // 首先检查是否是普通动作
        if let actionInfo = actionMap[actionKey] {
            actionInfo.action()
            return true
        }
        
        // 然后检查是否是切换动作
        if let toggleInfo = toggleActionMap[actionKey] {
            let currentState = toggleInfo.isOn()
            toggleInfo.action(!currentState)
            return true
        }
        
        return false
    }
    
    // MARK: - 获取所有动作信息

    func getAllActions() -> [ActionInfo] {
        return Array(actionMap.values)
    }

    // MARK: - 可见性检查

    /// 检查指定操作在指定模式下是否可见
    /// - Parameters:
    ///   - actionKey: 要检查的操作键
    ///   - mode: 当前应用模式
    /// - Returns: 操作是否可见
    func isActionVisible(_ actionKey: ActionKey, in mode: AppMode) -> Bool {
        // 检查普通操作
        if let actionInfo = actionMap[actionKey] {
            return actionInfo.supportedModes.contains(mode)
        }

        // 检查切换操作
        if let toggleInfo = toggleActionMap[actionKey] {
            return toggleInfo.supportedModes.contains(mode)
        }

        // 默认返回false（找不到的操作认为不可见）
        return false
    }
} 
