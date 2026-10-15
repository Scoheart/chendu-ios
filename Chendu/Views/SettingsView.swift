import SwiftUI

struct SettingsView: View {
    @Environment(IssueStore.self) private var store
    @AppStorage(DailyReminder.enabledKey) private var reminderOn = false
    @State private var denied = false
    @State private var confirmClear = false
    @State private var profile = ProfileDraft()
    @State private var appSettings = AppSettingsDraft()
    @State private var keySecret = ""
    @State private var keyHint = ""
    @State private var rssURL = ""
    @State private var promptBody = ""
    @State private var status = ""

    var body: some View {
        NavigationStack {
            Form {
                learning
                tasks
                schedule
                appearance
                sources
                prompt
                reminder
                offline
                account
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .navigationTitle("设置")
            .alert("通知未开启", isPresented: $denied) {
                Button("去设置") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请在系统设置里允许晨读发送通知。")
            }
            .confirmationDialog("清除离线缓存的文章和音频？笔记不受影响。", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清除缓存", role: .destructive) { store.clearCache() }
            }
        }
    }

    private var learning: some View {
        Section("学习") {
            Picker("水平", selection: $profile.learnerLevel) {
                ForEach(["A2", "B1", "B2", "C1", "C2"], id: \.self) { Text($0) }
            }
            TextField("解释语言", text: $profile.explanationLang)
            Picker("深度", selection: $profile.annotationDepth) {
                ForEach(["light", "standard", "deep"], id: \.self) { Text($0) }
            }
            Stepper("节选 \(profile.excerptWords) 词", value: $profile.excerptWords, in: 50...500, step: 10)
            Stepper("词条 \(profile.vocabCount)", value: $profile.vocabCount, in: 0...40)
            Stepper("句型 \(profile.patternCount)", value: $profile.patternCount, in: 0...12)
            Toggle("标音", isOn: $profile.includeIpa)
            Button("保存学习设置") { Task { await saveProfile() } }
        }
    }

    private var tasks: some View {
        Section {
            TextField("模型供应商", text: $profile.provider)
            TextField("模型", text: $profile.model)
            TextField("声音", text: $profile.voice)
            SecureField("模型 key", text: $keySecret)
                .accessibilityIdentifier("providerKey")
            Button("保存 key") { Task { await saveKey() } }
                .disabled(keySecret.isEmpty)
            if !keyHint.isEmpty {
                LabeledContent("已存 key 末四位", value: keyHint)
            }
        } header: {
            Text("模型")
        } footer: {
            Text("Key 只经过 save_provider_key，界面上不留 secret。")
        }
    }

    private var schedule: some View {
        Section("投递") {
            TextField("时区", text: $appSettings.timezone)
            TextField("时刻", text: $appSettings.deliveryTime)
            Toggle("推送", isOn: $appSettings.pushEnabled)
            Button("保存投递") { Task { await saveAppSettings() } }
        }
    }

    private var appearance: some View {
        Section("外观") {
            TextField("主题", text: $appSettings.theme)
            Picker("正文字体", selection: $appSettings.bodyFont) {
                Text("衬线").tag("serif")
                Text("系统").tag("system")
            }
            Toggle("栏目标题用手写", isOn: $appSettings.handwritingHeadings)
            Toggle("同步笔记", isOn: $appSettings.syncNotes)
            Button("保存外观") { Task { await saveAppSettings() } }
        }
    }

    private var sources: some View {
        Section("来源") {
            TextField("RSS 地址", text: $rssURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("订阅这个 RSS") { Task { await addRss() } }
                .disabled(rssURL.isEmpty)
        }
    }

    private var prompt: some View {
        Section {
            TextEditor(text: $promptBody)
                .frame(minHeight: 80)
            Button("保存为我的选文 prompt") { Task { await copyPrompt() } }
                .disabled(promptBody.isEmpty)
            Button("恢复默认 prompt") { Task { await restorePrompt() } }
        } header: {
            Text("Prompt")
        } footer: {
            Text("保存会复制平台模板再改你自己的一行。恢复默认会删掉你的那一行。")
        }
    }

    private var reminder: some View {
        Section {
            Toggle("每天 8:00 提醒（北京时间）", isOn: $reminderOn)
                .tint(.grammarRed)
                .onChange(of: reminderOn) { _, on in
                    Task {
                        if on {
                            let ok = await DailyReminder.enable()
                            if !ok { reminderOn = false; denied = true }
                        } else {
                            DailyReminder.disable()
                        }
                    }
                }
        } header: {
            Text("提醒")
        } footer: {
            Text(status.isEmpty ? "到点后由你自己的 worker 生成，不再跟静态站的发布时间走。" : status)
        }
    }

    private var offline: some View {
        Section("离线") {
            LabeledContent("已缓存", value: "\(store.cachedIssueCount) 期")
            LabeledContent("占用空间", value: ByteCountFormatter.string(fromByteCount: store.cacheBytes, countStyle: .file))
            Button("下载最近 7 期（含音频）") { Task { await store.saveRecentOffline(count: 7) } }
                .disabled(store.summaries.isEmpty || !store.downloads.isEmpty)
            Button("清除缓存", role: .destructive) { confirmClear = true }
        }
    }

    private var account: some View {
        Section("账号") {
            Button("退出登录") { SessionStore.live.clear() }
                .accessibilityIdentifier("signOut")
        }
    }

    private func client() -> SettingsClient? {
        guard let session = SessionStore.live.session else { return nil }
        return SettingsClient(
            baseURL: SupabaseConfig.url,
            anonKey: SupabaseConfig.anonKey,
            accessToken: session.accessToken,
            userId: session.userId,
            transport: URLSessionTransport()
        )
    }

    private func saveProfile() async {
        guard let client = client() else { status = "先登录"; return }
        do {
            try await client.saveProfile(profile)
            status = "学习设置已保存。下一期的 snapshot 会带上新的水平和词数。"
        } catch {
            status = "保存失败"
        }
    }

    private func saveAppSettings() async {
        guard let client = client() else { status = "先登录"; return }
        do { try await client.saveSettings(appSettings); status = "已保存" } catch { status = "保存失败" }
    }

    private func saveKey() async {
        guard let client = client() else { status = "先登录"; return }
        do {
            let row = try await client.saveKey(provider: profile.provider, label: "default", secret: keySecret)
            keyHint = row.keyHint
            keySecret = ""
            status = "key 已存，界面上只留末四位"
        } catch {
            status = "key 保存失败"
        }
    }

    private func addRss() async {
        guard let client = client() else { status = "先登录"; return }
        do {
            try await client.addRss(title: "RSS", url: rssURL, topic: "general")
            rssURL = ""
            status = "已订阅"
        } catch {
            status = "订阅失败"
        }
    }

    private func copyPrompt() async {
        guard let client = client() else { status = "先登录"; return }
        do {
            try await client.copyPrompt(task: "select", body: promptBody, basedOnId: "", basedOnVersion: 1)
            status = "已保存你的 prompt"
        } catch {
            status = "prompt 保存失败"
        }
    }

    private func restorePrompt() async {
        guard let client = client() else { status = "先登录"; return }
        do {
            try await client.restorePrompt(task: "select")
            promptBody = ""
            status = "已恢复平台 prompt"
        } catch {
            status = "恢复失败"
        }
    }
}
