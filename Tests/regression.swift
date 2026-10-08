// Compiled with main.swift (without its entry point). Uses an isolated config and synthetic PIDs.
let app = NSApplication.shared
let rgApp = SystemProcessesApp()
var checks = 0, failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { failures += 1; print("FAIL: \(message)"); fflush(stdout) }
}
let fixtureRAM = SysRAM(total: 24_000_000_000, appMem: 6_000_000_000, wired: 4_000_000_000,
                        compressed: 2_000_000_000, free: 12_000_000_000)
func fixture(_ n: Int, name: String? = nil, type: ProcessType = .background, protected: Bool = false) -> ProcInfo {
    var result = ProcInfo(pid: Int32(90_000+n), name: name ?? "Fixture \(n)", ramBytes: UInt64(5_000_000_000/n), cpuPct: 0,
             icon: nil, type: type, isProtected: protected, threads: 1,
             startTime: Date(timeIntervalSince1970: 100.000123), ppid: 1, childCount: 0)
#if !LEGACY
    result.executablePath = "/bin/sleep"; result.executableFileID = executableFileIdentity("/bin/sleep")
#endif
    return result
}
let fixtures = (1...50).map { fixture($0) }
func descendants(_ view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants($0) }
}

#if !LEGACY
func unitChecks() throws {
    config = AppConfig()
    check(applicationOwnerName(bundleIdentifier: nil, bundleURL: nil) == nil, "Registered CLI titles cannot become cloud owner labels")
    check(applicationOwnerName(bundleIdentifier: "cli.fixture", bundleURL: URL(fileURLWithPath: "/usr/local/bin/node")) == nil, "Non-app registrations have no trusted application owner label")
    check(applicationOwnerName(bundleIdentifier: "com.google.Chrome", bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")) == "Google Chrome", "Owner evidence uses a static app bundle basename")
    var registeredCLI = fixture(1, name: "node --api-key=DO_NOT_SEND /private/path", type: .user)
    registeredCLI.ownerName = applicationOwnerName(bundleIdentifier: nil, bundleURL: nil)
    let cliRequest = try AIManager.request(procs: [registeredCLI], ram: fixtureRAM, model: "gemma4:31b-cloud", baseURL: "http://localhost:11434")
    check(!String(data: cliRequest.httpBody!, encoding: .utf8)!.contains("DO_NOT_SEND") && !String(data: cliRequest.httpBody!, encoding: .utf8)!.contains("/private/path"), "Registered CLI user processes cannot leak argv through name or owner")
    let ledgerFixture = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("systemprocesses-ledger-"+UUID().uuidString)
    check(UsageLedger.load(at: ledgerFixture).automaticUsageAvailable, "A missing first-run ledger permits bounded automatic accounting")
    try Data("damaged ledger".utf8).write(to: ledgerFixture)
    let damagedLedger = UsageLedger.load(at: ledgerFixture)
    check(!damagedLedger.automaticUsageAvailable && !damagedLedger.save(), "A damaged ledger pauses automatic requests and cannot overwrite evidence")
    try JSONEncoder().encode(UsageLedger(automaticCount: 6)).write(to: ledgerFixture)
    check(UsageLedger.load(at: ledgerFixture).automaticCount == 6, "A valid ledger restores the daily automatic count")
    try FileManager.default.removeItem(at: ledgerFixture)
    try FileManager.default.createDirectory(at: ledgerFixture, withIntermediateDirectories: false)
    check(!UsageLedger.load(at: ledgerFixture).automaticUsageAvailable, "An unreadable ledger is not interpreted as a fresh quota")
    try FileManager.default.removeItem(at: ledgerFixture)
    check(MainVC.manualAppleNotice(provider: "apple", pressure: .elevated)?.contains("additional memory") == true, "Manual Apple analysis warns of memory impact during warning pressure")
    check(MainVC.manualAppleNotice(provider: "apple", pressure: .critical)?.contains("critical") == true, "Manual Apple analysis warns during critical pressure")
    check(MainVC.manualAppleNotice(provider: "ollama", pressure: .critical) == nil && MainVC.manualAppleNotice(provider: "apple", pressure: .healthy) == nil, "Memory impact notice is limited to manual Apple analysis under pressure")
    let old = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"displayMode":"percent","showNotifications":false,"aiEnabled":true}"#.utf8))
    check(old.aiEnabled && old.displayMode == "percent" && !old.alert80On && old.aiModel == "gemma4:31b-cloud", "partial config keeps preferences and defaults")
    let bad = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"refreshInterval":-2,"maxProcesses":-1,"aiModel":" ","showCPU":"bad","aiEnabled":true}"#.utf8))
    check(bad.refreshInterval == 2 && bad.maxProcesses == 50 && bad.aiModel == "gemma4:31b-cloud" && bad.aiEnabled, "malformed config values are bounded independently")
    let go = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"aiProvider":"opencodeGo","aiModel":""}"#.utf8))
    check(go.aiModel == "deepseek-v4.1-flash", "empty Go model gets the correct provider default")
    let unavailableMemory = SysRAM(total: 24_000_000_000, appMem: 0, wired: 0, compressed: 0, free: 0, availableCounters: false)
    check(unavailableMemory.used == 0 && unavailableMemory.pct == 0, "Unavailable counters cannot become 100 percent occupancy")
    check(!SystemProcessesApp.appleProviderReady(available: false) && SystemProcessesApp.appleProviderReady(available: true), "Unavailable Apple model cannot reserve automatic quota")
    check(SysRAM(total: 1, appMem: 0, wired: 0, compressed: 0, free: 2).used == 0, "RAM counters cannot underflow")
    check(DiskInfo(total: 1, free: 2).used == 0, "purgeable disk capacity cannot underflow")

    let rowGeometry = ProcessRow(y: 0, w: POP_W, proc: fixture(1), maxRAM: 5_000_000_000)
    check(rowGeometry.metadataRect.maxX <= rowGeometry.memoryBarRect.minX, "Long row metadata cannot overlap the memory bar")
    let titled = fixture(1, name: "node --api-key=DO_NOT_SEND /private/path")
    let privateRequest = try AIManager.request(procs: [titled], ram: fixtureRAM, model: "gemma4:31b-cloud", baseURL: "http://localhost:11434")
    let privateBody = String(data: privateRequest.httpBody!, encoding: .utf8)!
    check(!privateBody.contains("DO_NOT_SEND") && !privateBody.contains("/private/path") && privateBody.contains("sleep"), "Cloud name excludes argv-derived process titles and paths")
    var unknown = titled; unknown.executablePath = ""
    check(AIManager.analysisDisplayName(unknown) == "Unknown executable", "Missing executable metadata never falls back to an arbitrary process title")
    let req = try AIManager.request(procs: fixtures, ram: fixtureRAM, model: "gemma4:31b-cloud", baseURL: "http://localhost:11434")
    let cloud = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
    check(cloud["format"] == nil && cloud["think"] as? Bool == false && req.timeoutInterval == 30, "Ollama cloud uses compatible fast request")
    let local = try AIManager.request(procs: [], ram: fixtureRAM, model: "gemma3", baseURL: "http://127.0.0.1:11434")
    let localBody = try JSONSerialization.jsonObject(with: local.httpBody!) as! [String: Any]
    check(localBody["format"] as? String == "json", "local JSON mode remains available without loading a model")
    let direct = try AIManager.request(procs: fixtures, ram: fixtureRAM, model: "deepseek-v4.1-flash", baseURL: "ignored",
                                       provider: .opencodeGo, apiKey: "test-key", sessionID: "test-session")
    let directBody = try JSONSerialization.jsonObject(with: direct.httpBody!) as! [String: Any]
    check(direct.url?.absoluteString == "https://opencode.ai/zen/go/v1/chat/completions", "Go credentials only target the fixed HTTPS endpoint")
    check(direct.value(forHTTPHeaderField: "User-Agent") == "SystemProcesses/1.0" && direct.value(forHTTPHeaderField: "x-opencode-session") == "test-session", "Go uses honest identity and stable session header")
    check((directBody["thinking"] as? [String: String])?["type"] == "disabled" && directBody["max_tokens"] as? Int == 2048, "DeepSeek thinking and output size are bounded")
    check(req.value(forHTTPHeaderField: "Authorization") == nil, "Go key never enters an Ollama request")
    do { _ = try AIManager.request(procs: [], ram: fixtureRAM, model: "gemma3", baseURL: "http://example.com"); check(false, "remote plaintext rejected") }
    catch { check(true, "remote plaintext rejected") }
    do { _ = try AIManager.request(procs: [], ram: fixtureRAM, model: "gemma3", baseURL: "http://user:password@localhost"); check(false, "URL credentials rejected") }
    catch { check(true, "URL credentials rejected") }

    let raw = #"{"recommendations":[{"pid":90001,"verdict":"safe","reason":"r"}],"summary":"s"}"#
    func envelope(_ content: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["message": ["content": content], "done": true, "done_reason": "stop"])
    }
    let fenced = try AIManager.decode(data: envelope("```json\n"+raw+"\n```"), status: 200)
    check(fenced.recommendations.count == 1, "fenced cloud JSON is accepted")
    let goData = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": raw], "finish_reason": "stop"]]])
    let goResponse = try AIManager.decode(data: goData, status: 200, provider: .opencodeGo)
    check(goResponse.recommendations.count == 1, "Go chat-completions response is decoded")
    for badJSON in ["{", #"{"summary":"s"}"#, #"{"recommendations":[{"pid":1,"verdict":"invalid","reason":"x"}],"summary":"x"}"#, #"{"recommendations":[{"pid":2147483648,"verdict":"safe","reason":"x"}],"summary":"x"}"#] {
        do { _ = try AIManager.decode(data: envelope(badJSON), status: 200); check(false, "malformed/partial AI answer rejected") }
        catch { check(true, "malformed/partial AI answer rejected") }
    }
    for (code, text) in [(401, "Sign in"), (402, "plan"), (429, "limit"), (503, "service error"), (302, "redirect")] {
        do { _ = try AIManager.decode(data: Data("not json".utf8), status: code); check(false, "HTTP \(code) handled") }
        catch let err as AIFailure { check(err.message.contains(text), "HTTP \(code) keeps the correct diagnosis without JSON") }
    }
    let target = fixture(1)
    let invalid = AIResp(recommendations: [AIRec(pid: target.pid, verdict: .safe, reason: "safe"),
        AIRec(pid: target.pid, verdict: .critical, reason: "keep"), AIRec(pid: -1, verdict: .safe, reason: "bad"),
        AIRec(pid: 88, verdict: .safe, reason: "not submitted")], summary: "one\ntwo")
    let valid = AIManager.validated(invalid, candidates: [target, target])
    check(valid.recommendations.count == 1 && valid.recommendations[0].verdict == .critical, "duplicate PIDs use the safest verdict and unknown PIDs are excluded")
    let safe = AIResp(recommendations: [AIRec(pid: target.pid, verdict: .safe, reason: "stop")], summary: "s")
    check(AIManager.validated(safe, candidates: [target]).recommendations[0].verdict == .caution, "unknown background cannot become automatically safe")
    check(AIManager.validated(safe, candidates: [fixture(1, type: .user)]).recommendations[0].verdict == .caution, "user app cannot become automatically safe")
    check(AIManager.validated(safe, candidates: [fixture(1, protected: true)]).recommendations[0].verdict == .critical, "protection overrides a model verdict")
    check(AIManager.validated(safe, candidates: []).recommendations.isEmpty, "empty live candidate set cannot signal a PID")
    check(!canAutoTerminate(target), "unknown process is rejected independently of the parser")
    check(!canAutoTerminate(fixture(1, name: "mdworker", protected: true)), "protected worker cannot auto-terminate")
    var bsd = proc_bsdinfo(); bsd.pbi_pid = UInt32(target.pid); bsd.pbi_uid = getuid()
    bsd.pbi_start_tvsec = 100; bsd.pbi_start_tvusec = 123
    check(signalIdentityMatches(target, bsd, path: "/bin/sleep"), "matching process identity accepted by pure validation")
    bsd.pbi_start_tvusec = 124
    check(!signalIdentityMatches(target, bsd, path: "/bin/sleep"), "PID reuse even within one second rejected")
    bsd.pbi_start_tvusec = 123; bsd.pbi_uid = 0
    check(!signalIdentityMatches(target, bsd, path: "/bin/sleep"), "current root ownership rejected")
    bsd.pbi_uid = getuid()
    check(!signalIdentityMatches(target, bsd, path: "/System/worker"), "current system binary rejected")
    check(!signalIdentityMatches(fixture(1, protected: true), bsd, path: "/bin/sleep"), "snapshot protection independently enforced")
    check(!signalIdentityMatches(target, bsd, path: ""), "missing executable identity rejected")
}

