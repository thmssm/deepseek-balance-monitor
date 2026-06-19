import Cocoa
import Foundation

// ── Configuration ───────────────────────────────────────────────────────────
private let refreshInterval: TimeInterval = 60
private let deepseekBalanceURL = "https://api.deepseek.com/user/balance"
private let deepseekTopUpURL = "https://platform.deepseek.com/top_up"
private let panicThreshold: Double = 1.0

// ── API ────────────────────────────────────────────────────────────────────

func loadAPIKey() -> String? {
    if let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !key.isEmpty { return key }
    let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".deepseek-api-key").path
    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
    }
    return nil
}

func fetchBalance() async -> Double? {
    guard let apiKey = loadAPIKey(), let url = URL(string: deepseekBalanceURL) else { return nil }
    var req = URLRequest(url: url)
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.timeoutInterval = 10
    guard let (data, _) = try? await URLSession.shared.data(for: req),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let infos = json["balance_infos"] as? [[String: Any]],
          let first = infos.first,
          let raw = first["total_balance"] as? String,
          let val = Double(raw)
    else { return nil }
    return val
}

// ── Menu Bar App ───────────────────────────────────────────────────────────

class BalanceMonitor: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?

    func applicationDidFinishLaunching(_: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let btn = statusItem.button else { return }
        btn.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

        if let iconPath = Bundle.main.path(forResource: "deepseek-icon", ofType: "png"),
           let icon = NSImage(contentsOfFile: iconPath) {
            icon.isTemplate = true
            btn.image = icon
            btn.imagePosition = .imageLeading
        }

        btn.action = #selector(showMenu)
        btn.target = self

        refresh()
        timer = Timer.scheduledTimer(
            timeInterval: refreshInterval, target: self,
            selector: #selector(refresh), userInfo: nil, repeats: true)
        RunLoop.current.add(timer!, forMode: .common)
    }

    func buildMenu() -> NSMenu {
        let m = NSMenu()
        let titleItem = NSMenuItem(title: "DeepSeek Balance", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        m.addItem(titleItem)
        m.addItem(.separator())
        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self; m.addItem(refresh)
        let copy = NSMenuItem(title: "Copy Balance", action: #selector(copyBalance), keyEquivalent: "c")
        copy.target = self; m.addItem(copy)
        m.addItem(.separator())
        let topup = NSMenuItem(title: "Top Up →", action: #selector(openTopUp), keyEquivalent: "t")
        topup.target = self; m.addItem(topup)
        m.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; m.addItem(quit)
        return m
    }

    @objc func showMenu() {
        guard let btn = statusItem.button, let menu = buildMenu() as NSMenu? else { return }
        let pt = NSPoint(x: 0, y: btn.bounds.height + 5)
        menu.popUp(positioning: nil, at: pt, in: btn)
    }

    @objc func refresh() {
        guard let btn = statusItem.button else { return }
        btn.title = "refreshing..."
        Task { await doFetch() }
        btn.contentTintColor = nil
    }

    @objc func copyBalance() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(statusItem.button?.title ?? "?", forType: .string)
    }

    @objc func openTopUp() {
        if let url = URL(string: deepseekTopUpURL) { NSWorkspace.shared.open(url) }
    }

    @objc func quitApp() { NSApplication.shared.terminate(nil) }

    func doFetch() async {
        let balance = await fetchBalance()
        await MainActor.run {
            guard let btn = self.statusItem.button else { return }
            if let b = balance {
                let text = String(format: "%.2f USD", b)
                btn.title = text
                // contentTintColor tints both image and text (macOS 11+)
                btn.contentTintColor = b < panicThreshold ? .systemRed : nil
            } else {
                btn.title = "--"
                btn.contentTintColor = nil
            }
        }
    }
}

// ── Bootstrap ──────────────────────────────────────────────────────────────

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = BalanceMonitor()
app.delegate = delegate
app.run()
