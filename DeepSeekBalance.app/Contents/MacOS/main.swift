import Cocoa
import Foundation

// ── Configuration ───────────────────────────────────────────────────────────
private let refreshInterval: TimeInterval = 60
private let deepseekBalanceURL = "https://api.deepseek.com/user/balance"
private let deepseekTopUpURL = "https://platform.deepseek.com/top_up"
private let thresholdDefaultsKey = "panicThreshold"

let thresholdOptions: [Double] = [0.50, 1.00, 1.50, 2.00, 3.00, 5.00, 10.00]

// ── Custom Status View ─────────────────────────────────────────────────────

class BalanceStatusView: NSView {
    var balanceText: String = "..." { didSet { needsDisplay = true } }
    var isLow: Bool = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    private var iconImage: NSImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        if let icon = Bundle.main.image(forResource: "deepseek-icon") {
            icon.isTemplate = true
            iconImage = icon
        }
    }
    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let iconSize: CGFloat = 14
        let iconRect = NSRect(x: 4, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
        iconImage?.draw(in: iconRect)

        let textX = iconRect.maxX + 4
        let textW = bounds.width - textX - 4
        let textRect = NSRect(x: textX, y: 2, width: textW, height: bounds.height - 4)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let color: NSColor = isLow ? NSColor(calibratedRed: 1, green: 0.2, blue: 0.2, alpha: 1) : .white
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (balanceText as NSString).draw(in: textRect, withAttributes: attrs)
    }
}

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
    var statusView: BalanceStatusView?
    var panicThreshold: Double {
        get { UserDefaults.standard.double(forKey: thresholdDefaultsKey).nonZero ?? 1.0 }
        set { UserDefaults.standard.set(newValue, forKey: thresholdDefaultsKey) }
    }

    func applicationDidFinishLaunching(_: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let sv = BalanceStatusView(frame: NSRect(x: 0, y: 0, width: 120, height: 22))
        sv.onClick = { [weak self] in self?.showMenu() }
        statusItem.view = sv
        statusView = sv

        refresh()
        timer = Timer.scheduledTimer(
            timeInterval: refreshInterval, target: self,
            selector: #selector(refresh), userInfo: nil, repeats: true)
        RunLoop.current.add(timer!, forMode: .common)
    }

    func showMenu() {
        guard let sv = statusView else { return }
        let menu = buildMenu()
        // Use the view's window to get proper screen coordinates
        if let window = sv.window {
            let frame = sv.convert(sv.bounds, to: nil)
            let screenFrame = window.convertToScreen(frame)
            let menuX = screenFrame.origin.x
            let menuY = screenFrame.origin.y - 5
            menu.popUp(positioning: nil, at: NSPoint(x: menuX, y: menuY), in: nil)
        } else {
            // Fallback: just show at reasonable position
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 22), in: sv)
        }
    }

    func buildMenu() -> NSMenu {
        let m = NSMenu()
        let titleItem = NSMenuItem(title: "DeepSeek Balance", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        m.addItem(titleItem)

        // Panic threshold submenu
        let thresholdItem = NSMenuItem(title: "Panic at", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let current = panicThreshold
        for opt in thresholdOptions {
            let item = NSMenuItem(title: String(format: "$%.2f", opt),
                                  action: #selector(setThreshold(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = opt
            if abs(opt - current) < 0.001 {
                item.state = .on
            }
            submenu.addItem(item)
        }
        thresholdItem.submenu = submenu
        m.addItem(thresholdItem)

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

    @objc func setThreshold(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? Double else { return }
        panicThreshold = val
        refresh()
    }

    @objc func refresh() {
        statusView?.balanceText = "refreshing..."
        Task { await doFetch() }
    }

    @objc func copyBalance() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(statusView?.balanceText ?? "?", forType: .string)
    }

    @objc func openTopUp() {
        if let url = URL(string: deepseekTopUpURL) { NSWorkspace.shared.open(url) }
    }

    @objc func quitApp() { NSApplication.shared.terminate(nil) }

    func doFetch() async {
        let balance = await fetchBalance()
        await MainActor.run {
            if let b = balance {
                let text = String(format: "%.2f USD", b)
                self.statusView?.balanceText = text
                self.statusView?.isLow = b < self.panicThreshold
                let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
                let textW = (text as NSString).size(withAttributes: [.font: font]).width
                let totalW = 4 + 14 + 4 + textW + 8
                self.statusItem.length = totalW
                self.statusView?.frame = NSRect(x: 0, y: 0, width: totalW, height: 22)
            } else {
                self.statusView?.balanceText = "--"
            }
        }
    }
}

// ── Helper ─────────────────────────────────────────────────────────────────

extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

// ── Bootstrap ──────────────────────────────────────────────────────────────

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = BalanceMonitor()
app.delegate = delegate
app.run()