class FixtureProtocol: URLProtocol {
    static var failureCode: Int?
    static var responseStatus = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let code = Self.failureCode { client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: code)); return }
        let content = #"{"recommendations":[{"pid":90001,"verdict":"caution","reason":"fixture"},{"pid":90002,"verdict":"caution","reason":"fixture two"}],"summary":"fixture summary"}"#
        let data = try! JSONSerialization.data(withJSONObject: ["message": ["content": content], "done": true, "done_reason": "stop"])
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.responseStatus, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif

class RegressionHarness: NSObject, NSApplicationDelegate {
    var anchor: NSWindow!
    func record(_ label: String) {
        let vc = rgApp.mainVC!, v = vc.view
        check(rgApp.popover.isShown && v.window != nil, "popover actually visible at \(label)")
        check(abs(rgApp.popover.contentSize.height-v.frame.height)<1, "popover/window size matches at \(label)")
        if !vc.showSettings {
            let header = v.subviews.first { $0 is RAMOverview }!
            check(header.frame.minY == 0 && v.visibleRect.contains(header.frame), "graphs visible at \(label)")
        }
        let capture = v.window?.contentView ?? v
        for (name, appearance) in [("light", NSAppearance(named: .aqua)), ("dark", NSAppearance(named: .darkAqua))] {
            v.appearance = appearance
            if let rep = capture.bitmapImageRepForCachingDisplay(in: capture.bounds) {
                capture.cacheDisplay(in: capture.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "TEST_OUTPUT/\(label)-\(name).png"))
            }
        }
        v.appearance = nil
        print("UI \(label): window=\(rgApp.popover.contentSize.height), content=\(v.frame.height)"); fflush(stdout)
    }
    func show() {
        rgApp.popover.show(relativeTo: NSRect(x: 220, y: 70, width: 40, height: 10), of: anchor.contentView!, preferredEdge: .minY)
    }
    func applicationDidFinishLaunching(_ n: Notification) {
        config = AppConfig(); config.aiEnabled = true
#if !LEGACY
        config.cloudAnalysisEnabled = true
#endif
        rgApp.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rgApp.statusItem.button!.title = "RG QA"
        rgApp.popover = NSPopover(); rgApp.popover.behavior = .applicationDefined
#if LEGACY
        rgApp.popover.animates = true
#else
        rgApp.popover.animates = false
#endif
        rgApp.mainVC = MainVC(); rgApp.popover.contentViewController = rgApp.mainVC; _ = rgApp.mainVC.view
        rgApp.procs = fixtures; rgApp.mainVC.update(ram: fixtureRAM, disk: .zero, p: fixtures)
        anchor = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 600, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        anchor.title = "SystemProcesses regression checks"; anchor.orderFrontRegardless(); show()
        DispatchQueue.main.asyncAfter(deadline: .now()+0.4) { self.record("baseline"); self.transition(1) }
    }
    func transition(_ i: Int) {
        let scroll = rgApp.mainVC.view.subviews.first { $0 is NSScrollView } as! NSScrollView
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 800)); scroll.reflectScrolledClipView(scroll.contentView)
        rgApp.mainVC.settingsTap()
        let settings = descendants(rgApp.mainVC.view).first { $0 is SettingsView }!
        let helpButtons = descendants(settings).compactMap { $0 as? NSButton }.filter { $0.toolTip?.hasPrefix("About ") == true }
        check(helpButtons.count == 3, "Settings exposes one information button for each AI checkbox")
        check(helpButtons.allSatisfy { !($0.accessibilityLabel() ?? "").isEmpty }, "AI help buttons have accessible labels")
        let aiCheckboxes = descendants(settings).compactMap { $0 as? NSButton }.filter { $0.isEnabled || $0.title == "Analyze sustained problems (max 6/day)" }
        check(aiCheckboxes.contains { $0.title == "Enable AI recommendations" } &&
              aiCheckboxes.contains { $0.title == "Analyze sustained problems (max 6/day)" } &&
              aiCheckboxes.contains { $0.title == "Allow selected process evidence in cloud requests" },
              "AI checkbox labels remain readable alongside help buttons")
        let field = settings.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable }!
        field.stringValue = "fixture\(i):cloud" // deliberately do not press Return
