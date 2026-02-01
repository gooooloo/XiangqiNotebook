import SwiftUI

// 单个路径配置的视图
struct PathConfigView: View {
    @Binding var pathConfig: PathConfig
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Text(pathConfig.points.joined(separator: ","))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                .cornerRadius(6)
            
            Toggle("箭头", isOn: Binding(
                get: { pathConfig.showArrow },
                set: { newValue in
                    pathConfig = PathConfig(
                        points: pathConfig.points,
                        showArrow: newValue,
                        isDashed: pathConfig.isDashed
                    )
                }
            ))
            
            Toggle("虚线", isOn: Binding(
                get: { pathConfig.isDashed },
                set: { newValue in
                    pathConfig = PathConfig(
                        points: pathConfig.points,
                        showArrow: pathConfig.showArrow,
                        isDashed: newValue
                    )
                }
            ))
        }
    }
}

// 单个路径组的视图
struct PathGroupView: View {
    @Binding var pathGroup: PathGroup
    let groupIndex: Int
    let selectedGroupIndex: Int?
    let selectedPathIndex: Int?
    let onSelect: (Int, Int) -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("组名", text: Binding(
                    get: { pathGroup.name ?? "" },
                    set: { newName in
                        pathGroup = PathGroup(
                            paths: pathGroup.paths,
                            name: newName.isEmpty ? nil : newName
                        )
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("删除") {
                    onDelete()
                }
                .foregroundColor(.red)
            }
            
            // 显示组内的路径
            ForEach(pathGroup.paths.indices, id: \.self) { pathIndex in
                HStack {
                    Text("路径 \(pathIndex + 1):")
                    PathConfigView(
                        pathConfig: Binding(
                            get: { pathGroup.paths[pathIndex] },
                            set: { newValue in
                                var newPaths = pathGroup.paths
                                newPaths[pathIndex] = newValue
                                pathGroup = PathGroup(
                                    paths: newPaths,
                                    name: pathGroup.name
                                )
                            }
                        ),
                        isSelected: selectedGroupIndex == groupIndex && selectedPathIndex == pathIndex
                    )
                    
                    Button(selectedGroupIndex == groupIndex && selectedPathIndex == pathIndex ? "取消选择" : "选择") {
                        if selectedGroupIndex == groupIndex && selectedPathIndex == pathIndex {
                            onSelect(-1, -1) // 取消选择
                        } else {
                            onSelect(groupIndex, pathIndex) // 选择当前路径
                        }
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(selectedGroupIndex == groupIndex && selectedPathIndex == pathIndex ? .blue : .primary)
                    
                    Button("删除") {
                        var newPaths = pathGroup.paths
                        newPaths.remove(at: pathIndex)
                        pathGroup = PathGroup(
                            paths: newPaths,
                            name: pathGroup.name
                        )
                        if selectedGroupIndex == groupIndex && selectedPathIndex == pathIndex {
                            onSelect(-1, -1) // 取消选择被删除的路径
                        }
                    }
                    .foregroundColor(.red)
                }
            }
            
            // 添加新路径的按钮
            Button("添加路径") {
                let newPath = PathConfig(points: [], showArrow: true)
                var newPaths = pathGroup.paths
                newPaths.append(newPath)
                pathGroup = PathGroup(
                    paths: newPaths,
                    name: pathGroup.name
                )
                // 自动选择新添加的路径
                onSelect(groupIndex, newPaths.count - 1)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MarkPathView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedGroupIndex: Int = -1
    @State private var selectedPathIndex: Int = -1
    @State private var pathGroups: [PathGroup]
    private let boardViewModel: BoardViewModel
    private let onPathGroupsUpdated: ([PathGroup]) -> Void
    
    init(viewModel: BoardViewModel, onPathGroupsUpdated: @escaping ([PathGroup]) -> Void = { _ in }) {
        self.boardViewModel = viewModel
        self.onPathGroupsUpdated = onPathGroupsUpdated
        
        // 根据是否有现有路径组来初始化
        let initialPathGroups = viewModel.getCurrentFenPathGroups()
        if initialPathGroups.isEmpty {
            // 没有路径组时，自动创建一个新的路径组和路径
            let newPath = PathConfig(points: [], showArrow: true)
            let newGroup = PathGroup(
                paths: [newPath],
                name: "新路径组"
            )
            self._pathGroups = State(initialValue: [newGroup])
            self._selectedGroupIndex = State(initialValue: 0)
            self._selectedPathIndex = State(initialValue: 0)
        } else {
            // 有现有路径组时，保持原样
            self._pathGroups = State(initialValue: initialPathGroups)
            self._selectedGroupIndex = State(initialValue: -1)
            self._selectedPathIndex = State(initialValue: -1)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // 左侧：路径组列表
            VStack {
                HStack {
                    Text("路径组")
                        .font(.headline)
                    Spacer()
                    Button("添加") {
                        let newPath = PathConfig(points: [], showArrow: true)
                        let newGroup = PathGroup(
                            paths: [newPath],  // 初始化时包含一条路径
                            name: "新路径组"
                        )
                        pathGroups.append(newGroup)
                        // 自动选中新添加的路径组和路径
                        selectedGroupIndex = pathGroups.count - 1
                        selectedPathIndex = 0
                    }
                }
                .padding()
                
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(pathGroups.indices, id: \.self) { index in
                            PathGroupView(
                                pathGroup: Binding(
                                    get: { pathGroups[index] },
                                    set: { newValue in
                                        pathGroups[index] = newValue
                                    }
                                ),
                                groupIndex: index,
                                selectedGroupIndex: selectedGroupIndex,
                                selectedPathIndex: selectedPathIndex,
                                onSelect: { groupIndex, pathIndex in
                                    selectedGroupIndex = groupIndex
                                    selectedPathIndex = pathIndex
                                },
                                onDelete: {
                                    pathGroups.remove(at: index)
                                    if selectedGroupIndex == index {
                                        selectedGroupIndex = -1
                                        selectedPathIndex = -1
                                    }
                                }
                            )
                            Divider()
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .frame(width: 600)
            .border(Color.gray)
            
            // 右侧：棋盘视图
            VStack {
                HStack {
                    Text("标记路径")
                        .font(.headline)
                    Spacer()
                    HStack(spacing: 8) {
                        Button("取消并退出") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                        
                        Button("保存并退出") {
                            onPathGroupsUpdated(pathGroups)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                
                PathMarkingBoard(
                    pathGroups: $pathGroups,
                    selectedGroupIndex: $selectedGroupIndex,
                    selectedPathIndex: $selectedPathIndex,
                    viewModel: boardViewModel,
                    onSquareClick: { square in
                        guard selectedGroupIndex >= 0,
                              selectedPathIndex >= 0 else { return }
                        
                        var newPathGroups = pathGroups
                        newPathGroups[selectedGroupIndex].paths[selectedPathIndex].points.append(square)
                        pathGroups = newPathGroups
                    }
                )
                .frame(width: 600, height: 600)
                
                // 路径编辑控制
                VStack {
                    Text(selectedGroupIndex >= 0 && selectedPathIndex >= 0 
                        ? "正在编辑: \(pathGroups[selectedGroupIndex].name ?? "未命名组") - 路径 \(selectedPathIndex + 1)"
                        : "请选择一个路径进行编辑")
                        .foregroundColor(selectedGroupIndex >= 0 && selectedPathIndex >= 0 ? .primary : .gray)
                    
                    Button("清空路径") {
                        if selectedGroupIndex >= 0 && selectedPathIndex >= 0 {
                            var newPathGroups = pathGroups
                            newPathGroups[selectedGroupIndex].paths[selectedPathIndex] = PathConfig(
                                points: [],
                                showArrow: newPathGroups[selectedGroupIndex].paths[selectedPathIndex].showArrow,
                                isDashed: newPathGroups[selectedGroupIndex].paths[selectedPathIndex].isDashed
                            )
                            pathGroups = newPathGroups
                        }
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    .disabled(selectedGroupIndex < 0 || selectedPathIndex < 0)
                    .opacity(selectedGroupIndex >= 0 && selectedPathIndex >= 0 ? 1.0 : 0.5)
                }
                .frame(height: 80)
                .padding()
            }
            .frame(minWidth: 700, minHeight: 800)
        }
        .frame(width: 1300, height: 800)
    }
} 
