import Foundation

/// Bilingual string helper — detects system language at runtime, with user override.
enum L {
    /// nil = follow system, true = force Chinese, false = force English
    static var languageOverride: Bool? {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: "languageOverride") != nil else { return nil }
            return d.bool(forKey: "languageOverride")
        }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v, forKey: "languageOverride")
            } else {
                UserDefaults.standard.removeObject(forKey: "languageOverride")
            }
        }
    }

    static var zh: Bool {
        if let override = languageOverride { return override }
        let lang = Locale.current.language.languageCode?.identifier ?? ""
        return lang.hasPrefix("zh")
    }

    // MARK: - Status Bar
    static var weeklyLimit: String { zh ? "周限额" : "Weekly Limit" }
    static var hourLimit: String   { zh ? "5h限额" : "5h Limit" }

    // MARK: - MenuBarView
    static var noAccounts: String      { zh ? "还没有账号"          : "No Accounts" }
    static var addAccountHint: String  { zh ? "点击下方 + 添加账号"   : "Tap + below to add an account" }
    static var refreshUsage: String    { zh ? "刷新用量"            : "Refresh Usage" }
    static var addAccount: String      { zh ? "添加账号"            : "Add Account" }
    static var relayTitle: String { zh ? "API 中转站" : "API Relay" }
    static var relayHint: String {
        zh ? "适合接 OpenAI 兼容的第三方中转站。激活后会把 API Key 写入 ~/.codex/auth.json，并把 Base URL 写入 ~/.codex/config.toml。" :
        "Use OpenAI-compatible relay/proxy endpoints. Activation writes the API key to ~/.codex/auth.json and the base URL to ~/.codex/config.toml."
    }
    static var relayEmptyHint: String { zh ? "还没有 API 中转站配置" : "No relay profiles yet" }
    static var relayNameField: String { zh ? "名称" : "Name" }
    static var relayBaseURLField: String { zh ? "Base URL" : "Base URL" }
    static var relayAPIKeyField: String { zh ? "API Key" : "API Key" }
    static var relayModelField: String { zh ? "模型（可选）" : "Model (optional)" }
    static var relaySaveButton: String { zh ? "保存配置" : "Save Profile" }
    static var relayActivateButton: String { zh ? "启用" : "Activate" }
    static var relayActiveTag: String { zh ? "当前生效" : "Active" }
    static var relayDeleteActiveError: String { zh ? "当前生效的 Relay 不能直接删除，请先切回其他账号或其他 Relay。" : "You can't delete the active relay profile. Switch away first." }
    static var relayValidationError: String { zh ? "请至少填写名称、Base URL 和 API Key。" : "Name, Base URL, and API key are required." }
    static var relayInvalidBaseURL: String { zh ? "Base URL 看起来不对，请填写 http(s):// 开头的完整地址。" : "Base URL looks invalid. Use a full http(s):// URL." }
    static func relaySaved(_ name: String) -> String {
        zh ? "已保存 API 中转站「\(name)」。" : "Saved relay profile \"\(name)\"."
    }
    static func relayDeleted(_ name: String) -> String {
        zh ? "已删除 API 中转站「\(name)」。" : "Deleted relay profile \"\(name)\"."
    }
    static func relaySwitchPromptTitle(_ name: String) -> String {
        zh ? "启用 API 中转站「\(name)」" : "Activate relay \"\(name)\""
    }
    static func relaySwitchPromptInfoRunning(_ name: String) -> String {
        zh
            ? "确认后会把「\(name)」写入 Codex 配置，并自动退出后重新打开 Codex.app。\n\n如果你当前还有重要任务在跑，建议先等它结束。"
            : "This will apply relay \"\(name)\" to Codex and restart Codex.app.\n\nIf an important task is still running, wait for it to finish first."
    }
    static func relaySwitchPromptInfoStopped(_ name: String) -> String {
        zh
            ? "确认后会把「\(name)」写入 Codex 配置，下次打开 Codex.app 时生效。"
            : "This will apply relay \"\(name)\" to Codex. The change will take effect next time Codex.app opens."
    }
    static func relayActivated(_ name: String) -> String {
        zh ? "已启用 API 中转站「\(name)」。" : "Activated relay \"\(name)\"."
    }
    static func relayActivatedAndRestarting(_ name: String) -> String {
        zh ? "已启用 API 中转站「\(name)」，正在重新打开 Codex.app。" : "Activated relay \"\(name)\" and restarting Codex.app."
    }
    static func relayDeletePrompt(_ name: String) -> String {
        zh ? "确认删除 API 中转站「\(name)」？" : "Delete relay profile \"\(name)\"?"
    }
    static var relayMenuBadge: String { zh ? "API Relay" : "API Relay" }
    static var personalAccountsGroup: String { zh ? "个人账号" : "Personal Accounts" }
    static var fullDiskAccessTitle: String { zh ? "需要完全磁盘访问权限" : "Full Disk Access Needed" }
    static var fullDiskAccessHint: String {
        zh
            ? "macOS 不允许应用自动授予该权限。已在启动时自动打开设置页；你打开开关后，建议重新启动本应用。"
            : "macOS does not allow apps to grant this permission automatically. The settings page was opened on launch; after enabling it, restart this app."
    }
    static var openSettings: String { zh ? "打开设置" : "Open Settings" }
    static var quit: String            { zh ? "退出"               : "Quit" }
    static var gotIt: String           { zh ? "知道了"             : "OK" }
    static var switchQueuedTitle: String { zh ? "切换已挂起" : "Switch Queued" }
    static func switchQueuedBody(_ name: String) -> String {
        zh
            ? "检测到 Codex.app 仍有任务活动，将在任务结束后再提示你切换到「\(name)」。"
            : "Codex.app is still busy. You'll be prompted to switch to \"\(name)\" after tasks finish."
    }
    static var switchReadyTitle: String { zh ? "可以切换了" : "Ready to Switch" }
    static func switchReadyBody(_ name: String) -> String {
        zh
            ? "检测到任务已结束。打开菜单后可确认切换到「\(name)」。"
            : "Tasks look finished. Open the menu to confirm switching to \"\(name)\"."
    }
    static func switchPromptTitle(_ name: String) -> String {
        zh ? "切换到「\(name)」" : "Switch to \"\(name)\""
    }
    static func switchPromptInfoRunning(_ name: String) -> String {
        zh
            ? "当前没有检测到正在进行的任务。\n\n确认后将切换到「\(name)」，并自动退出后重新打开 Codex.app。"
            : "No active tasks were detected.\n\nConfirm to switch to \"\(name)\" and automatically restart Codex.app."
    }
    static func switchPromptInfoStopped(_ name: String) -> String {
        zh
            ? "当前 Codex.app 未在运行。\n\n确认后将切换到「\(name)」，下次打开 Codex.app 时生效。"
            : "Codex.app is not running.\n\nConfirm to switch to \"\(name)\". The change will apply next time Codex.app opens."
    }
    static var confirmSwitchAction: String { zh ? "确认切换" : "Confirm Switch" }
    static func switchScheduled(_ name: String) -> String {
        zh ? "已挂起切换到「\(name)」，任务结束后会提醒你确认。" : "Queued switch to \"\(name)\" and will remind you when tasks finish."
    }
    static func switchApplied(_ name: String) -> String {
        zh ? "已切换到「\(name)」。" : "Switched to \"\(name)\"."
    }
    static func switchAppliedAndRestarting(_ name: String) -> String {
        zh ? "已切换到「\(name)」，正在重新打开 Codex.app。" : "Switched to \"\(name)\" and restarting Codex.app."
    }
    static var autoSwitchSuggestedTitle: String {
        zh ? "建议切换账号" : "Switch Suggested"
    }
    static func autoSwitchSuggestedBody(_ from: String, _ to: String) -> String {
        zh
            ? "检测到「\(from)」额度偏低，已准备在空闲后让你确认切换到「\(to)」。"
            : "Quota is getting low on \"\(from)\". A switch to \"\(to)\" is ready for your confirmation when Codex is idle."
    }
    static var switchAccount: String    { zh ? "切换账号"            : "Switch Account" }
    static var switchTitle: String     { zh ? "切换账号"            : "Switch Account" }
    static var continueRestart: String { zh ? "继续"               : "Continue" }
    static var cancel: String          { zh ? "取消"               : "Cancel" }
    static var justUpdated: String     { zh ? "刚刚更新"            : "Just updated" }
    static var restartCodexTitle: String {
        zh ? "Codex.app 正在运行" : "Codex.app is Running"
    }
    static var restartCodexInfo: String {
        zh
            ? "账号已切换完成。\n\n如需立即生效，可强制退出 Codex.app（可选是否自动重新打开）。\n\n⚠️ 警告：强制退出将终止所有 subagent 任务，可能导致进行中的任务丢失，请谨慎操作。"
            : "Account switched successfully.\n\nYou may force-quit Codex.app now to apply the change (optionally reopen it).\n\n⚠️ Warning: Force-quitting will kill all running subagent tasks. Make sure no important tasks are in progress."
    }
    static var forceQuitAndReopen: String { zh ? "强制退出并重新打开" : "Force Quit & Reopen" }
    static var forceQuitOnly: String    { zh ? "仅强制退出" : "Force Quit Only" }
    static var restartLater: String     { zh ? "稍后手动重启" : "Later" }

    static func available(_ n: Int, _ total: Int) -> String {
        zh ? "\(n)/\(total) 可用" : "\(n)/\(total) Available"
    }
    static func minutesAgo(_ m: Int) -> String {
        zh ? "\(m) 分钟前更新" : "Updated \(m) min ago"
    }
    static func hoursAgo(_ h: Int) -> String {
        zh ? "\(h) 小时前更新" : "Updated \(h) hr ago"
    }
    static var switchWarningTitle: String {
        zh ? "⚠️ 实验性功能 — 账号切换" : "⚠️ Experimental — Account Switch"
    }
    static func switchConfirm(_ name: String) -> String { switchWarning(name) }
    static func switchConfirmMsg(_ name: String) -> String { switchWarning(name) }
    static func switchWarning(_ name: String) -> String {
        zh
            ? "⚠️ 实验性功能\n\n将切换到「\(name)」。\n\n此功能通过直接修改配置文件实现辅助切换，需要退出整个 Codex.app 才能生效。退出过程中可能导致数据丢失！\n\n如果你正在使用 subagent，强烈建议通过软件内的退出登录功能重新登录其他账号，而非使用此切换方案。"
            : "⚠️ Experimental Feature\n\nSwitching to \"\(name)\".\n\nThis feature works by modifying the config file directly. Codex.app must be fully quit to apply the change, which may cause data loss.\n\nIf you are using subagents, it is strongly recommended to log out from within Codex.app and log in with another account instead."
    }

    // MARK: - Auto switch
    static var autoSwitchTitle: String {
        zh ? "已自动切换账号" : "Account Auto-Switched"
    }
    static func autoSwitchBody(_ from: String, _ to: String) -> String {
        zh
            ? "「\(from)」额度不足，已自动切换至「\(to)」"
            : "Quota low on \"\(from)\", switched to \"\(to)\""
    }
    static var autoSwitchNoCandidates: String {
        zh
            ? "所有账号额度不足或不可用，请手动处理"
            : "All accounts are low or unavailable, please take action"
    }

    // MARK: - AccountRowView
    static var reauth: String          { zh ? "重新授权"     : "Re-authorize" }
    static var switchBtn: String       { zh ? "切换"         : "Switch" }
    static var tokenExpiredMsg: String { zh ? "Token 已过期，请重新授权" : "Token expired, please re-authorize" }
    static var bannedMsg: String       { zh ? "账号已停用"   : "Account suspended" }
    static var deleteBtn: String       { zh ? "删除"         : "Delete" }
    static var deleteConfirm: String   { zh ? "删除"         : "Delete" }

    static func deletePrompt(_ name: String) -> String {
        zh ? "确认删除 \(name)？" : "Delete \(name)?"
    }
    static func confirmDelete(_ name: String) -> String { deletePrompt(name) }
    static var delete: String         { zh ? "删除"     : "Delete" }
    static var tokenExpiredHint: String { zh ? "Token 已过期，请重新授权" : "Token expired, please re-authorize" }
    static var accountSuspended: String { zh ? "账号已停用" : "Account suspended" }
    static var weeklyExhausted: String  { zh ? "周额度耗尽" : "Weekly quota exhausted" }
    static var primaryExhausted: String { zh ? "5h 额度耗尽" : "5h quota exhausted" }

    // MARK: - TokenAccount status
    static var statusOk: String       { zh ? "正常"     : "OK" }
    static var statusWarning: String  { zh ? "即将用尽" : "Warning" }
    static var statusExceeded: String { zh ? "额度耗尽" : "Exceeded" }
    static var statusBanned: String   { zh ? "已停用"   : "Suspended" }

    // MARK: - Reset countdown
    static var resetSoon: String { zh ? "即将重置" : "Resetting soon" }
    static func resetInMin(_ m: Int) -> String {
        zh ? "\(m) 分钟后重置" : "Resets in \(m) min"
    }
    static func resetInHr(_ h: Int, _ m: Int) -> String {
        zh ? "\(h) 小时 \(m) 分后重置" : "Resets in \(h)h \(m)m"
    }
    static func resetInDay(_ d: Int, _ h: Int) -> String {
        zh ? "\(d) 天 \(h) 小时后重置" : "Resets in \(d)d \(h)h"
    }
}
