import SwiftUI

struct SettingsView: View {
    @Environment(IssueStore.self) private var store
    @AppStorage(DailyReminder.enabledKey) private var reminderOn = false
    @State private var denied = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
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
                    Text("新一期每天约 7:51 发布。开启后，系统会在后台尝试提前缓存最新一期。")
                }

                Section("离线") {
                    LabeledContent("已缓存", value: "\(store.cachedIssueCount) 期")
                    LabeledContent("占用空间", value: ByteCountFormatter.string(fromByteCount: store.cacheBytes, countStyle: .file))
                    Button("下载最近 7 期（含音频）") { Task { await store.saveRecentOffline(count: 7) } }
                        .disabled(store.summaries.isEmpty || !store.downloads.isEmpty)
                    if !store.downloads.isEmpty {
                        ProgressView("正在下载 \(store.downloads.count) 期…")
                    }
                    Button("清除缓存", role: .destructive) { confirmClear = true }
                }

                Section {
                    LabeledContent("当前数据源", value: store.indexSource.label)
                    if let t = store.lastRefresh {
                        LabeledContent("上次刷新", value: t.formatted(date: .abbreviated, time: .shortened))
                    }
                    Link("打开晨读网站", destination: SiteClient.baseURL)
                } header: {
                    Text("数据")
                } footer: {
                    Text("优先读取 /issues.json；网站未部署 JSON 时自动改为解析网页，两者内容一致。笔记只保存在本机。")
                }

                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Text("手写字体：马善政楷书（Ma Shan Zheng）、Caveat，均为 SIL Open Font License。")
                        .font(.footnote).foregroundStyle(Color.muted)
                }
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
}
