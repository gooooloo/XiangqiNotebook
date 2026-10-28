import SwiftUI

struct CoachWorkspaceModifier: ViewModifier {
    @ObservedObject var notebook: ViewModel
    @StateObject private var coach = CoachViewModel.shared
    @ObservedObject private var notifications = CoachNotifications.shared
    @State private var showingCoach = !AIKeychain.isRunningInTests
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .disabled(showingCoach)
            .overlay {
                if showingCoach {
                    CoachView(coach: coach, notebook: notebook)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Button { showingCoach = true } label: { Label("教练课堂", systemImage: "person.bubble") }
                        .buttonStyle(.borderedProminent).tint(showingCoach ? .accentColor : .gray)
                    Button("棋谱与自由研究") { showingCoach = false }.buttonStyle(.bordered)
                    Spacer()
                }.padding(8).background(.background)
            }
            .task { if !AIKeychain.isRunningInTests { coach.start(); await coach.refresh() } }
            .onAppear { notebook.coachWorkspaceVisible = showingCoach }
            .onChange(of: showingCoach) { _, value in
                notebook.coachWorkspaceVisible = value
                if value { notifications.becameActive() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { notifications.becameActive(); Task { await coach.refresh() } }
                else { coach.flushDraft(); Task { await coach.syncDraft() } }
            }
            .onChange(of: notifications.lessonID) { _, id in
                guard id != nil else { return }
                showingCoach = true
                Task { await coach.refresh() }
            }
    }
}

