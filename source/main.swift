import Foundation
import AppKit
import UserNotifications
import Security

struct Window: Codable {
    let usedPercent: Double
    let windowDurationMins: Int
    let resetsAt: TimeInterval?
}
struct Snapshot: Codable {
    var windows: [String: Window]
    var accountId: String?
    var ordinaryUsageAllowed: Bool?
}
struct Saved: Codable {
    var snapshot: Snapshot
    var lastChecked: Date
}

let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser
let storage = home.appendingPathComponent("Library/Application Support/CodexLimitWatch", isDirectory: true)
let stateFile = storage.appendingPathComponent("state.json")
let modeFile = storage.appendingPathComponent("mode.txt")
let languageFile = storage.appendingPathComponent("language.txt")
func localized(_ ru: String, _ en: String) -> String {
    return en
}
let logFile = storage.appendingPathComponent("watcher.log")
let intervalFile = storage.appendingPathComponent("interval-minutes.txt")
let channelFile = storage.appendingPathComponent("channel.txt")
let windowFile = storage.appendingPathComponent("limit-window.txt")
let thresholdFile = storage.appendingPathComponent("prod-threshold.txt")
let comparisonFile = storage.appendingPathComponent("prod-comparison.txt")
func prodComparison() -> String {
    (try? String(contentsOf: comparisonFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) == "lte" ? "lte" : "gte"
}
func selectedWindow() -> String {
    (try? String(contentsOf: windowFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) == "5hour" ? "5hour" : "week"
}
func prodThreshold() -> Double {
    let raw = (try? String(contentsOf: thresholdFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "98"
    return Double(max(5, min(100, Int(raw) ?? 98)))
}
let chatFile = storage.appendingPathComponent("telegram-chat-id.txt")
let keychainService = "dev.local.codex-limit-watch.telegram"
func intervalMinutes() -> Int {
    let text = (try? String(contentsOf: intervalFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "7"
    guard let n = Int(text), n >= 1, n <= 1440 else { return 7 }
    return n
}
func log(_ s: String) {
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(s)\n"
    print(line, terminator: "")
    try? fm.createDirectory(at: storage, withIntermediateDirectories: true)
    if let file = try? FileHandle(forWritingTo: logFile) {
        defer { try? file.close() }
        _ = try? file.seekToEnd()
        try? file.write(contentsOf: Data(line.utf8))
    } else { try? line.write(to: logFile, atomically: true, encoding: .utf8) }
}
func executable() -> String? {
    let configured = ProcessInfo.processInfo.environment["CODEX_BIN"] ?? (try? String(contentsOf:storage.appendingPathComponent("codex-path.txt"),encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines)
    let candidates: [String] = ([configured].compactMap { $0 }) + ["/opt/homebrew/bin/codex", home.appendingPathComponent(".volta/bin/codex").path, home.appendingPathComponent(".local/share/mise/shims/codex").path, "/usr/local/bin/codex", home.appendingPathComponent(".npm-global/bin/codex").path, home.appendingPathComponent(".local/bin/codex").path, home.appendingPathComponent(".bun/bin/codex").path, "/Applications/Codex.app/Contents/Resources/codex", "/Applications/Codex.app/Contents/Resources/codex-cli", "/Applications/Codex.app/Contents/MacOS/codex", home.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex").path, home.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex-cli").path, home.appendingPathComponent("Applications/Codex.app/Contents/MacOS/codex").path, "/opt/homebrew/Caskroom/codex/current/codex"]
    for candidate in candidates where fm.isExecutableFile(atPath: candidate) { return candidate }
    if let path = ProcessInfo.processInfo.environment["PATH"] {
        for dir in path.split(separator: ":") {
            let p = String(dir) + "/codex"
            if fm.isExecutableFile(atPath: p) { return p }
        }
    }
    // fnm installs may exist only inside ephemeral per-shell PATH directories.
    let fnmDir=home.appendingPathComponent(".local/state/fnm_multishells")
    if let entries=try? fm.contentsOfDirectory(at:fnmDir, includingPropertiesForKeys:nil) {
        for item in entries.sorted(by: {$0.lastPathComponent > $1.lastPathComponent}) {
            let path=item.appendingPathComponent("bin/codex").path
            if fm.isExecutableFile(atPath:path) { return path }
        }
    }
    let nodeDir=home.appendingPathComponent(".local/share/fnm/node-versions")
    if let versions=try? fm.contentsOfDirectory(at:nodeDir, includingPropertiesForKeys:nil) {
        for item in versions.sorted(by: {$0.lastPathComponent > $1.lastPathComponent}) {
            let path=item.appendingPathComponent("installation/bin/codex").path
            if fm.isExecutableFile(atPath:path) { return path }
        }
    }
    // Find bundled Codex executables in app resources, including version-specific layouts.
    for app in ["/Applications/Codex.app", home.appendingPathComponent("Applications/Codex.app").path] {
        let resources=URL(fileURLWithPath:app).appendingPathComponent("Contents/Resources")
        if let entries=try? fm.contentsOfDirectory(at:resources,includingPropertiesForKeys:nil) {
            for url in entries where url.lastPathComponent.lowercased().contains("codex") && fm.isExecutableFile(atPath:url.path) {
                return url.path
            }
        }
    }
    return nil
}

enum WatchError: Error, CustomStringConvertible {
    case problem(String)
    var description: String { if case let .problem(s) = self { return s }; return "Unknown error" }
}

final class RPC {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let mutex = NSLock()
    private var pending: [Int: DispatchSemaphore] = [:]
    private var replies: [Int: [String: Any]] = [:]
    private var buffer = Data()
    init(path: String) throws {
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            if bytes.isEmpty { handle.readabilityHandler = nil; return }
            self?.receive(bytes)
        }
    }
    private func receive(_ bytes: Data) {
        mutex.lock()
        buffer.append(bytes)
        while let idx = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<idx]); buffer.removeSubrange(...idx)
            if let json = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let id = json["id"] as? Int {
                replies[id] = json
                pending[id]?.signal()
            }
        }
        mutex.unlock()
    }
    private func send(_ payload: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: payload)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    func notify(_ method: String) throws { try send(["method":method]) }
    func call(_ method: String, id: Int, params: [String: Any]? = nil) throws -> [String: Any] {
        let sem = DispatchSemaphore(value: 0)
        mutex.lock(); pending[id] = sem; mutex.unlock()
        var message: [String: Any] = ["method":method, "id":id]
        if let params = params { message["params"] = params }
        try send(message)
        guard sem.wait(timeout: .now() + 18) == .success else { throw WatchError.problem("Codex app-server не ответил (таймаут)") }
        mutex.lock(); let reply = replies.removeValue(forKey: id); pending.removeValue(forKey: id); mutex.unlock()
        guard let response = reply else { throw WatchError.problem("Пустой ответ app-server") }
        if let err = response["error"] { throw WatchError.problem("Codex error: \(err)") }
        guard let result = response["result"] as? [String: Any] else { throw WatchError.problem("Нет result в ответе Codex") }
        return result
    }
    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForReading.close()
    }
    deinit { if process.isRunning { process.terminate() } }
}

func snapshot(from result: [String: Any]) throws -> Snapshot {
    var buckets = result["rateLimitsByLimitId"] as? [String: [String: Any]] ?? [:]
    if buckets.isEmpty, let legacy = result["rateLimits"] as? [String: Any] {
        buckets[legacy["limitId"] as? String ?? "codex"] = legacy
    }
    var windows: [String: Window] = [:]
    for (bucketId, bucket) in buckets {
        for kind in ["primary", "secondary"] {
            guard let raw = bucket[kind] as? [String: Any], let percent = raw["usedPercent"] as? Double,
                  let duration = raw["windowDurationMins"] as? Int else { continue }
            let reset = (raw["resetsAt"] as? NSNumber)?.doubleValue
            windows["\(bucketId):\(kind):\(duration)"] = Window(usedPercent: percent, windowDurationMins: duration, resetsAt: reset)
        }
    }
    guard !windows.isEmpty else { throw WatchError.problem("Codex не вернул окна лимитов. Проверь авторизацию: codex login status") }
    return Snapshot(windows: windows, accountId: result["accountId"] as? String, ordinaryUsageAllowed: result["ordinaryUsageAllowed"] as? Bool)
}
func label(_ key: String, _ w: Window) -> String {
    let bucket = key.components(separatedBy: ":").first ?? "codex"
    let mins = w.windowDurationMins
    let interval: String = mins == 300 ? "5 ч" : mins == 10080 ? "7 дней" : mins % 1440 == 0 ? "\(mins / 1440) дней" : mins % 60 == 0 ? "\(mins / 60) ч" : "\(mins) мин"
    return "\(bucket) · \(interval)"
}
func percent(_ x: Double) -> String { String(format: "%.0f", max(0, min(100, x))) }

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
let notificationDelegate = NotificationDelegate()
func notify(title: String, body: String) {
    let center = UNUserNotificationCenter.current()
    center.delegate = notificationDelegate
    let authSem = DispatchSemaphore(value: 0)
    var authorized = false
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        authorized = granted
        if let error = error { log("Notification permission error: \(error)") }
        authSem.signal()
    }
    _ = authSem.wait(timeout: .now() + 12)
    guard authorized else { log("Уведомления запрещены. Разреши их в System Settings → Notifications → CLW."); return }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let sem = DispatchSemaphore(value: 0)
    center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
        if let error = error { log("Notification error: \(error)") }
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 8)
    // Allow macOS notification delivery service a moment before process exits.
    Thread.sleep(forTimeInterval: 1.0)
}

