import Foundation

func stringify(_ data: Any) -> String {
    let sortedData = sortKeys(data)
    let jsonData = try? JSONSerialization.data(withJSONObject: sortedData, options: [.prettyPrinted])
    return String(data: jsonData ?? Data(), encoding: .utf8) ?? "{}"
}

func sortKeys(_ value: Any) -> Any {
    if let array = value as? [Any] {
        return array.map { sortKeys($0) }
    } else if let dict = value as? [String: Any] {
        var sortedDict: [String: Any] = [:]
        for key in dict.keys.sorted() {
            sortedDict[key] = sortKeys(dict[key]!)
        }
        return sortedDict
    }
    return value
}

func hashString(_ text: String) -> Int {
    var hash = 0
    for char in text {
        hash = ((hash << 5) &- hash) &+ Int(char.asciiValue ?? 0)
        hash = hash & hash // 转换为32位整数
    }
    return hash
}

func makeDiff(newValue: Any?, oldValue: Any?) -> Any? {
    // 如果新值为空
    if newValue == nil {
        if oldValue == nil {
            return nil // 无差异
        } else {
            return NSNull() // 表示删除
        }
    }
    
    // 如果旧值为空
    if oldValue == nil {
        return newValue
    }
    
    // 如果类型不同
    if type(of: newValue!) != type(of: oldValue!) {
        return newValue
    }
    
    // 如果不是对象类型
    if !(newValue is [String: Any]) && !(newValue is [Any]) {
        if isEqual(newValue, oldValue) {
            return nil
        } else {
            return newValue
        }
    }
    
    // 处理字典类型
    if let newDict = newValue as? [String: Any],
       let oldDict = oldValue as? [String: Any] {
        var diff: [String: Any] = [:]
        
        // 检查新值中的所有键
        for (key, value) in newDict {
            let localDiff = makeDiff(newValue: value, oldValue: oldDict[key])
            if localDiff != nil { // nil 表示无差异
                diff[key] = localDiff
            }
        }
        
        // 检查旧值中被删除的键
        for key in oldDict.keys {
            if !newDict.keys.contains(key) {
                diff[key] = NSNull()
            }
        }
        
        return diff.isEmpty ? nil : diff
    }
    
    // 处理数组类型
    if let newArray = newValue as? [Any],
       let oldArray = oldValue as? [Any] {
        // 替换直接比较为逐元素比较
        if newArray.count == oldArray.count {
            for i in 0..<newArray.count {
                if !isEqual(newArray[i], oldArray[i]) {
                    return newArray
                }
            }
            return nil // 数组完全相同
        }
        return newArray
    }
    
    return newValue
}

private func isEqual(_ value1: Any?, _ value2: Any?) -> Bool {
    if let num1 = value1 as? NSNumber, let num2 = value2 as? NSNumber {
        return num1 == num2
    }
    if let str1 = value1 as? String, let str2 = value2 as? String {
        return str1 == str2
    }
    if let bool1 = value1 as? Bool, let bool2 = value2 as? Bool {
        return bool1 == bool2
    }
    if let dict1 = value1 as? [String: Any], let dict2 = value2 as? [String: Any] {
        if dict1.keys.count != dict2.keys.count {
            return false
        }
        for (key, value) in dict1 {
            if !isEqual(value, dict2[key]) {
                return false
            }
        }
        return true
    }
    if let arr1 = value1 as? [Any], let arr2 = value2 as? [Any] {
        if arr1.count != arr2.count {
            return false
        }
        for i in 0..<arr1.count {
            if !isEqual(arr1[i], arr2[i]) {
                return false
            }
        }
        return true
    }
    if value1 == nil && value2 == nil {
        return true
    }
    return false
}

func removeNullOrUndefinedValues(_ value: Any) -> Any? {
    if !(value is [String: Any]) && !(value is [Any]) {
        return value
    }
    
    if let array = value as? [Any] {
        let filtered: [Any] = array.compactMap { value in
            if value is NSNull { return nil }
            return removeNullOrUndefinedValues(value)
        }
        return filtered.isEmpty ? nil : filtered
    }
    
    if let dict = value as? [String: Any] {
        var newDict: [String: Any] = [:]
        for (key, value) in dict {
            if let processedValue = removeNullOrUndefinedValues(value) {
                newDict[key] = processedValue
            }
        }
        return newDict.isEmpty ? nil : newDict
    }
    
    return nil
}

func normalizeFen(_ fen: String) -> String {
    // We hack the fen after - - as we don't need the rest of the information, and we need to be compatible with the old code
    // TODO: We should remove this hack after the old code is removed
    return fen.split(separator: "-")[0].trimmingCharacters(in: .whitespaces) + " - - 1 1"
}