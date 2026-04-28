import SwiftUI
import Combine
import UserNotifications

struct MenuBarView: View {
    private enum SwitchRequestOrigin {
        case manual
        case automaticSuggestion
        case bridgeAuto

        var bridgeSource: ControlPendingSwitchSource {
            switch self {
            case .manual: return .manual
            case .automaticSuggestion: return .automaticSuggestion
            case .bridgeAuto: return .bridgeAuto
            }
        }
    }

    @EnvironmentObject var store: TokenStore
    @EnvironmentObject var oauth: OAuthManager
    @EnvironmentObject var permissions: PermissionManager
    private let runtimeMonitor = CodexRuntimeMonitor.shared
    private let bridge = ControlBridge.shared
    @State private var isRefreshing = false
    @State private var showError: String?
    @State private var showSuccess: String?
    @State private var now = Date()
    @State private var refreshingAccounts: Set<String> = []
    @State private var pendingSwitchIdentityKey: String?
    @State private var pendingSwitchOrigin: SwitchRequestOrigin = .manual
    @State private var pendingSwitchReady = false
    @State private var switchPromptVisible = false
    @State private var dismissedAutomaticSwitchIdentityKey: String?

    // 每 10 秒刷新倒计时显示
    private let countdownTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    // 菜单打开时 10 秒快速刷新活跃账号；菜单关闭时 5 分钟后台刷新全部
    private let quickTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private let slowTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let pendingSwitchTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State private var menuVisible = false
    @State private var languageToggle = false  // 用于触发语言切换后的重绘

    /// workspace/personal group → accounts
    private var groupedAccounts: [(id: String, title: String, accounts: [TokenAccount])] {
        var dict: [String: [TokenAccount]] = [:]
        var titles: [String: String] = [:]
        var personalFlags: [String: Bool] = [:]

        for acc in store.accounts {
            let key = acc.workspaceGroupKey
            dict[key, default: []].append(acc)
            titles[key] = acc.workspaceGroupTitle
            personalFlags[key] = acc.isPersonalWorkspace
        }

        let sortedKeys = dict.keys.sorted { key1, key2 in
            let personal1 = personalFlags[key1] ?? false
            let personal2 = personalFlags[key2] ?? false
            if personal1 != personal2 { return !personal1 }

            let best1 = bestStatus(dict[key1]!)
            let best2 = bestStatus(dict[key2]!)
            if best1 != best2 { return best1 < best2 }

            let title1 = titles[key1] ?? key1
            let title2 = titles[key2] ?? key2
            return title1.localizedCaseInsensitiveCompare(title2) == .orderedAscending
        }

        return sortedKeys.map { key in
            let sorted = dict[key]!.sorted { a, b in
                if a.isActive != b.isActive { return a.isActive }
                if statusRank(a) != statusRank(b) { return statusRank(a) < statusRank(b) }
                return a.rowTitle.localizedCaseInsensitiveCompare(b.rowTitle) == .orderedAscending
            }
            return (
                id: key,
                title: titles[key] ?? key,
                accounts: sorted
            )
        }
    }

    private func bestStatus(_ accounts: [TokenAccount]) -> Int {
        accounts.map { statusRank($0) }.min() ?? 2
    }

    private func statusRank(_ a: TokenAccount) -> Int {
        switch a.usageStatus {
        case .ok: return 0
        case .warning: return 1
        case .exceeded: return 2
        case .banned: return 3
        }
    }

    private var availableCount: Int {
        store.accounts.filter { $0.usageStatus == .ok }.count
    }