struct CoachView: View {
    @ObservedObject var coach: CoachViewModel
    @ObservedObject var notebook: ViewModel
    @ObservedObject private var notifications = CoachNotifications.shared
    @State private var showSettings = false
    @State private var showAISettings = false
    @State private var showSource = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("一起把棋学明白").font(.title2.bold())
                        Text("你负责学习，我来安排下一步。").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { coach.reloadPreferences(); showSettings.toggle() } label: { Image(systemName: "gearshape") }.accessibilityLabel("教练设置")
                    Button { Task { await coach.refresh() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("同步学习记录")
                }
                Text(coach.snapshot.syncStatus).font(.caption).foregroundStyle(.secondary)
                if coach.isBusy || coach.isPreparing {
                    HStack {
                        ProgressView("教练正在准备或同步…已有记录保存在本机")
                        Button("停止模型请求") { coach.cancelModel() }
                    }
                }
                if let error = coach.error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
                if coach.snapshot.incomplete || coach.snapshot.hasUnresolvedApproval { Text("同步尚未完整，未下载的记录不会被删除。跨设备最新安排可能稍后才出现。").font(.caption).foregroundStyle(.orange) }
                if coach.snapshot.hasAuthorityConflict { Text("计划或审批文件有冲突，已保留全部版本；核对前暂停教学授权，未自动采用旧计划。").foregroundStyle(.orange) }
                if coach.snapshot.invalidApprovalCount > 0 { Text("部分审批内容无效，已保留供核对；不会阻止其他有效计划继续。").font(.caption).foregroundStyle(.orange) }
                if coach.snapshot.hasClockUncertainty || coach.snapshot.hasCorrectionConflict {
                    Text("部分记录的时间或更正存在不确定性。已保留原始记录，暂不据此延长复习间隔。").foregroundStyle(.orange)
                }
                if let p = coach.snapshot.effectivePreferences {
                    GroupBox("当前教学范围") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(p.goal)
                            Text("每日一节 · 约 \(p.dailyMinutes) 分钟 · 模型请求上限 \(p.maxDailyCalls) 次/日")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(coach.snapshot.materials.filter { coach.snapshot.allowedMaterialIDs.contains($0.id) }.map(\.title).joined(separator: "、"))
                            if !p.enabled { Text("教练已暂停，或当前计划没有共同有效范围。可以 review 新安排后继续。").foregroundStyle(.secondary) }
                            if p.enabled { Button("暂停教练", role: .destructive) { Task { await coach.pause() } } }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if coach.snapshot.heads.count > 1 {
                    GroupBox("两台设备批准了不同安排") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("选择前，只在两份安排共同允许的范围内继续。所有已完成的学习都会保留。")
                            ForEach(coach.snapshot.approvedPlans) { plan in
                                planSummary(plan)
                                Button("采用这份安排并合并分支") { Task { await coach.resolve(using: plan) } }
                            }
                        }
                    }
                }
                ForEach(coach.snapshot.pendingPlans) { plan in
                    GroupBox("教练提出的安排 · 请 review") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(plan.rationale)
                            planSummary(plan)
                            HStack {
                                Button("采用并开始学习") { Task { await coach.approve(plan) } }.buttonStyle(.borderedProminent)
                                Button("暂不采用") { Task { await coach.dismiss(plan) } }
                                Button("提意见") { coach.reloadPreferences(); showSettings = true }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let lesson = coach.lesson { classroom(lesson) }
                else {
                    GroupBox("接下来的安排") {
                        Text(nextStep).frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                }
                Button("把当前教材笔记加入学习范围") { coach.setSource(from: notebook); showSource = true }
                if showSource { sourceEditor.disabled(coach.isBusy) }
                if showSettings { settings.disabled(coach.isBusy) }
                if !coach.snapshot.materials.isEmpty {
                    DisclosureGroup("教材与复习安排") {
                        ForEach(coach.snapshot.materials) { m in
                            VStack(alignment: .leading) {
                                Text(m.title).bold()
                                Text(m.locator).font(.caption)
                                let due = coach.snapshot.dueDate(for: m)
                                Text(due == .distantPast ? "尚未学习" : "下次复习：\(due.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                        }
                    }
                }
                if !coach.snapshot.stalePlans.isEmpty {
                    DisclosureGroup("基于旧计划的建议（尚未生效）") {
                        ForEach(coach.snapshot.stalePlans) { plan in
                            Text(plan.rationale)
                            Button("基于当前安排重新提出，供 review") { Task { await coach.rebase(plan) } }
                            Button("不再考虑这份建议") { Task { await coach.dismiss(plan) } }
                        }
                    }
                }
                if !coach.snapshot.conflictingEvents.isEmpty {
                    DisclosureGroup("身份冲突的原始记录（全部保留）") {
                        ForEach(Array(coach.snapshot.conflictingEvents.enumerated()), id: \.offset) { item in
                            if case .attempt(let value) = item.element.payload {
                                Text(value.answer)
                                Text("\(item.element.createdAt.formatted()) · \(ratingName(value.rating))").font(.caption)
                            } else { Text("记录 \(item.element.id)：等待核对，未自动覆盖") }
                        }
                    }
                }
                history
            }
            .padding(20).frame(maxWidth: 850).frame(maxWidth: .infinity)
        }
        .onChange(of: coach.answer) { _, _ in coach.saveDraft() }
        .onChange(of: coach.revealed) { _, _ in coach.saveDraft() }
        .onChange(of: coach.showHint) { _, _ in coach.saveDraft() }
        .sheet(isPresented: $showAISettings) { AISettingsView(isPresented: $showAISettings) }
    }
    private var nextStep: String {
        if coach.snapshot.materials.isEmpty { return "先选一份你想学的书籍或棋谱笔记交给我。我会提出短期安排，带你理解、练习并反复巩固。" }
        if coach.snapshot.effectivePreferences == nil { return "我已准备教学安排。你确认范围后，我会主动安排每天的课程，不需要你每天规划。" }
        if coach.snapshot.effectivePreferences?.enabled != true { return "当前教学已暂停。可在设置中提出恢复安排，确认后继续。" }
        if !coach.snapshot.todayAttempts.isEmpty { return "今天的学习已记录。先消化一下，我会根据表现安排下一次复习。" }
        return "已有内容会按间隔再次复习，暂时没有到期任务。你也可以加入下一份教材笔记。"
    }
    private func planSummary(_ plan: CoachPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.preferences.goal).bold()
            Text("教材：" + coach.snapshot.materials.filter { plan.materialIDs.contains($0.id) }.map(\.title).joined(separator: "、"))
            Text("每日一节约 \(plan.preferences.dailyMinutes) 分钟；模型请求最多 \(plan.preferences.maxDailyCalls) 次/日。")
            Text(plan.preferences.enabled ? "允许教练在此范围内自主安排教学和复习。" : "暂停教学和提醒。")
            if let current = coach.snapshot.approvedPlans.first {
                if current.preferences.goal != plan.preferences.goal { Text("目标变更：\(current.preferences.goal) → \(plan.preferences.goal)") }
                if current.preferences.dailyMinutes != plan.preferences.dailyMinutes { Text("每课时长：\(current.preferences.dailyMinutes) → \(plan.preferences.dailyMinutes) 分钟") }
                if Set(current.materialIDs) != Set(plan.materialIDs) { Text("教材范围有调整，请核对上方列表。") }
            }
            if let device = plan.preferences.reminderDeviceID {
                Text("提醒：\(device == coach.deviceID ? "此设备" : "另一台设备")，\(plan.preferences.hour) 点（\(plan.preferences.timeZone)）；按到期日安排，最多四次，逐步减少。")
            } else { Text("不安排系统提醒。") }
            if let end = plan.preferences.endDate { Text("截止：\(end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))") }
        }.font(.subheadline)
    }
    private var settings: some View {
        GroupBox("教学安排与本机设置") {
            VStack(alignment: .leading, spacing: 12) {
                Button("模型设置（与问棋共用）") { showAISettings = true }
                Text("备课和追问会把相关教材片段发送给你在 App 中选择的模型。原笔记不会被修改。")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("学习目标", text: $coach.preferences.goal).textFieldStyle(.roundedBorder)
                Toggle("允许教练主动教学", isOn: $coach.preferences.enabled)
                Stepper("每课约 \(coach.preferences.dailyMinutes) 分钟", value: $coach.preferences.dailyMinutes, in: 3...30)
                Stepper("每日模型请求上限 \(coach.preferences.maxDailyCalls) 次", value: $coach.preferences.maxDailyCalls, in: 1...10)
                Text("离线多设备无法保证全局硬额度；每台设备会按已知记录限制请求。失败和重试也计数。").font(.caption).foregroundStyle(.secondary)
                ForEach(coach.snapshot.materials) { material in
                    Toggle(material.title, isOn: Binding(get: { coach.selectedMaterials.contains(material.id) }, set: {
                        if $0 { coach.selectedMaterials.insert(material.id) } else { coach.selectedMaterials.remove(material.id) }
                    }))
                }
                Toggle("由此设备提醒我学习", isOn: Binding(get: { coach.preferences.reminderDeviceID == coach.deviceID }, set: {
                    coach.preferences.reminderDeviceID = $0 ? coach.deviceID : nil
                }))
                Stepper("\(coach.preferences.hour) 点提醒", value: $coach.preferences.hour, in: 0...23)
                Toggle("设置阶段截止日期", isOn: Binding(get: { coach.preferences.endDate != nil }, set: {
                    coach.preferences.endDate = $0 ? coach.snapshot.calendar.date(byAdding: .day, value: 15, to: coach.snapshot.calendar.startOfDay(for: Date())) : nil
                }))
                if coach.preferences.endDate != nil {
                    DatePicker("阶段截止", selection: Binding(get: { (coach.preferences.endDate ?? Date()).addingTimeInterval(-1) }, set: { coach.preferences.endDate = coach.snapshot.calendar.date(byAdding: .day, value: 1, to: coach.snapshot.calendar.startOfDay(for: $0)) }), displayedComponents: .date)
                }
                HStack {
                    Button("生成修改方案供 review") { Task { await coach.proposeChanges() } }
                    Button("重新载入当前安排") { coach.reloadPreferences() }
                }
                Divider()
                Button("允许本地通知") { Task { await notifications.enable(); await coach.updateNotifications() } }
                #if os(macOS)
                Toggle("登录 Mac 后自动启动", isOn: Binding(get: { notifications.loginEnabled }, set: { notifications.setLoginEnabled($0) }))
                Text("关窗口后教练仍可运行；退出 App 或 Mac 睡眠后暂停。已安排的本地通知交由系统发送。").font(.caption).foregroundStyle(.secondary)
                #endif
                Text(notifications.status).font(.caption).foregroundStyle(.secondary)
            }.padding(6)
        }
    }
    private var sourceEditor: some View {
        GroupBox("保存教材副本并提出安排") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("教材标题", text: $coach.sourceTitle)
                TextField("章节、页码或笔记位置", text: $coach.sourceLocator)
                TextField("想学会什么", text: $coach.objective)
                TextEditor(text: $coach.sourceNote).frame(minHeight: 100).border(.secondary.opacity(0.3))
                Text("先保存到本机，经 iCloud 同步。采用教学安排后，教练才会将这份材料交给 App 已配置的模型备课。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("保存并让教练安排") { Task { await coach.saveSource(); if coach.error == nil { showSource = false } } }
                    .disabled(!coach.canSaveSource)
                if coach.snapshot.approvals.isEmpty {
                    Button("先试学这份笔记，稍后 review") { Task { await coach.saveSource(startTrial: true); if coach.error == nil { showSource = false } } }
                        .disabled(!coach.canSaveSource)
                }
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
                    .frame(height: 330).allowsHitTesting(false).accessibilityLabel("教材局面")
            }
            Text(lesson.content.question).font(.headline).textSelection(.enabled)
            TextEditor(text: $coach.answer).frame(minHeight: 90).border(.secondary.opacity(0.3)).accessibilityLabel("写下你的思路")
            HStack {
                Button("给我一点提示") { coach.showHint = true }
                Button("带我理解这段笔记") { coach.revealed = true }
            }
            if coach.showHint { Text(lesson.content.hint).textSelection(.enabled) }
            if coach.revealed {
                GroupBox(lesson.provenance) { Text(lesson.content.explanation).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(6) }
                if let material = coach.material { DisclosureGroup("原笔记") { Text(material.note).textSelection(.enabled) } }
            }
            ForEach(coach.discussions, id: \.0.id) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text("我：" + item.1.question).bold()
                    Text(item.1.answer).textSelection(.enabled)
                    Text(item.1.provenance).font(.caption).foregroundStyle(.secondary)
                }
            }
            TextField("哪里还没想明白？", text: $coach.question, axis: .vertical).textFieldStyle(.roundedBorder)
            Button("请教练继续讲解") { Task { await coach.askCoach() } }.disabled(coach.question.isEmpty || coach.isPreparing || coach.isBusy)
            Button("保存这份思路，供其他设备接续") { Task { await coach.syncDraft() } }
            DisclosureGroup("其他已保存的思路（不会自动覆盖当前输入）") {
                ForEach(coach.snapshot.drafts(for: lesson.id)) { event in
                    if case .draft(let draft) = event.payload {
                        Text(draft.answer).lineLimit(3)
                        Button("载入 \(event.createdAt.formatted()) 的草稿") { coach.loadDraft(event) }
                    }
                }
            }
            Text("记录这次表现，安排下一次复习").font(.subheadline.bold())
            ViewThatFits(in: .horizontal) {
                HStack { ratingButtons }
                VStack(alignment: .leading) { ratingButtons }
            }
            Button("今天先放一放") { Task { await coach.deferLesson() } }
            Text("这是你的自评，不等于客观掌握。看过提示或讲解后不会算独立回忆；同日重复不当作多次间隔巩固。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var ratingButtons: some View {
        ForEach(["independent", "prompted", "again", "uncertain"], id: \.self) { rating in
            Button(ratingName(rating)) { Task { await coach.submit(rating) } }
                .disabled(coach.isBusy || coach.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    private var history: some View {
        DisclosureGroup("学习记录与更正历史") {
            ForEach(coach.snapshot.attempts.reversed(), id: \.event.id) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.value.answer)
                    Text("\(item.event.createdAt.formatted()) · \(ratingName(item.value.rating))\(item.value.supersedes == nil ? "" : " · 更正记录")")
                        .font(.caption).foregroundStyle(.secondary)
                    Menu("更正这次自评") {
                        ForEach(["independent", "prompted", "again", "uncertain"], id: \.self) { rating in
                            Button(ratingName(rating)) { Task { await coach.correct(item.event, rating: rating) } }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            }
        }
    }
    private func ratingName(_ value: String) -> String {
        ["independent": "独立想出来了", "prompted": "提示后理解", "again": "还需要再学", "uncertain": "暂时不确定"][value] ?? value
    }
}
