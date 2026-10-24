import Foundation
import AppKit
import UserNotifications

final class SettingsWindow: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var notificationPoller: Timer?
    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error = error { log("Notification authorization error: \(error)") }
                    DispatchQueue.main.async {
                        self.status.stringValue = granted ? "Notifications enabled" : "Notifications disabled. Enable CLW in System Settings → Notifications."
                    }
                }
            } else if settings.authorizationStatus == .denied {
                DispatchQueue.main.async { self.status.stringValue = "Notifications disabled. Enable CLW in System Settings → Notifications." }
            }
        }
    }
    private func drainMacNotifications() {
        let folder = notificationInbox
        guard let paths = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for path in paths.filter({ $0.pathExtension == "txt" }).sorted(by: {$0.lastPathComponent < $1.lastPathComponent}) {
            guard let message = try? String(contentsOf: path, encoding: .utf8) else { continue }
            try? fm.removeItem(at: path)
            if fm.fileExists(atPath: storage.appendingPathComponent("monitoring-enabled").path) {
                sendNativeNotification(message)
            }
        }
    }
    private func sendNativeNotification(_ message: String) {
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                DispatchQueue.main.async { self.status.stringValue = "Notifications not allowed. Enable CLW in System Settings → Notifications." }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "CLW"
            content.body = message
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
                DispatchQueue.main.async {
                    self.status.stringValue = error.map { "Notification error: \($0.localizedDescription)" } ?? "Notification submitted to macOS"
                }
            }
        }
    }
    private let mode = NSSegmentedControl(labels:["TEST", "PROD"], trackingMode:.selectOne, target:nil, action:nil)
    private let interval = NSPopUpButton(frame:.zero, pullsDown:false)
    private let limitWindow = NSSegmentedControl(labels:["5-hour", "Week"], trackingMode:.selectOne, target:nil, action:nil)
    private let comparison = NSSegmentedControl(labels:["≥", "≤"], trackingMode:.selectOne, target:nil, action:nil)
    private let comparisonLabel = NSTextField(labelWithString:"Condition")
    private let threshold = NSSlider(value:98, minValue:5, maxValue:100, target:nil, action:nil)
    private let thresholdValue = NSTextField(labelWithString:"98%")
    private let windowLabel = NSTextField(labelWithString:"Limit window")
    private let thresholdLabel = NSTextField(labelWithString:"PROD threshold")
    private var thresholdCol: NSStackView!
    private let channel = NSSegmentedControl(labels:["", ""], trackingMode:.selectOne, target:nil, action:nil)
    private let token = NSSecureTextField(frame:.zero)
    private let visibleToken = NSTextField(frame:.zero)
    private let showToken = NSButton(frame:.zero)
    private var tokenShown = false
    private var lastSavedToken = ""
    private let chat = NSTextField(frame:.zero)
    private let titleLabel = NSTextField(labelWithString:"Codex Limit Watch")
    private let subtitle = NSTextField(labelWithString:"")
    private let modeLabel = NSTextField(labelWithString:"")
    private let intervalLabel = NSTextField(labelWithString:"")
    private let channelLabel = NSTextField(labelWithString:"")
    private let tokenLabel = NSTextField(labelWithString:"")
    private let chatLabel = NSTextField(labelWithString:"Chat ID")
    private let tokenHelp = NSButton(title:"?", target:nil, action:nil)
    private let chatHelp = NSButton(title:"?", target:nil, action:nil)
    private let findChat = NSButton(title:"Find Chat ID", target:nil, action:nil)
    private let hint = NSTextField(wrappingLabelWithString:"")
    private let status = NSTextField(wrappingLabelWithString:"")
    private let codexPathInput = NSTextField(frame:.zero)
    private let codexPathHelp = NSTextField(wrappingLabelWithString:"Paste the full path to the codex executable (not Codex.app). Example: /opt/homebrew/bin/codex. In Terminal run `command -v codex` to find its path, then paste it here.")
    private let retryCodex = NSButton(title:"Save path & retry", target:nil, action:nil)
    private var codexPathSection: NSStackView!

    private let test = NSButton(title:"",target:nil,action:nil)
    private let inspect = NSButton(title:"",target:nil,action:nil)
    private var stack:NSStackView!
    private func t(_ ru:String,_ en:String)->String { en }

    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.regular)
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:550,height:650),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title="CLW"
        window.center(); window.isReleasedWhenClosed=false
        if let image=NSImage(named:"AppIcon") { NSApp.applicationIconImage=image }
        let root=NSView(frame:NSRect(x:0,y:0,width:550,height:650)); window.contentView=root
        stack=NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing=10
        stack.translatesAutoresizingMaskIntoConstraints=false
        root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:26),stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-26),stack.topAnchor.constraint(equalTo:root.topAnchor,constant:18),stack.bottomAnchor.constraint(lessThanOrEqualTo:root.bottomAnchor,constant:-18)])
        titleLabel.font = .boldSystemFont(ofSize:24); stack.addArrangedSubview(titleLabel)
        subtitle.textColor = .secondaryLabelColor; stack.addArrangedSubview(subtitle)
        let top=NSStackView();top.orientation = .horizontal;top.distribution = .fillEqually;top.spacing=15
        let modeCol=makeColumn(modeLabel,mode)
        let windowCol=makeColumn(windowLabel,limitWindow)
        top.addArrangedSubview(modeCol);top.addArrangedSubview(windowCol)
        stack.addArrangedSubview(top);top.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        comparison.selectedSegment=0
        comparison.setToolTip("Remaining quota is greater than or equal to the PROD threshold", forSegment:0)
        comparison.setToolTip("Remaining quota is less than or equal to the PROD threshold", forSegment:1)
        let comparisonCol=makeColumn(comparisonLabel,comparison)
        stack.addArrangedSubview(comparisonCol)
        mode.selectedSegment=0
        mode.setToolTip("TEST: notify after every successful poll for the selected limit window.", forSegment: 0)
        mode.setToolTip("PROD: notify on crossing the selected threshold using ≥ or ≤.", forSegment: 1)
        limitWindow.setToolTip("Monitor the 5-hour quota", forSegment:0)
        limitWindow.setToolTip("Monitor the 7-day quota (default)", forSegment:1)
        limitWindow.selectedSegment = 1
        let pollingRow = NSStackView();pollingRow.orientation = .horizontal;pollingRow.distribution = .fillEqually;pollingRow.spacing = 15
        let intervalCol = makeColumn(intervalLabel, interval)
        thresholdCol = NSStackView(); thresholdCol.orientation = .vertical;thresholdCol.alignment = .leading; thresholdCol.spacing = 5
        thresholdCol.addArrangedSubview(thresholdLabel)
        let sliderRow = NSStackView();sliderRow.orientation = .horizontal;sliderRow.spacing = 8
        sliderRow.addArrangedSubview(threshold);sliderRow.addArrangedSubview(thresholdValue)
        threshold.widthAnchor.constraint(equalToConstant:175).isActive = true
        thresholdValue.widthAnchor.constraint(equalToConstant:45).isActive = true
        thresholdCol.addArrangedSubview(sliderRow)
        pollingRow.addArrangedSubview(intervalCol); pollingRow.addArrangedSubview(thresholdCol)
        stack.addArrangedSubview(pollingRow);pollingRow.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        threshold.isContinuous = true
        threshold.numberOfTickMarks = 0
        interval.addItems(withTitles:["1", "3", "5", "7", "10", "15", "30", "60"])
        channelLabel.font = .boldSystemFont(ofSize:13);stack.addArrangedSubview(channelLabel)
        channel.setLabel("", forSegment:0)
        channel.setLabel("", forSegment:1)
        channel.setImage(NSImage(systemSymbolName:"apple.logo", accessibilityDescription:"macOS") ?? NSImage(systemSymbolName:"desktopcomputer", accessibilityDescription:"macOS"), forSegment:0)
        channel.setImage(NSImage(systemSymbolName:"paperplane.fill", accessibilityDescription:"Telegram"), forSegment:1)
        channel.setWidth(235, forSegment:0)
        channel.setWidth(235, forSegment:1)
        channel.setAccessibilityLabel("Notification destination")
        channel.setToolTip("Native macOS notifications",forSegment:0)
        channel.setToolTip("Telegram bot messages",forSegment:1)
        channel.target=self;channel.action=#selector(channelChangedAndSave)
        stack.addArrangedSubview(channel);channel.widthAnchor.constraint(equalToConstant:480).isActive=true
        tokenLabel.font = .systemFont(ofSize:12);chatLabel.font = .systemFont(ofSize:12)
        let tokenRow=NSStackView();tokenRow.orientation = .horizontal;tokenRow.spacing=8
        tokenRow.addArrangedSubview(tokenLabel);tokenRow.addArrangedSubview(tokenHelp)
        tokenHelp.bezelStyle = .helpButton;tokenHelp.target=self;tokenHelp.action=#selector(showTokenHelp)
        stack.addArrangedSubview(tokenRow)
        let tokenInputRow = NSStackView()
        tokenInputRow.orientation = .horizontal
        tokenInputRow.alignment = .centerY
        tokenInputRow.spacing = 6
        tokenInputRow.addArrangedSubview(token)
        tokenInputRow.addArrangedSubview(visibleToken)
        token.widthAnchor.constraint(equalToConstant:442).isActive = true
        visibleToken.widthAnchor.constraint(equalToConstant:442).isActive = true
        visibleToken.isHidden = true
        showToken.bezelStyle = .texturedRounded
        showToken.image = NSImage(systemSymbolName:"eye", accessibilityDescription:"Show bot token")
        showToken.imagePosition = .imageOnly
        showToken.toolTip = "Show bot token"
        showToken.target = self
        showToken.action = #selector(toggleTokenVisibility)
        showToken.widthAnchor.constraint(equalToConstant:32).isActive = true
        tokenInputRow.addArrangedSubview(showToken)
        stack.addArrangedSubview(tokenInputRow)
        let chatRow=NSStackView();chatRow.orientation = .horizontal;chatRow.spacing=8
        chatRow.addArrangedSubview(chatLabel);chatRow.addArrangedSubview(chatHelp)
        chatHelp.bezelStyle = .helpButton;chatHelp.target=self;chatHelp.action=#selector(showChatHelp)
        stack.addArrangedSubview(chatRow);stack.addArrangedSubview(chat);chat.widthAnchor.constraint(equalToConstant:480).isActive=true
        findChat.target=self;findChat.action=#selector(findChatID)
        stack.addArrangedSubview(findChat)
        hint.font = .systemFont(ofSize:11);hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint);hint.widthAnchor.constraint(equalToConstant:480).isActive=true
        let actions=NSStackView();actions.orientation = .horizontal;actions.spacing=10
        test.target=self;test.action=#selector(testNow)
        inspect.target=self;inspect.action=#selector(checkNow)
        actions.addArrangedSubview(test);actions.addArrangedSubview(inspect)
        stack.addArrangedSubview(actions)
        status.font = .systemFont(ofSize:12);status.textColor = .secondaryLabelColor
        stack.addArrangedSubview(status);status.widthAnchor.constraint(equalToConstant:480).isActive=true
        codexPathSection=NSStackView()
        codexPathSection.orientation = .vertical
        codexPathSection.alignment = .leading
        codexPathSection.spacing = 6
        let pathTitle=NSTextField(labelWithString:"Codex executable path")
        pathTitle.font = .boldSystemFont(ofSize:12)
        codexPathSection.addArrangedSubview(pathTitle)
        codexPathInput.placeholderString="/opt/homebrew/bin/codex"
        codexPathInput.widthAnchor.constraint(equalToConstant:480).isActive=true
        codexPathSection.addArrangedSubview(codexPathInput)
        codexPathHelp.textColor = .secondaryLabelColor
        codexPathHelp.font = .systemFont(ofSize:11)
        codexPathHelp.widthAnchor.constraint(equalToConstant:480).isActive=true
        codexPathSection.addArrangedSubview(codexPathHelp)
        retryCodex.target=self
        retryCodex.action=#selector(savePathAndRetry)
        codexPathSection.addArrangedSubview(retryCodex)
        stack.addArrangedSubview(codexPathSection)
        codexPathSection.isHidden=true
        installMainMenu()
        loadSettings();refreshLanguage();channelChanged()
        mode.target=self; mode.action=#selector(settingChanged)
        limitWindow.target=self; limitWindow.action=#selector(settingChanged)
        comparison.target=self; comparison.action=#selector(settingChanged)
        threshold.target=self; threshold.action=#selector(thresholdChanged)
        interval.target=self; interval.action=#selector(settingChanged)
        token.target=self; token.action=#selector(credentialsChanged)
        visibleToken.target=self; visibleToken.action=#selector(credentialsChanged)
        chat.target=self; chat.action=#selector(credentialsChanged)
        for field in [token, visibleToken, chat] {
            NotificationCenter.default.addObserver(self, selector:#selector(credentialsEdited(_:)), name:NSControl.textDidChangeNotification, object:field)
        }
        try? fm.removeItem(at:storage.appendingPathComponent("agent-interval.txt"))
        _ = saveSettings()
        resizeWindow()
        window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        requestNotificationPermission()
        drainMacNotifications()
        notificationPoller = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.drainMacNotifications()
        }
    }
    // AppKit requires an Edit menu for standard ⌘C / ⌘V / ⌘A shortcuts.
    private func installMainMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title:"CLW")
        appMenu.addItem(withTitle:"Quit CLW", action:#selector(NSApplication.terminate(_:)), keyEquivalent:"q")
        appItem.submenu = appMenu
        bar.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title:"Edit")
        editMenu.addItem(withTitle:"Undo", action:Selector(("undo:")), keyEquivalent:"z")
        editMenu.addItem(withTitle:"Redo", action:Selector(("redo:")), keyEquivalent:"Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle:"Cut", action:#selector(NSText.cut(_:)), keyEquivalent:"x")
        editMenu.addItem(withTitle:"Copy", action:#selector(NSText.copy(_:)), keyEquivalent:"c")
        editMenu.addItem(withTitle:"Paste", action:#selector(NSText.paste(_:)), keyEquivalent:"v")
        editMenu.addItem(withTitle:"Select All", action:#selector(NSText.selectAll(_:)), keyEquivalent:"a")
        editItem.submenu = editMenu
        bar.addItem(editItem)
        NSApp.mainMenu = bar
    }
    private func makeColumn(_ label:NSTextField,_ control:NSView)->NSStackView {
        let container=NSStackView();container.orientation = .vertical;container.alignment = .leading;container.spacing=5
        container.addArrangedSubview(label);container.addArrangedSubview(control)
        control.widthAnchor.constraint(equalToConstant:230).isActive=true
        return container
    }
    private func loadSettings() {
        let currentMode=(try? String(contentsOf:modeFile,encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "test"
        mode.selectedSegment=currentMode == "prod" ? 1 : 0
        limitWindow.selectedSegment=selectedWindow() == "week" ? 1 : 0
        comparison.selectedSegment=prodComparison() == "lte" ? 1 : 0
        threshold.doubleValue=prodThreshold()
        thresholdValue.stringValue="\(Int(threshold.doubleValue))%"
        thresholdCol.isHidden = mode.selectedSegment != 1
        let choices=[1,3,5,7,10,15,30,60]
        let n=intervalMinutes()
        if let index=choices.firstIndex(of:n) {interval.selectItem(at:index)} else {interval.addItem(withTitle:String(n));interval.selectItem(at:8)}
        let dest=(try? String(contentsOf:channelFile,encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "macos"
        channel.selectedSegment=dest == "telegram" ? 1 : 0
        chat.stringValue=(try? String(contentsOf:chatFile,encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
        token.stringValue=telegramToken() ?? ""
        lastSavedToken=token.stringValue
        visibleToken.stringValue=token.stringValue
        codexPathInput.stringValue=(try? String(contentsOf:storage.appendingPathComponent("codex-path.txt"),encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
    }
    private func refreshLanguage() {
        subtitle.stringValue=t("Проверка лимитов в фоне через launchd","Background limit checks via launchd")
        modeLabel.stringValue=t("Режим", "Mode")
        intervalLabel.stringValue="Polling interval (min)"
        windowLabel.stringValue="Limit window"
        comparisonLabel.stringValue="Notify when remaining quota is"
        thresholdLabel.stringValue="PROD threshold"
        channelLabel.stringValue=t("Куда отправлять уведомления", "Notification destination")
        tokenLabel.stringValue=t("Токен бота (от @BotFather)", "Bot token (from @BotFather)")
        hint.stringValue="Token is saved in macOS Keychain. Send /start to your bot, then click Find Chat ID."
        token.placeholderString="123456:ABC..."
        visibleToken.placeholderString="123456:ABC..."
        chat.placeholderString=t("Например, 123456789", "For example, 123456789")
        test.title=t("Отправить тест", "Send test")
        inspect.title=t("Проверить лимиты", "Check limits")
        status.stringValue="Settings save automatically."
    }
    private func currentToken() -> String { tokenShown ? visibleToken.stringValue : token.stringValue }
    @objc private func toggleTokenVisibility() {
        if tokenShown {
            token.stringValue = visibleToken.stringValue
        } else {
            visibleToken.stringValue = token.stringValue
        }
        tokenShown.toggle()
        token.isHidden = tokenShown
        visibleToken.isHidden = !tokenShown
        showToken.image = NSImage(systemSymbolName: tokenShown ? "eye.slash" : "eye", accessibilityDescription: tokenShown ? "Hide bot token" : "Show bot token")
        showToken.toolTip = tokenShown ? "Hide bot token" : "Show bot token"
    }
    @objc private func channelChanged() {
        let show=channel.selectedSegment == 1
        for v in [chat,tokenLabel,chatLabel,tokenHelp,chatHelp,findChat,hint,showToken] {v.isHidden = !show}
        token.isHidden = !show || tokenShown
        visibleToken.isHidden = !show || !tokenShown
        tokenLabel.superview?.isHidden = !show
        token.superview?.isHidden = !show
        chatLabel.superview?.isHidden = !show
        resizeWindow()
    }
    @objc private func channelChangedAndSave() {
        channelChanged()
        saveSettings()
    }
    @objc private func settingChanged() {
        thresholdCol.isHidden = mode.selectedSegment != 1
        resizeWindow()
        saveSettings()
    }
    @objc private func thresholdChanged() {
        threshold.doubleValue = Double(Int(threshold.doubleValue.rounded()))
        thresholdValue.stringValue="\(Int(threshold.doubleValue))%"
        saveSettings()
    }
    @objc private func credentialsEdited(_ note: Notification) { scheduleCredentialsSave() }
    @objc private func credentialsChanged() { scheduleCredentialsSave() }
    private var pendingCredentialSave: DispatchWorkItem?
    private func scheduleCredentialsSave() {
        pendingCredentialSave?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self=self else { return }
            let current=self.currentToken().trimmingCharacters(in:.whitespacesAndNewlines)
            let cid=self.chat.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
            if !current.isEmpty && !cid.isEmpty {
                self.channel.selectedSegment=1
                self.channelChanged()
            }
            self.saveSettings()
        }
        pendingCredentialSave=task
        DispatchQueue.main.asyncAfter(deadline:.now()+0.6,execute:task)
    }
    private func help(_ title:String,_ body:String) {
        let alert=NSAlert();alert.messageText=title;alert.informativeText=body;alert.addButton(withTitle:"OK")
        alert.runModal()
    }
    @objc private func showTokenHelp() {
        help("How to get a Telegram bot token", "1. Open Telegram and find the verified @BotFather bot.\n2. Send /newbot.\n3. Follow the prompts to choose a name and username.\n4. Copy the HTTP API token (123456789:ABC...) into Bot Token.\n\nThe digits before ':' identify the BOT, not your chat. Keep the full token secret.")
    }
    @objc private func showChatHelp() {
        help("How to get your Chat ID", "1. Open YOUR new bot in Telegram and send /start.\n2. Enter its token in CLW.\n3. Click Find Chat ID.\n\nManual alternative: open https://api.telegram.org/bot<TOKEN>/getUpdates in your browser (replace <TOKEN> with your full token). Find result → message → chat → id. Copy that id into Chat ID.\n\nDo not share this URL: it contains your secret bot token. If the bot has multiple chats, select the correct chat ID manually.")
    }
    @objc private func findChatID() {
        let entered=currentToken().trimmingCharacters(in:.whitespacesAndNewlines)
        guard !entered.isEmpty, entered.contains(":"), let safe=entered.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed), let url=URL(string:"https://api.telegram.org/bot\(safe)/getUpdates") else {
            status.stringValue="Enter a valid Bot Token first.";return
        }
        findChat.isEnabled=false;status.stringValue="Searching recent bot messages…"
        var request=URLRequest(url:url);request.timeoutInterval=15
        URLSession.shared.dataTask(with:request) { data,response,error in
            var message="Could not read Telegram updates. Check the token and network."
            var resultID:String?=nil
            if error == nil,let data=data,
               let json=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
               let ok=json["ok"] as? Bool,ok,
               let items=json["result"] as? [[String:Any]] {
                var ids=Set<String>()
                for item in items {
                    for kind in ["message","edited_message","channel_post","edited_channel_post","my_chat_member"] {
                        if let obj=item[kind] as? [String:Any],let chat=obj["chat"] as? [String:Any], let id=chat["id"] as? NSNumber {ids.insert(id.stringValue)}
                    }
                }
                if ids.count == 1 { resultID=ids.first;message="Chat ID found. Telegram settings saved automatically." }
                else if ids.isEmpty {message="No chats found. Send /start to your bot in Telegram, then retry."}
                else {message="Multiple chats found (\(ids.sorted().joined(separator:", "))). Enter your Chat ID manually."}
            }
            let chosen=resultID
            DispatchQueue.main.async {
                self.findChat.isEnabled=true
                if let id=chosen {self.chat.stringValue=id; self.scheduleCredentialsSave()}
                self.status.stringValue=message
            }
        }.resume()
    }
    @discardableResult private func saveSettings() -> Bool {
        let selectedMode=mode.selectedSegment == 1 ? "prod" : "test"
        let minutes=Int(interval.titleOfSelectedItem ?? "7") ?? 7
        let requestedTelegram=channel.selectedSegment == 1
        let current=currentToken().trimmingCharacters(in:.whitespacesAndNewlines)
        let cid=chat.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        let credentialsReady = !current.isEmpty && !cid.isEmpty
        let destination = requestedTelegram && credentialsReady ? "telegram" : "macos"
        do {
            try fm.createDirectory(at:storage,withIntermediateDirectories:true)
            try selectedMode.write(to:modeFile,atomically:true,encoding:.utf8)
            try String(minutes).write(to:intervalFile,atomically:true,encoding:.utf8)
            try (limitWindow.selectedSegment == 0 ? "5hour" : "week").write(to:windowFile,atomically:true,encoding:.utf8)
            try String(Int(threshold.doubleValue)).write(to:thresholdFile,atomically:true,encoding:.utf8)
            try (comparison.selectedSegment == 1 ? "lte" : "gte").write(to:comparisonFile,atomically:true,encoding:.utf8)
            try destination.write(to:channelFile,atomically:true,encoding:.utf8)
            try chat.stringValue.write(to:chatFile,atomically:true,encoding:.utf8)
            try "en".write(to:languageFile,atomically:true,encoding:.utf8)
            try "enabled".write(to:storage.appendingPathComponent("monitoring-enabled"),atomically:true,encoding:.utf8)
            if current != lastSavedToken {
                try saveTelegramToken(current)
                lastSavedToken=current
            }
            let existingInterval=(try? String(contentsOf:storage.appendingPathComponent("agent-interval.txt"),encoding:.utf8))?.trimmingCharacters(in:.whitespacesAndNewlines)
            if existingInterval != String(minutes) {
                try installAgent(interval:minutes)
                try String(minutes).write(to:storage.appendingPathComponent("agent-interval.txt"),atomically:true,encoding:.utf8)
            }
            status.stringValue = requestedTelegram && !credentialsReady
                ? "Enter Bot Token and Chat ID to enable Telegram. macOS is active until then."
                : "✓ Saved automatically · \(minutes) min · \(selectedMode.uppercased()) · \(limitWindow.selectedSegment == 0 ? "5-hour" : "Week") · \(comparison.selectedSegment == 1 ? "≤" : "≥") \(Int(threshold.doubleValue))% · \(destination == "telegram" ? "Telegram" : "macOS")"
            return true
        } catch {status.stringValue="Error: "+String(describing:error);return false}
    }
    private func installAgent(interval:Int) throws {
        let exe=Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CLWWorker").path
        guard fm.isExecutableFile(atPath:exe) else { throw WatchError.problem("Background worker not installed") }
        let agent=home.appendingPathComponent("Library/LaunchAgents/dev.local.codex-limit-watch.plist")
        try fm.createDirectory(at:agent.deletingLastPathComponent(),withIntermediateDirectories:true)
        let previous=(NSDictionary(contentsOf:agent) as? [String:Any]) ?? [:]
        var env=(previous["EnvironmentVariables"] as? [String:String]) ?? [:]
        env["PATH"]="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(home.path)/.local/bin:\(home.path)/.bun/bin"
        let plist:[String:Any]=["Label":"dev.local.codex-limit-watch","ProgramArguments":[exe,"--check"],"StartInterval":interval*60,"RunAtLoad":true,"ProcessType":"Background","EnvironmentVariables":env]
        let data=try PropertyListSerialization.data(fromPropertyList:plist,format:.xml,options:0)
        try data.write(to:agent,options:.atomic)
        let domain="gui/\(getuid())"
        func launch(_ args:[String]) {
            let p=Process();p.executableURL=URL(fileURLWithPath:"/bin/launchctl");p.arguments=args
            p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.nullDevice
            try? p.run();p.waitUntilExit()
        }
        launch(["bootout",domain,agent.path]);launch(["bootstrap",domain,agent.path])
    }
    private func spawn(_ args:[String], finished:@escaping(String)->Void) {
        let exe=Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CLWWorker").path
        guard fm.isExecutableFile(atPath:exe) else {
            finished("Background worker not installed. Re-run Install.command.")
            return
        }
        DispatchQueue.global(qos:.userInitiated).async {
            let p=Process();p.executableURL=URL(fileURLWithPath:exe);p.arguments=args
            let pipe=Pipe();p.standardOutput=pipe;p.standardError=pipe
            do {try p.run();let data=pipe.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit()
                let msg=String(data:data,encoding:.utf8) ?? ""
                DispatchQueue.main.async {finished(msg)}
            } catch {DispatchQueue.main.async {finished(String(describing:error))}}
        }
    }
    @objc private func testNow() {
        // Save the currently selected channel and credentials before testing it.
        // Never fall back to macOS if Telegram is selected but incomplete.
        pendingCredentialSave?.cancel()
        guard saveSettings() else { return }
        if channel.selectedSegment == 1 && ((try? String(contentsOf:channelFile,encoding:.utf8)) ?? "") != "telegram" {
            status.stringValue="Enter Bot Token and Chat ID before testing Telegram.";return
        }
        status.stringValue="Sending test via " + (channel.selectedSegment == 1 ? "Telegram…" : "macOS…")
        if channel.selectedSegment == 0 {
            sendNativeNotification("\(selectedWindow() == "week" ? "7-day limit" : "5-hour limit"): test")
        } else {
            spawn(["--test-notification"]) { output in
                self.status.stringValue="Telegram test attempted. " + String(output.suffix(170))
            }
        }
    }
    @objc private func checkNow() {
        status.stringValue="Reading Codex limits…"
        spawn(["--status"]) { output in
            self.status.stringValue=String(output.suffix(350))
            let missingExecutable=output.localizedCaseInsensitiveContains("Codex CLI was not found") || output.localizedCaseInsensitiveContains("Не найден исполняемый codex") || output.localizedCaseInsensitiveContains("Codex executable not found")
            if missingExecutable {
                self.codexPathSection.isHidden=false
                self.window.makeFirstResponder(self.codexPathInput)
            } else if !output.localizedCaseInsensitiveContains("Error:") && !output.localizedCaseInsensitiveContains("ERROR:") {
                self.codexPathSection.isHidden=true
            }
            self.resizeWindow()
        }
    }
    @objc private func savePathAndRetry() {
        let value=codexPathInput.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.isEmpty else {status.stringValue="Paste the executable path first.";return}
        guard fm.isExecutableFile(atPath:value) else {
            status.stringValue="No executable found at that path. Run `command -v codex` in Terminal and paste the result."
            return
        }
        do {
            try fm.createDirectory(at:storage,withIntermediateDirectories:true)
            try value.write(to:storage.appendingPathComponent("codex-path.txt"),atomically:true,encoding:.utf8)
            checkNow()
        } catch {status.stringValue="Could not save Codex path: \(error)"}
    }
    private func resizeWindow() {
        guard window != nil, stack != nil, let root = window.contentView else { return }
        // Measure the real Auto Layout content rather than guessing its height.
        // Defer until AppKit has processed changed/hidden arranged subviews.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.window != nil,
                  let content = self.window.contentView else { return }
            content.layoutSubtreeIfNeeded()
            self.stack.layoutSubtreeIfNeeded()
            let measured = self.stack.fittingSize.height
            guard measured.isFinite && measured > 0 else { return }
            let contentHeight = ceil(measured) + 36 // 18 pt top + bottom margins
            let current = self.window.frame
            let contentRect = NSRect(x: 0, y: 0, width: content.bounds.width, height: contentHeight)
            let requiredFrame = self.window.frameRect(forContentRect: contentRect)
            let targetHeight = requiredFrame.height
            guard abs(current.height - targetHeight) > 1 else { return }
            var frame = current
            frame.origin.y += current.height - targetHeight // keep top edge fixed
            frame.size.height = targetHeight
            self.window.setFrame(frame, display: true, animate: false)
        }
    }
    private func stopMonitoring() {
        let enabled=storage.appendingPathComponent("monitoring-enabled")
        try? fm.removeItem(at:enabled)
        let agent=home.appendingPathComponent("Library/LaunchAgents/dev.local.codex-limit-watch.plist")
        let p=Process();p.executableURL=URL(fileURLWithPath:"/bin/launchctl")
        p.arguments=["bootout","gui/\(getuid())",agent.path]
        p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.nullDevice
        try? p.run();p.waitUntilExit()
        try? fm.removeItem(at:agent)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
    func applicationWillTerminate(_ notification:Notification) {notificationPoller?.invalidate();stopMonitoring()}
}
private var guiDelegate:SettingsWindow?
func runGUI() {
    let app=NSApplication.shared
    let delegate=SettingsWindow();guiDelegate=delegate;app.delegate=delegate;app.run()
}
