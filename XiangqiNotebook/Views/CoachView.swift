import SwiftUI

/// Shared entry point: the coach is the initial workspace; the original notebook remains one tap away.
struct CoachWorkspaceModifier: ViewModifier {
    @ObservedObject var notebook: ViewModel
    @StateObject private var coach = CoachViewModel()
    @ObservedObject private var notifications = CoachNotifications.shared
    @State private var showingCoach = !AIKeychain.isRunningInTests
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .disabled(showingCoach)
            .overlay {
                if showingCoach {
                    CoachView(coach: coach, notebook: notebook)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.background)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Button { showingCoach = true } label: { Label("教练课堂", systemImage: "person.bubble") }
                        .buttonStyle(.borderedProminent).tint(showingCoach ? .accentColor : .gray)
                    Button("棋谱与自由研究") { showingCoach = false }
                        .buttonStyle(.bordered)
                    Spacer()
                }.padding(8).background(.background)
            }
            .task {
                guard !AIKeychain.isRunningInTests else { return }
                await coach.refresh()
                if let token = notifications.deviceToken { await coach.registerDevice(token) }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { break }
                    if scenePhase == .active {
                        await coach.refresh()
                        if let token = notifications.deviceToken { await coach.registerDevice(token) }
                    }
                }
            }
            .onAppear { notebook.coachWorkspaceVisible = showingCoach }
            .onChange(of: showingCoach) { _, value in notebook.coachWorkspaceVisible = value }
            .onChange(of: notifications.lessonID) { _, id in
                guard id != nil else { return }
                showingCoach = true
                Task { await coach.refresh() }
            }
            .onChange(of: notifications.deviceToken) { _, token in
                guard let token else { return }
                Task { await coach.registerDevice(token) }
            }
    }
}

struct CoachView: View {
    @ObservedObject var coach: CoachViewModel
    @ObservedObject var notebook: ViewModel
    @ObservedObject private var notifications = CoachNotifications.shared
    @State private var showSettings = false
    @State private var showSource = false
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("一起把棋学明白").font(.title2.bold())
                        Text(coach.isConnected ? "接着上次的学习，逐步理解、练习和巩固。" : "连接你的私人教练，开始长期学习。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { showSettings.toggle() } label: { Image(systemName: "gearshape") }.accessibilityLabel("教练设置")
                    if coach.isConnected {
                        Button { Task { await coach.refresh() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("刷新课堂")
                    }
                }
                if coach.isBusy { ProgressView("正在同步…") }
                if let error = coach.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if !coach.isConnected || showSettings { settings }
                if let snapshot = coach.snapshot {
                    if !snapshot.preferences.enabled { Text("教练已暂停主动备课和联系；已有课程仍可继续。").foregroundStyle(.secondary) }
                    if !snapshot.capabilities.generator { Text("服务尚未配置备课模型。教材可以保存，配置后才会自动备课。").foregroundStyle(.orange) }
                    if !snapshot.capabilities.push { Text("服务尚未配置远程推送。这里显示备好的课程，但暂时不能主动通知你。").foregroundStyle(.secondary) }
                    if let error = snapshot.lastError { Text(error).foregroundStyle(.orange) }
                    if let lesson = coach.lesson { classroom(lesson) }
                    else {
                        GroupBox("接下来的安排") {
                            Text(snapshot.materials.isEmpty ? "先在棋谱中选一个有笔记的教材局面，再交给教练。" : "教练将在约定的 \(snapshot.preferences.hour) 点准备到期课程。今天学过的内容会根据反馈再次安排。")
                                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                        }
                    }
                    Button("把当前教材局面交给教练") { coach.setSource(from: notebook); showSource = true }
                    if showSource { sourceEditor }
                    if !snapshot.materials.isEmpty {
                        GroupBox("共同学习的笔记") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(snapshot.materials) { material in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(material.title).bold()
                                        Text(material.locator).font(.caption).foregroundStyle(.secondary)
                                        Text(material.objective).font(.subheadline)
                                        Text("复习安排：\(displayDate(material.dueAt))").font(.caption)
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                        }
                    }
                    if !snapshot.attempts.isEmpty {
                        DisclosureGroup("学习记录（学生自评，不代表已掌握）") {
                            ForEach(snapshot.attempts.reversed()) { attempt in
                                VStack(alignment: .leading) {
                                    Text(attempt.answer)
                                    Text("\(displayDate(attempt.createdAt)) · \(ratingName(attempt.rating))").font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                            }
                        }
                    }
                }
            }
            .padding(20).frame(maxWidth: 850).frame(maxWidth: .infinity)
            .disabled(coach.isBusy)
        }
        .onChange(of: coach.answer) { _, _ in coach.saveDraft() }
        .onChange(of: coach.revealed) { _, _ in coach.saveDraft() }
        .onChange(of: coach.showHint) { _, _ in coach.saveDraft() }
        .confirmationDialog("清除服务端全部教练材料、课程和学习记录？原始棋谱笔记不受影响。", isPresented: $confirmReset) {
            Button("清除教练记录并暂停", role: .destructive) { Task { await coach.clearCoachData() } }
        }
    }