// Local private token storage avoids Keychain prompts on every ad-hoc signed update.
// macOS file permissions: storage directory 0700 and token 0600.
private let localTokenFile = storage.appendingPathComponent("telegram-token.txt")
func telegramToken() -> String? {
    return try? String(contentsOf: localTokenFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
}
func saveTelegramToken(_ token: String) throws {
    try fm.createDirectory(at: storage, withIntermediateDirectories: true)
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: storage.path)
    if token.isEmpty { try? fm.removeItem(at: localTokenFile); return }
    try token.write(to: localTokenFile, atomically: true, encoding: .utf8)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: localTokenFile.path)
}
let notificationInbox = storage.appendingPathComponent("notification-inbox", isDirectory: true)
func enqueueMacNotification(_ message: String) {
    do {
        try fm.createDirectory(at: notificationInbox, withIntermediateDirectories: true)
        // Atomic creation + unique filename prevents partial reads and lost messages.
        let file = notificationInbox.appendingPathComponent(UUID().uuidString + ".txt")
        try message.write(to: file, atomically: true, encoding: .utf8)
        log("Queued notification for CLW GUI")
    } catch { log("Cannot queue macOS notification: \(error)") }
}
func deliver(_ message: String) {
    if CommandLine.arguments.contains("--check") && !fm.fileExists(atPath:storage.appendingPathComponent("monitoring-enabled").path) { return }
    let channel = ((try? String(contentsOf:channelFile,encoding:.utf8)) ?? "macos").trimmingCharacters(in:.whitespacesAndNewlines)
    if channel != "telegram" { enqueueMacNotification(message); return }
    guard let token=telegramToken(), !token.isEmpty,
          let chat=(try? String(contentsOf:chatFile,encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines), !chat.isEmpty else {
        log("Telegram: не настроены bot token или chat ID"); return
    }
    guard let url = URL(string:"https://api.telegram.org/bot\(token)/sendMessage") else { log("Telegram: неверный token"); return }
    var req = URLRequest(url:url)
    req.httpMethod = "POST"
    req.setValue("application/json",forHTTPHeaderField:"Content-Type")
    req.timeoutInterval = 12
    req.httpBody = try? JSONSerialization.data(withJSONObject:["chat_id":chat,"text":message])
    let sem=DispatchSemaphore(value:0)
    var errText:String? = nil
    URLSession.shared.dataTask(with:req) { data,response,error in
        if let e=error { errText = e.localizedDescription }
        else if let http=response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            errText = "HTTP \(http.statusCode): " + String((String(data:data ?? Data(),encoding:.utf8) ?? "").prefix(200))
        }
        sem.signal()
    }.resume()
    if sem.wait(timeout:.now()+15) != .success { log("Telegram timeout") }
    else if let error=errText { log("Telegram delivery error: \(error)") }
    else { log("Telegram sent") }
}
func run() throws {
    try fm.createDirectory(at: storage, withIntermediateDirectories: true)
    let args = Set(CommandLine.arguments.dropFirst())
    if args.contains("--test-notification") {
        deliver("\(selectedWindow() == "week" ? "7-day limit" : "5-hour limit"): test")
        log("Test notification requested")
        return
    }
    guard let codex = executable() else {
        throw WatchError.problem("Codex CLI was not found automatically. Ensure Codex CLI is installed and signed in.")
    }
    let rpc = try RPC(path: codex)
    defer { rpc.stop() }
    _ = try rpc.call("initialize", id: 1, params: ["clientInfo": ["name":"codex_limit_watch", "title":"CLW", "version":"1.0.0"], "capabilities": ["experimentalApi": true]])
    try rpc.notify("initialized")
    let info = try rpc.call("account/read", id: 2, params: ["refreshToken": false])
    guard let account = info["account"] as? [String: Any], !account.isEmpty else {
        throw WatchError.problem("В Codex CLI нет авторизации ChatGPT. Выполни: codex login. API ключ для ChatGPT лимитов не нужен.")
    }
    let result = try rpc.call("account/rateLimits/read", id: 3)
    let current = try snapshot(from: result)
    let mode = ((try? String(contentsOf: modeFile, encoding: .utf8)) ?? "test").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard mode == "test" || mode == "prod" else { throw WatchError.problem("Неверный mode.txt: используй test или prod") }
    let limitWindow = selectedWindow()
    let threshold = prodThreshold()
    let comparison = prodComparison()
    let targetDuration = limitWindow == "week" ? 10080 : 300
    let selected = current.windows.filter { $0.value.windowDurationMins == targetDuration }
    let windowName = limitWindow == "week" ? "7-day limit" : "5-hour limit"
    let selectedRows = selected.sorted { $0.key < $1.key }.map { (_, window) in
        "\(windowName): \(percent(100 - window.usedPercent))%"
    }
    let old = (try? Data(contentsOf: stateFile)).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
    let previousMode = (try? String(contentsOf: storage.appendingPathComponent("last-mode.txt"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    let previousWindow = (try? String(contentsOf: storage.appendingPathComponent("last-window.txt"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    let previousThreshold = (try? String(contentsOf: storage.appendingPathComponent("last-threshold.txt"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    let previousComparison = (try? String(contentsOf: storage.appendingPathComponent("last-comparison.txt"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    let configurationChanged = previousMode != "prod" || previousWindow != limitWindow || previousThreshold != String(Int(threshold)) || previousComparison != comparison
    let qualifying = selected.filter { key, window in
        let remaining = 100 - window.usedPercent
        let matches = comparison == "lte" ? remaining <= threshold : remaining >= threshold
        guard matches, current.ordinaryUsageAllowed != false else { return false }
        guard let prior = old?.snapshot.windows[key],
              old?.snapshot.accountId == nil || current.accountId == nil || old?.snapshot.accountId == current.accountId
        else { return true }
        let previousRemaining = 100 - prior.usedPercent
        let crossed = comparison == "lte" ? previousRemaining > threshold : previousRemaining < threshold
        return crossed || configurationChanged
    }
    if args.contains("--status") {
        // Manual inspection must not generate notifications or change alert state.
        print(localized("Режим: \(mode), интервал: \(intervalMinutes()) мин.", "Mode: \(mode), interval: \(intervalMinutes()) min."))
        for (key,w) in current.windows.sorted(by: {$0.key < $1.key}) {
            print("\(label(key,w)): \(localized("доступно", "remaining")) \(percent(100-w.usedPercent))%, reset \(w.resetsAt.map { Date(timeIntervalSince1970: $0).description } ?? "unknown")")
        }
        return
    }
    if args.contains("--check") && !fm.fileExists(atPath:storage.appendingPathComponent("monitoring-enabled").path) { return }
    let encoded = try JSONEncoder().encode(Saved(snapshot: current, lastChecked: Date()))
    try encoded.write(to: stateFile, options: .atomic)
    try mode.write(to: storage.appendingPathComponent("last-mode.txt"), atomically: true, encoding: .utf8)
    try limitWindow.write(to: storage.appendingPathComponent("last-window.txt"), atomically: true, encoding: .utf8)
    try String(Int(threshold)).write(to: storage.appendingPathComponent("last-threshold.txt"), atomically: true, encoding: .utf8)
    try comparison.write(to: storage.appendingPathComponent("last-comparison.txt"), atomically: true, encoding: .utf8)
    if selected.isEmpty {
        log("WARNING: \(windowName) unavailable in Codex response")
        deliver("CLW error: selected Codex limit is unavailable.")
    } else if mode == "test" {
        deliver(selectedRows.joined(separator: "\n"))
        log("TEST: \(selectedRows.joined(separator: "; "))")
    } else if !qualifying.isEmpty {
        let messages = qualifying.sorted { $0.key < $1.key }.map { _, window in
            "\(windowName): \(percent(100-window.usedPercent))%"
        }
        deliver(messages.joined(separator: "\n"))
        log("PROD ALERT (\(comparison == "lte" ? "≤" : "≥")\(threshold)%): \(messages.joined(separator: "; "))")
    } else {
        log("PROD: no threshold crossing; \(selectedRows.joined(separator: "; "))")
    }
}
if CommandLine.arguments.count == 1 {
    runGUI()
} else {
    // Headless worker: never initialize NSApplication, which can briefly create a Dock tile.
    do { try run() } catch {
        log("ERROR: \(error)")
        let args=Set(CommandLine.arguments)
        if args.contains("--check") && fm.fileExists(atPath:storage.appendingPathComponent("monitoring-enabled").path) {
            deliver("CLW error: Codex check failed. Open CLW to fix the connection.")
        }
        if args.contains("--status") { fputs("Error: \(error)\n", stderr) }
        exit(1)
    }
}