#if !LEGACY
        if i == 1 {
            let pop = settings.subviews.compactMap { $0 as? NSPopUpButton }.first { $0.toolTip == "AI provider" }!
            pop.selectItem(at: AIProvider.choices.firstIndex(of: .opencodeGo)!); pop.sendAction(pop.action!, to: pop.target)
            check(config.aiProvider == "opencodeGo" && field.stringValue == "deepseek-v4.1-flash", "Go selection uses the correct model ID")
            pop.selectItem(at: AIProvider.choices.firstIndex(of: .ollama)!); pop.sendAction(pop.action!, to: pop.target)
            check(config.aiProvider == "ollama" && field.stringValue == "fixture1:cloud", "switching providers preserves the previous model")
        }
#endif
        DispatchQueue.main.asyncAfter(deadline: .now()+0.4) {
            self.record("settings\(i)")
            rgApp.popover.close()
            DispatchQueue.main.asyncAfter(deadline: .now()+0.7) {
                rgApp.popover.contentViewController = nil; rgApp.popover.contentViewController = rgApp.mainVC; self.show()
                DispatchQueue.main.asyncAfter(deadline: .now()+0.4) {
                    let done = descendants(settings).compactMap { $0 as? NSButton }.first { $0.title == "Done" }!
                    done.performClick(nil); rgApp.timer?.invalidate()
                    rgApp.popover.behavior = .applicationDefined
                    DispatchQueue.main.asyncAfter(deadline: .now()+0.4) {
                        self.record("return\(i)")
                        check(config.aiModel == "fixture\(i):cloud", "Done commits model without Return")
                        check(scroll.contentView.bounds.origin.y == 0, "return from Settings resets scroll")
                        if i<3 { self.transition(i+1) } else { self.finishUI() }
                    }
                }
            }
        }
    }
    func finishUI() {
#if !LEGACY
        config.displayMode = "iconOnly"; rgApp.updateStatusBar()
        check(rgApp.statusItem.button!.attributedTitle.length == 0 && rgApp.statusItem.length == NSStatusItem.squareLength, "icon mode removes all metrics and uses square width")
        check(rgApp.statusItem.button!.image?.isTemplate == true, "menu icon follows system light/dark tint")
        rgApp.sysRAM = fixtureRAM; config.menuBarSSD = false; config.menuBarCPU = false
        for mode in ["usedRam", "percent", "usedTotal"] {
            config.displayMode = mode; rgApp.updateStatusBar()
            let expected = mode == "usedRam" ? fmtShort(fixtureRAM.used) : mode == "percent" ? "50%" : fmtShort(fixtureRAM.used)+"/"+fmtShort(fixtureRAM.total)
            check(rgApp.statusItem.button!.attributedTitle.string == "M "+expected, "status mode \(mode) changes the display")
        }
        let vc = rgApp.mainVC!
        vc.search = "no matches"; vc.rebuildList(resetScroll: true); record("empty")
        vc.search = ""; vc.rebuildList(resetScroll: true); record("restored")
        check(!descendants(vc.view).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "No matching processes" || $0.stringValue == "No processes found" }, "Restoring rows removes the empty-list placeholder")
        let mockConfig = URLSessionConfiguration.ephemeral; mockConfig.protocolClasses = [FixtureProtocol.self]
        vc.aiManager = AIManager(session: URLSession(configuration: mockConfig))
        vc.aiTap(); vc.aiTap(); check(vc.aiLoading, "repeated AI click does not launch or clear another request")
        vc.settingsTap(); let height = vc.view.frame.height
        vc.rebuildList(); check(vc.view.frame.height == height, "late list rebuild cannot corrupt Settings layout")
        DispatchQueue.main.asyncAfter(deadline: .now()+0.2) {
            check(vc.showSettings && !vc.aiLoading && vc.aiRecs.isEmpty, "cancelled AI result is ignored in Settings")
            vc.settingsTap(); rgApp.timer?.invalidate(); rgApp.popover.behavior = .applicationDefined; vc.aiTap()
            DispatchQueue.main.asyncAfter(deadline: .now()+0.2) {
                check(vc.aiRecs.count == 2 && !vc.aiLoading, "mocked end-to-end AI succeeds")
                self.record("ai-result")
                var changed = fixtures; changed[0].ramBytes += 128*1_048_576
                rgApp.procs = changed; vc.update(ram: fixtureRAM, disk: .zero, p: changed)
                check(vc.aiRecs[90001] == nil && vc.aiRecs[90002] != nil, "Changed-process badge expires while unchanged evidence retains its assessment")
                changed[1].executableFileID = "changed-file-identity"
                rgApp.procs = changed; vc.update(ram: fixtureRAM, disk: .zero, p: changed)
                check(vc.aiRecs.isEmpty, "Executable replacement expires the remaining badge")
                rgApp.procs = fixtures

                rgApp.popover.delegate = rgApp
                rgApp.popover.behavior = .semitransient; rgApp.popover.close()
                rgApp.procs = fixtures; rgApp.mainVC.update(ram: fixtureRAM, disk: .zero, p: fixtures); self.show()
                DispatchQueue.main.asyncAfter(deadline: .now()+0.7) {
                    check(rgApp.popover.behavior == .transient, "close resets confirmation behavior")
                    self.record("rapid-reopen")
                    self.dismissalChecks()
                }
            }
        }
