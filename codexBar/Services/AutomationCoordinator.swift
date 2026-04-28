import Foundation
import AppKit
import Combine

final class AutomationCoordinator: ObservableObject {
    static let shared = AutomationCoordinator()

    private let store = TokenStore.shared
    private let permissions = PermissionManager.shared
    private let runtimeMonitor = CodexRuntimeMonitor.shared
    private let bridge = ControlBridge.shared

    private var cancellables: Set<AnyCancellable> = []
    private var started = false

    private var pendingIdentityKey: String?
    private var pendingReady = false
    private var lastSuccess: String?
    private var lastError: String?

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        store.markActiveAccount()
        permissions.refreshFullDiskAccess()
        publishStatus()

        Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.heartbeat() }
            .store(in: &cancellables)

        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshUsage() }
            .store(in: &cancellables)
    }

    private var pendingAccount: TokenAccount? {
        guard let pendingIdentityKey else { return nil }
        return store.accounts.first { $0.identityKey == pendingIdentityKey }
    }

    private func heartbeat() {
        permissions.refreshFullDiskAccess()
        processBridgeCommand()
        handlePendingSwitch()
        publishStatus()
    }

    private func refreshUsage() {
        Task { [weak self] in
            await WhamService.shared.refreshAll(store: self?.store ?? .shared)
            self?.store.markActiveAccount()
            self?.publishStatus()
        }
    }

    private func processBridgeCommand() {
        guard let handle = bridge.nextCommand() else { return }

        switch handle.command.action {
        case .switchWhenIdle:
            guard let identityKey = handle.command.identityKey, !identityKey.isEmpty else {
                finish(handle, status: .error, message: "Missing identityKey.")
                return
            }

            guard pendingIdentityKey == nil else {
                finish(handle, status: .error, message: "Another bridge switch is already pending.")
                return
            }

            guard let account = store.accounts.first(where: { $0.identityKey == identityKey }) else {
                finish(handle, status: .error, message: "Account not found.")
                return
            }

            if account.isActive {
                finish(handle, status: .success, message: "Account is already active.")
                return
            }

            let busy = runtimeMonitor.hasRecentTaskActivity()
            requestBridgeSwitch(to: account)
            finish(
                handle,
                status: busy ? .accepted : .success,
                message: busy
                    ? "Queued switch to \(account.rowTitle) until Codex becomes idle."
                    : "Switched to \(account.rowTitle)."
            )

        case .cancelPendingSwitch:
            if let pending = pendingAccount {
                clearPendingSwitch()
                lastSuccess = "Cancelled pending switch to \(pending.rowTitle)."
                finish(handle, status: .success, message: "Cancelled pending switch.")
            } else {
                finish(handle, status: .success, message: "No pending switch to cancel.")
            }

        case .refreshNow:
            finish(handle, status: .accepted, message: "Refresh requested.")
            refreshUsage()
        }
    }

    private func requestBridgeSwitch(to account: TokenAccount) {
        if runtimeMonitor.hasRecentTaskActivity() {
            pendingIdentityKey = account.identityKey
            pendingReady = false
            lastError = nil
            lastSuccess = "Queued switch to \(account.rowTitle)."
            return
        }

        performSwitch(account)
    }

    private func handlePendingSwitch() {
        guard let account = pendingAccount else {
            clearPendingSwitch()
            return
        }

        guard !pendingReady else {
            performSwitch(account)
            return
        }

        guard !runtimeMonitor.hasRecentTaskActivity() else { return }
        pendingReady = true
        lastSuccess = "Ready to switch to \(account.rowTitle)."
        performSwitch(account)
    }

    private func clearPendingSwitch() {
        pendingIdentityKey = nil
        pendingReady = false
    }

    private func performSwitch(_ account: TokenAccount) {
        let running = runtimeMonitor.runningCodexApplications()

        do {
            try store.activate(account)
            clearPendingSwitch()
            lastError = nil

            if running.isEmpty {
                lastSuccess = "Switched to \(account.rowTitle)."
            } else {
                lastSuccess = "Switched to \(account.rowTitle) and restarting Codex.app."
                restartCodex(running)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func restartCodex(_ running: [NSRunningApplication]) {
        let workspace = NSWorkspace.shared
        let url = workspace.urlForApplication(withBundleIdentifier: "com.openai.codex")

        running.forEach { $0.forceTerminate() }

        guard let url else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            workspace.open(url)
        }
    }

    private func finish(_ handle: ControlBridge.CommandHandle, status: ControlResultStatus, message: String) {
        bridge.finish(handle, status: status, message: message)
        if status == .error {
            lastError = message
        } else {
            lastSuccess = message
        }
    }

    private func publishStatus() {
        let activeAccount = store.activeAccount()
        let activeRelay = store.activeRelayProfile()
        let pending = pendingAccount.map { account in
            ControlPendingSwitch(
                identityKey: account.identityKey,
                email: account.rowTitle,
                workspace: account.workspaceGroupTitle,
                ready: pendingReady,
                source: .bridgeAuto
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
            activeIdentityKey: activeRelay?.identityKey ?? activeAccount?.identityKey,
            activeEmail: activeRelay.map { "API Relay · \($0.rowTitle)" } ?? activeAccount?.rowTitle,
            pendingSwitch: pending,
            lastSuccess: lastSuccess,
            lastError: lastError,
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
}