    private var pendingSwitchAccount: TokenAccount? {
        guard let key = pendingSwitchIdentityKey else { return nil }
        return store.accounts.first { $0.identityKey == key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("CodexAppBar")
                    .font(.system(size: 13, weight: .semibold))

                if !store.accounts.isEmpty {
                    Text(L.available(availableCount, store.accounts.count))
                        .font(.system(size: 10))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(availableCount > 0 ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                        .foregroundColor(availableCount > 0 ? .green : .red)
                        .cornerRadius(4)
                }

                Spacer()

                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
                .buttonStyle(.borderless)
                .help(L.refreshUsage)
                .disabled(isRefreshing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if store.accounts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(L.noAccounts)
                        .foregroundColor(.secondary)
                    Text(L.addAccountHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !store.accounts.isEmpty {
                            ForEach(groupedAccounts, id: \.id) { group in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.title)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .padding(.leading, 4)

                                    ForEach(group.accounts) { account in
                                        AccountRowView(
                                            account: account,
                                            isActive: account.isActive,
                                            now: now,
                                            isRefreshing: refreshingAccounts.contains(account.id)
                                        ) {
                                            activateAccount(account)
                                        } onRefresh: {
                                            Task { await refreshAccount(account) }
                                        } onReauth: {
                                            reauthAccount(account)
                                        } onDelete: {
                                            store.remove(account)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 520)
            }

            if let success = showSuccess {
                Divider()
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(success)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            if let error = showError {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text(error)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        showError = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            // 底部操作栏
            HStack(spacing: 8) {
                if let lastUpdate = store.accounts.compactMap({ $0.lastChecked }).max() {
                    Text(relativeTime(lastUpdate))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    oauth.startOAuth { result in
                        switch result {
                        case .success(let tokens):
                            let account = AccountBuilder.build(from: tokens)
                            store.addOrUpdate(account)
                            Task { await WhamService.shared.refreshOne(account: account, store: store) }
                        case .failure(let error):
                            showError = error.localizedDescription
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help(L.addAccount)

                Button {
                    store.clearAllAccounts()
                    showError = nil
                    showSuccess = "已清空账号池。"
                    publishBridgeStatus()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("清空账号池")

                Button {
                    switch L.languageOverride {
                    case nil:   L.languageOverride = true
                    case true:  L.languageOverride = false
                    case false: L.languageOverride = nil
                    }
                    languageToggle.toggle()
                } label: {
                    // languageToggle 作为 @State 依赖，保证切换后重绘
                    let label = languageToggle ? L.languageOverride : L.languageOverride
                    Text(label == nil ? "AUTO" : (label == true ? "中" : "EN"))
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("切换语言 / Switch Language")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help(L.quit)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 360)
        .onReceive(countdownTimer) { _ in now = Date() }
        .onReceive(pendingSwitchTimer) { _ in
            handlePendingSwitch()
        }
        .onReceive(quickTimer) { _ in
            guard menuVisible,
                  let active = store.accounts.first(where: { $0.isActive }),
                  !active.secondaryExhausted else { return }
            Task {
                await refreshAccount(active)
                store.markActiveAccount()
                autoSwitchIfNeeded()
            }
        }
        .onReceive(slowTimer) { _ in
            Task {
                if !menuVisible { await refresh() }
                store.markActiveAccount()
                autoSwitchIfNeeded()
            }
        }
        .onAppear {
            menuVisible = true
            store.markActiveAccount()
            publishBridgeStatus()
            handlePendingSwitch()
        }
        .onDisappear { menuVisible = false }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return L.justUpdated }
        if seconds < 3600 { return L.minutesAgo(seconds / 60) }
        return L.hoursAgo(seconds / 3600)
    }

    private func activateAccount(_ account: TokenAccount) {
        requestSwitch(to: account, origin: .manual)
    }

    private func requestSwitch(to account: TokenAccount, origin: SwitchRequestOrigin) {
        guard !account.isActive else { return }

        let running = runtimeMonitor.runningCodexApplications()
        let hasRecentActivity = runtimeMonitor.hasRecentTaskActivity()

        if origin != .manual, pendingSwitchIdentityKey != nil {
            return
        }

        if hasRecentActivity {
            queuePendingSwitch(for: account, origin: origin, markReady: false, showAlert: origin == .manual)
            return
        }

        if origin == .automaticSuggestion && !menuVisible {
            queuePendingSwitch(for: account, origin: origin, markReady: true, showAlert: false)
            return
        }

        if origin == .bridgeAuto {
            performSwitch(account, running: running)
        } else {
            confirmAndSwitch(account, running: running)
        }
    }

    private func queuePendingSwitch(
        for account: TokenAccount,
        origin: SwitchRequestOrigin,
        markReady: Bool,
        showAlert: Bool
    ) {
        if origin == .automaticSuggestion,
           dismissedAutomaticSwitchIdentityKey == account.identityKey {
            return
        }

        let isSamePending = pendingSwitchIdentityKey == account.identityKey
        if isSamePending, pendingSwitchReady == markReady, !showAlert {
            return
        }

        pendingSwitchIdentityKey = account.identityKey
        pendingSwitchOrigin = origin
        pendingSwitchReady = markReady
        showError = nil

        if origin == .manual {
            dismissedAutomaticSwitchIdentityKey = nil
        }

        showSuccess = markReady ? L.switchReadyBody(account.rowTitle) : L.switchScheduled(account.rowTitle)

        if origin == .automaticSuggestion {
            let activeLabel = store.activeAccount()?.rowTitle ?? store.activeAccount()?.email ?? ""
            sendNotification(
                title: L.autoSwitchSuggestedTitle,
                body: L.autoSwitchSuggestedBody(activeLabel.isEmpty ? L.switchAccount : activeLabel, account.rowTitle)
            )
        } else if markReady, !isSamePending {
            sendNotification(title: L.switchReadyTitle, body: L.switchReadyBody(account.rowTitle))
        }

        if !showAlert {
            publishBridgeStatus()
            return
        }

        let alert = NSAlert()
        alert.messageText = L.switchQueuedTitle
        alert.informativeText = L.switchQueuedBody(account.rowTitle)
        alert.addButton(withTitle: L.gotIt)
        alert.runModal()
        publishBridgeStatus()
    }

    private func handlePendingSwitch() {
        guard let account = pendingSwitchAccount else {
            clearPendingSwitch()
            return
        }

        if !pendingSwitchReady {
            guard !runtimeMonitor.hasRecentTaskActivity() else { return }
            pendingSwitchReady = true
            showSuccess = L.switchReadyBody(account.rowTitle)
            if pendingSwitchOrigin != .bridgeAuto {
                sendNotification(title: L.switchReadyTitle, body: L.switchReadyBody(account.rowTitle))
            }
            publishBridgeStatus()
        }

        guard pendingSwitchReady else { return }

        if pendingSwitchOrigin == .bridgeAuto {
            performSwitch(account, running: runtimeMonitor.runningCodexApplications())
            return
        }

        guard menuVisible, !switchPromptVisible else { return }
        confirmAndSwitch(account, running: runtimeMonitor.runningCodexApplications())
    }

    private func clearPendingSwitch() {
        pendingSwitchIdentityKey = nil
        pendingSwitchOrigin = .manual
        pendingSwitchReady = false
        publishBridgeStatus()
    }

    private func confirmAndSwitch(_ account: TokenAccount, running: [NSRunningApplication]) {
        switchPromptVisible = true
        defer { switchPromptVisible = false }

        let alert = NSAlert()
        alert.messageText = L.switchPromptTitle(account.rowTitle)
        alert.informativeText = running.isEmpty
            ? L.switchPromptInfoStopped(account.rowTitle)
            : L.switchPromptInfoRunning(account.rowTitle)
        alert.addButton(withTitle: L.confirmSwitchAction)
        alert.addButton(withTitle: L.cancel)

        guard alert.runModal() == .alertFirstButtonReturn else {
            if pendingSwitchAccount?.identityKey == account.identityKey {
                if pendingSwitchOrigin == .automaticSuggestion {
                    dismissedAutomaticSwitchIdentityKey = account.identityKey
                }
                clearPendingSwitch()
            }
            return
        }

        performSwitch(account, running: running)
    }

    private func performSwitch(_ account: TokenAccount, running: [NSRunningApplication]) {
        do {
            try store.activate(account)
            clearPendingSwitch()
            dismissedAutomaticSwitchIdentityKey = nil
            showError = nil

            if running.isEmpty {
                showSuccess = L.switchApplied(account.rowTitle)
            } else {
                showSuccess = L.switchAppliedAndRestarting(account.rowTitle)
                restartCodex(running)
            }
        } catch {
            showError = error.localizedDescription
        }
        publishBridgeStatus()
    }

    /// 检查当前账号额度，必要时自动切换到最优账号
    private func autoSwitchIfNeeded() {
        guard let active = store.accounts.first(where: { $0.isActive }) else { return }
        guard pendingSwitchIdentityKey == nil else { return }

        let primary5hRemaining  = 100.0 - active.primaryUsedPercent
        let secondary7dRemaining = 100.0 - active.secondaryUsedPercent

        let shouldSwitch = primary5hRemaining <= 10.0 || secondary7dRemaining <= 3.0
        guard shouldSwitch else { return }

        // 找最优账号：未被封禁、token 未过期、非当前账号、usageStatus 最优
        let candidates = store.accounts.filter {
            !$0.isSuspended && !$0.tokenExpired && $0.identityKey != active.identityKey
        }.sorted {
            if statusRank($0) != statusRank($1) { return statusRank($0) < statusRank($1) }
            let rem0 = min(100 - $0.primaryUsedPercent, 100 - $0.secondaryUsedPercent)
            let rem1 = min(100 - $1.primaryUsedPercent, 100 - $1.secondaryUsedPercent)
            return rem0 > rem1
        }

        guard let best = candidates.first else {
            // 无可用账号，发通知提醒用户
            sendNotification(title: L.autoSwitchTitle, body: L.autoSwitchNoCandidates)
            return
        }

        guard dismissedAutomaticSwitchIdentityKey != best.identityKey else { return }

        requestSwitch(to: best, origin: .automaticSuggestion)
    }

    private func bridgeHeartbeat() {
        processBridgeCommand()
        publishBridgeStatus()
    }

    private func processBridgeCommand() {
        guard let handle = bridge.nextCommand() else { return }

        switch handle.command.action {
        case .switchWhenIdle:
            guard let identityKey = handle.command.identityKey, !identityKey.isEmpty else {
                bridge.finish(handle, status: .error, message: "Missing identityKey.")
                return
            }

            guard pendingSwitchIdentityKey == nil else {
                bridge.finish(handle, status: .error, message: "Another switch is already pending.")
                return
            }

            guard let account = store.accounts.first(where: { $0.identityKey == identityKey }) else {
                bridge.finish(handle, status: .error, message: "Account not found.")
                return
            }

            if account.isActive {
                bridge.finish(handle, status: .success, message: "Account is already active.")
                return
            }

            let busy = runtimeMonitor.hasRecentTaskActivity()
            requestSwitch(to: account, origin: .bridgeAuto)
            bridge.finish(
                handle,
                status: busy ? .accepted : .success,
                message: busy
                    ? "Queued switch to \(account.rowTitle) until Codex becomes idle."
                    : "Switched to \(account.rowTitle)."
            )

        case .cancelPendingSwitch:
            if let pending = pendingSwitchAccount {
                clearPendingSwitch()
                showSuccess = "Cancelled pending switch to \(pending.rowTitle)."
                bridge.finish(handle, status: .success, message: "Cancelled pending switch.")
            } else {
                bridge.finish(handle, status: .success, message: "No pending switch to cancel.")
            }

        case .refreshNow:
            bridge.finish(handle, status: .accepted, message: "Refresh requested.")
            Task {
                await refresh()
                publishBridgeStatus()
            }
        }
    }

    private func publishBridgeStatus() {
        let activeAccount = store.activeAccount()
        let pending: ControlPendingSwitch? = pendingSwitchAccount.map { account in
            ControlPendingSwitch(
                identityKey: account.identityKey,
                email: account.rowTitle,
                workspace: account.workspaceGroupTitle,
                ready: pendingSwitchReady,
                source: pendingSwitchOrigin.bridgeSource
            )
        }

        let accounts = store.accounts.map { account in
            ControlAccountSummary(
                identityKey: account.identityKey,
                email: account.rowTitle,
                workspace: account.workspaceGroupTitle,
                planType: account.planType,
                isActive: account.isActive,
                usageStatus: usageStatusName(account.usageStatus),
                primaryUsedPercent: account.primaryUsedPercent,
                secondaryUsedPercent: account.secondaryUsedPercent,
                tokenExpired: account.tokenExpired,
                isSuspended: account.isSuspended
            )
        }

        let status = ControlStatus(
            updatedAt: Date(),
            appRunning: true,
            codexRunning: !runtimeMonitor.runningCodexApplications().isEmpty,
            codexBusy: runtimeMonitor.hasRecentTaskActivity(),
            fullDiskAccessGranted: permissions.fullDiskAccessGranted,
            activeIdentityKey: activeAccount?.identityKey,
            activeEmail: activeAccount?.rowTitle,
            pendingSwitch: pending,
            lastSuccess: showSuccess,
            lastError: showError,
            accounts: accounts
        )

        bridge.writeStatus(status)
    }

    private func usageStatusName(_ status: UsageStatus) -> String {
        switch status {
        case .ok: return "ok"
        case .warning: return "warning"
        case .exceeded: return "exceeded"
        case .banned: return "banned"
        }
    }

    private func sendNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "codexbar-\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    private func restartCodex(_ running: [NSRunningApplication]) {
        let ws = NSWorkspace.shared
        let url = ws.urlForApplication(withBundleIdentifier: "com.openai.codex")

        running.forEach { $0.forceTerminate() }

        guard let url else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            ws.open(url)
        }
    }

    private func refresh() async {
        isRefreshing = true
        await WhamService.shared.refreshAll(store: store)
        isRefreshing = false
    }

    private func refreshAccount(_ account: TokenAccount) async {
        refreshingAccounts.insert(account.id)
        await WhamService.shared.refreshOne(account: account, store: store)
        refreshingAccounts.remove(account.id)
    }

    private func reauthAccount(_ account: TokenAccount) {
        oauth.startOAuth { result in
            switch result {
            case .success(let tokens):
                var updated = AccountBuilder.build(from: tokens)
                // 同一个 team 下的不同成员要能并存，因此按成员级 identityKey 判断是否覆盖
                if updated.identityKey == account.identityKey {
                    updated.isActive = account.isActive
                    updated.tokenExpired = false
                    updated.isSuspended = false
                }
                store.addOrUpdate(updated)
                Task { await WhamService.shared.refreshOne(account: updated, store: store) }
            case .failure(let error):
                showError = error.localizedDescription
            }
        }
    }
}
