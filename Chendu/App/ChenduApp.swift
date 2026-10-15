import SwiftData
import SwiftUI
import UserNotifications

@main
struct ChenduApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = IssueStore.shared

    let container: ModelContainer = {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-uiTestInMemoryStore")
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try! ModelContainer(for: UserNote.self, configurations: config)
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onAppear { appDelegate.store = store }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { DailyReminder.schedule() }
            if phase == .background { DailyReminder.scheduleRefresh() }
        }
        .backgroundTask(.appRefresh(DailyReminder.refreshTaskID)) {
            await Self.prefetchLatest()
        }
    }

    @MainActor
    static func prefetchLatest() async {
        DailyReminder.scheduleRefresh()
        let store = IssueStore.shared
        await store.refreshIndex()
        if let latest = store.summaries.first {
            _ = try? await store.issue(latest.date)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var store: IssueStore?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { store?.openLatestRequested = true }
    }
}

struct RootView: View {
    @State private var auth: SessionStore

    init() {
        if ProcessInfo.processInfo.arguments.contains("-forceSignedOut") {
            SessionStore.live.clear()
        }
        _auth = State(initialValue: SessionStore.live)
    }

    var body: some View {
        Group {
            if auth.session == nil {
                LoginView(auth: auth)
            } else {
                TabView {
                    IssueListView()
                        .tabItem { Label("晨读", systemImage: "book") }
                    MyNotesView()
                        .tabItem { Label("我的笔记", systemImage: "pencil.and.list.clipboard") }
                    SettingsView()
                        .tabItem { Label("设置", systemImage: "gearshape") }
                }
            }
        }
        .tint(.grammarRed)
        .preferredColorScheme(.light)
    }
}
