import AppKit

let app = NSApplication.shared
let rgApp = SystemProcessesApp()

private let demoAssetsPath = __DEMO_ASSETS__

private func descendants(_ view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants($0) }
}

private func saveRenderedView(_ view: NSView, at path: String) {
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
    let bounds = view.bounds
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else {
        NSLog("Could not allocate demo screenshot for %@", path)
        return
    }
    view.cacheDisplay(in: bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        NSLog("Could not encode demo screenshot for %@", path)
        return
    }
    do { try png.write(to: URL(fileURLWithPath: path), options: .atomic) }
    catch { NSLog("Could not save demo screenshot: %@", error.localizedDescription) }
}

private func fixture(_ pid: Int32, _ name: String, _ owner: String, _ ram: UInt64,
                     type: ProcessType = .user, threads: Int32 = 8, cpu: Double = 0.4,
                     parent: Int32 = 1, childCount: Int = 0, minutesOld: TimeInterval = 37) -> ProcInfo {
    ProcInfo(pid: pid, name: name, ramBytes: ram, cpuPct: cpu, icon: nil,
             type: type, isProtected: type == .system, threads: threads,
             startTime: Date().addingTimeInterval(-minutesOld * 60), ppid: parent,
             childCount: childCount, cpuSampleValid: true, footprintBytes: ram,
             ownerName: owner, executableFileID: "demo-fixture-\(pid)")
}

private final class DemoDriver: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Every row and owner below is deliberately synthetic and declared in this fixture.
        // No process enumeration, model request, or credential lookup is invoked.
        config = AppConfig()
        config.displayMode = "iconOnly"
        config.aiEnabled = false
        config.automaticAnalysis = false
        config.cloudAnalysisEnabled = true
        config.aiProvider = "hybrid"
        config.aiModel = "gemma4:31b-cloud"
        config.showCPU = true
        config.showThreads = false
        config.groupHelpers = true

        let ram = SysRAM(total: 16_000_000_000, appMem: 6_800_000_000,
                         wired: 2_100_000_000, compressed: 430_000_000,
                         free: 4_900_000_000, pressure: .healthy,
                         swapUsed: 0, inactive: 1_770_000_000, purgeable: 280_000_000)
        let disk = DiskInfo(total: 512_000_000_000, free: 192_000_000_000)
        let processes = [
            fixture(10101, "Safari", "Safari", 1_340_000_000, threads: 22, cpu: 2.8, childCount: 2, minutesOld: 86),
            fixture(10102, "Editor", "Visual Studio Code", 940_000_000, threads: 18, cpu: 1.2, childCount: 1, minutesOld: 142),
            fixture(10103, "Build Worker", "Demo Project", 720_000_000, type: .background, threads: 6, cpu: 13.4, minutesOld: 9),
            fixture(10104, "WindowServer", "macOS", 610_000_000, type: .system, threads: 16, cpu: 3.1, minutesOld: 320),
            fixture(10105, "Build Helper", "Demo Project", 380_000_000, type: .background, threads: 4, cpu: 2.1, parent: 10103, minutesOld: 8),
            fixture(10106, "Messages", "Messages", 290_000_000, threads: 11, cpu: 0.2, minutesOld: 57)
        ]
        rgApp.procs = processes
        rgApp.sysRAM = ram
        rgApp.diskInfo = disk
        rgApp.mainVC = MainVC()
        rgApp.mainVC.update(ram: ram, disk: disk, p: processes)

        let main = NSWindow(contentRect: NSRect(x: 0, y: 0, width: POP_W, height: 340),
                            styleMask: .borderless, backing: .buffered, defer: false)
        main.backgroundColor = .windowBackgroundColor
        main.isOpaque = false
        main.hasShadow = true
        main.contentViewController = rgApp.mainVC
        main.setFrameOrigin(NSPoint(x: 260, y: 300))
        main.orderFrontRegardless()
        mainWindow = main

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rgApp.statusItem = statusItem
        config.displayMode = "iconOnly"
        config.menuBarRAM = false
        config.menuBarSSD = false
        config.menuBarCPU = false
        config.menuBarNet = false
        config.menuBarBattery = false
        rgApp.updateStatusBar()

        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.captureProcessList() }
    }

    private func captureProcessList() {
        guard let mainWindow, let view = rgApp.mainVC?.view else { finish(); return }
        mainWindow.setContentSize(view.frame.size)
        mainWindow.displayIfNeeded()
        saveRenderedView(view, at: "\(demoAssetsPath)/processes.png")
        rgApp.mainVC.settingsTap()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.captureSettings() }
    }

    private func captureSettings() {
        guard let mainWindow, let view = rgApp.mainVC?.view else { finish(); return }
        mainWindow.setContentSize(view.frame.size)
        mainWindow.displayIfNeeded()
        saveRenderedView(view, at: "\(demoAssetsPath)/settings.png")

        let helpButton = descendants(view).compactMap { $0 as? NSButton }
            .first { $0.toolTip == "About cloud process evidence" }
        if let helpButton {
            helpButton.performClick(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.captureHelpAndMenuButton() }
        } else {
            captureMenuButton()
        }
    }

    private func captureHelpAndMenuButton() {
        guard let mainWindow, rgApp.mainVC?.view != nil else { captureMenuButton(); return }
        // Keep an additional rendered review image for the longest help copy.
        mainWindow.displayIfNeeded()
        if let helpWindow = app.windows.first(where: {
            $0 !== mainWindow && $0.isVisible && $0.frame.width >= 220 && $0.frame.height >= 80
        }),
           let helpView = helpWindow.contentView {
            saveRenderedView(helpView, at: "\(demoAssetsPath)/settings-help.png")
        }
        rgApp.mainVC.cancelModelDiscovery()
        captureMenuButton()
    }

    private func captureMenuButton() {
        guard let button = rgApp.statusItem?.button else { finish(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            saveRenderedView(button, at: "\(demoAssetsPath)/menu-button.png")
            self?.finish()
        }
    }

    private func finish() {
        mainWindow?.orderOut(nil)
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

private let demoDriver = DemoDriver()
app.setActivationPolicy(.accessory)
app.delegate = demoDriver
app.run()