    private var settings: some View {
        GroupBox("教练设置") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("服务地址（https://…）", text: $coach.endpoint).textFieldStyle(.roundedBorder)
                SecureField("服务凭据", text: $coach.token).textFieldStyle(.roundedBorder)
                Button("连接服务") { Task { await coach.connect() } }.buttonStyle(.borderedProminent)
                if coach.isConnected {
                    Divider()
                    TextField("学习目标", text: $coach.preferences.goal).textFieldStyle(.roundedBorder)
                    Toggle("允许教练主动备课和联系", isOn: $coach.preferences.enabled)
                    Stepper("每天 \(coach.preferences.hour) 点联系（\(coach.preferences.timeZone)）", value: $coach.preferences.hour, in: 0...23)
                    Stepper("每课约 \(coach.preferences.dailyMinutes) 分钟", value: $coach.preferences.dailyMinutes, in: 3...30)
                    Stepper("每日最多 \(coach.preferences.maxDailyCalls) 次模型请求（含追问和重试）", value: $coach.preferences.maxDailyCalls, in: 1...10)
                    Text("每天最多一课、每台设备一次通知。模型请求次数是用量限制，不是金额保证。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("保存教学安排") { Task { await coach.savePreferences() } }
                        Button("恢复服务端安排") { coach.reloadPreferences() }
                    }
                    Button("开启此设备的学习通知") { Task {
                        await notifications.enable()
                        if let token = notifications.deviceToken { await coach.registerDevice(token) }
                    } }
                    Text(notifications.status).font(.caption).foregroundStyle(.secondary)
                    Button("清除教练记录…", role: .destructive) { confirmReset = true }
                }
            }.padding(6)
        }
    }
    private var sourceEditor: some View {
        GroupBox("确认交给教练的材料") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("教材标题", text: $coach.sourceTitle)
                TextField("章节、页码或笔记位置", text: $coach.sourceLocator)
                TextField("想学会什么", text: $coach.objective)
                TextEditor(text: $coach.sourceNote).frame(minHeight: 100).border(.secondary.opacity(0.3))
                Text("只上传这里的局面、位置和笔记副本，供服务端模型备课；原笔记不会被改动。请核对教材出处。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("上传这份材料") { Task { await coach.uploadSource(); if coach.error == nil { showSource = false } } }
                    .disabled(!coach.canUpload)
            }.padding(6).textFieldStyle(.roundedBorder)
        }
    }
    private func classroom(_ lesson: CoachLesson) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(lesson.content.title).font(.title3.bold())
            Text(lesson.reason).foregroundStyle(.secondary)
            if let material = coach.material {
                Text(material.locator).font(.caption).textSelection(.enabled)
                XiangqiBoard(viewModel: $coach.board, onMove: { _ in coach.resetBoard() })
                    .frame(height: 330).allowsHitTesting(false)
                    .accessibilityLabel("教材局面，只读展示")
            }
            Text(lesson.content.question).font(.headline).textSelection(.enabled)
            TextEditor(text: $coach.answer).frame(minHeight: 100).border(.secondary.opacity(0.3))
                .accessibilityLabel("写下你的思路")
            HStack {
                Button("给我一点提示") { coach.showHint = true }
                Button("看看教练的讲解") { coach.revealed = true }
            }
            if coach.showHint { Text(lesson.content.hint).textSelection(.enabled) }
            if coach.revealed {
                GroupBox("教练补充 · 尚未经引擎核验") {
                    Text(lesson.content.explanation).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(6)
                }
                if let material = coach.material {
                    DisclosureGroup("原笔记") { Text(material.note).textSelection(.enabled) }
                }
            }
            if coach.revealed {
                ForEach((coach.snapshot?.discussions ?? []).filter { $0.lessonId == lesson.id }) { discussion in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("我：" + discussion.question).bold()
                        Text(discussion.answer).textSelection(.enabled)
                    }
                }
                TextField("还有哪里没想明白？", text: $coach.question, axis: .vertical).textFieldStyle(.roundedBorder)
                Button("继续问教练") { Task { await coach.askCoach() } }
                    .disabled(coach.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack {
                Button("同步本课草稿") { Task { await coach.syncDraft() } }
                Button("取回另一设备的草稿") { coach.loadRemoteDraft() }
            }
            Text("切换设备前同步草稿；另一设备连接同一服务即可接着学。")
                .font(.caption).foregroundStyle(.secondary)
            Text("记录这次表现，安排下一次复习").font(.subheadline.bold())
            ViewThatFits(in: .horizontal) {
                HStack { ratingButtons }
                VStack(alignment: .leading) { ratingButtons }
            }
            Button("今天先放一放") { Task { await coach.deferLesson() } }
            Text("自评用于调整复习间隔。看过提示或讲解后，本次不会记为独立回忆。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var ratingButtons: some View {
        ForEach(["independent", "prompted", "again", "uncertain"], id: \.self) { rating in
            Button(ratingName(rating)) { Task { await coach.submit(rating) } }
                .disabled(coach.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    private func ratingName(_ value: String) -> String {
        ["independent": "独立想出来了", "prompted": "提示后理解", "again": "还需要再学", "uncertain": "暂时不确定"][value] ?? value
    }
    private func displayDate(_ value: String?) -> String {
        guard let value, let date = ISO8601DateFormatter.coach.date(from: value) else { return "待安排" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private extension ISO8601DateFormatter {
    static var coach: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