#else
        complete()
#endif
    }
#if !LEGACY
    func dismissalChecks() {
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: rgApp.mainVC.view.window!.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        // Escape in a confirmation dialog belongs to the dialog, not the underlying popup.
        rgApp.popover.behavior = .applicationDefined
        let modal = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 180, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        let modalSession = app.beginModalSession(for: modal)
        _ = app.runModalSession(modalSession)
        check(app.modalWindow === modal && !rgApp.handleDismissalKey(escape) && rgApp.popover.isShown, "Popup Escape handling leaves modal confirmation cancellation to AppKit")
        app.endModalSession(modalSession); modal.orderOut(nil)
        rgApp.popover.behavior = .transient
        check(rgApp.handleDismissalKey(escape) && !rgApp.popover.isShown, "Escape dismisses the visible popup")
        check(!rgApp.handleDismissalKey(escape), "Escape is not consumed after the popup closes")
        rgApp.popover.contentViewController = rgApp.mainVC; show()
        rgApp.mainVC.settingsTap()
        let helpView = descendants(rgApp.mainVC.view).first { $0 is SettingsView }!
        let information = descendants(helpView).compactMap { $0 as? NSButton }.filter { $0.toolTip?.hasPrefix("About ") == true }
        for button in information {
            button.performClick(nil)
            check(rgApp.handleDismissalKey(escape) && rgApp.popover.isShown, "Escape closes the information bubble while keeping Settings open")
            check(!rgApp.mainVC.dismissSettingsHelp(), "Dismissed information bubbles leave no stuck help window")
        }
        check(rgApp.handleDismissalKey(escape) && !rgApp.popover.isShown, "Escape dismisses Settings and commits edits")
        rgApp.popover.contentViewController = rgApp.mainVC
        rgApp.toggle()
        check(rgApp.popover.isShown && rgApp.popover.behavior == .transient, "Status button reopens a normally dismissible popup")
        rgApp.toggle()
        check(!rgApp.popover.isShown, "Status button closes the reopened popup")
        app.deactivate()
        rgApp.toggle()
        DispatchQueue.main.asyncAfter(deadline: .now()+0.1) {
            check(app.isActive, "Opening the menu activates the app for keyboard and accessibility input")
            let queuedEscape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: rgApp.mainVC.view.window!.windowNumber, context: nil, characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
            app.postEvent(queuedEscape, atStart: false)
            DispatchQueue.main.asyncAfter(deadline: .now()+0.2) {
                check(!rgApp.popover.isShown, "Escape through the app event queue dismisses the popup via its local monitor")
                boundedHTTPChecks { self.providerFailures(0) }
            }
        }
    }
    func providerFailures(_ index: Int) {
        let codes: [Int?] = [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, nil]
        guard index < codes.count else { FixtureProtocol.failureCode = nil; FixtureProtocol.responseStatus = 200; complete(); return }
        FixtureProtocol.failureCode = codes[index]; FixtureProtocol.responseStatus = index == 2 ? 429 : 200
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [FixtureProtocol.self]
        let manager = AIManager(session: URLSession(configuration: configuration))
        _ = manager.analyze(procs: fixtures, ram: fixtureRAM) { result in
            switch result {
            case .success: check(false, "Offline/timeout/quota errors cannot become successful answers")
            case .failure: check(true, "Offline/timeout/quota error surfaced without fallback")
            }
            self.providerFailures(index+1)
        }
    }
#endif
    func complete() {
        let result = ["checks": checks, "failures": failures]
        print("TEST_RESULT "+String(data: try! JSONSerialization.data(withJSONObject: result, options: .sortedKeys), encoding: .utf8)!); fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }
}
#if !LEGACY
do { try unitChecks() } catch { check(false, "unit check threw: \(error)") }
#endif
let harness = RegressionHarness()
app.delegate = harness; app.setActivationPolicy(.accessory); app.run()
