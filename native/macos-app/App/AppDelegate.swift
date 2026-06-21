import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let projectDir = AppDelegate.resolveProjectDir()
    private let audioEngine = LocalAudioEngine()
    private var localPlayerServer: LocalPlayerHTTPServer?
    private var window: NSWindow?
    private var store: SoulDJStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        localPlayerServer = LocalPlayerHTTPServer(audioEngine: audioEngine)
        localPlayerServer?.start()

        let settings = AppSettingsStore()
        settings.save()
        let netease = NeteaseService(projectDir: projectDir)
        let miniMax = MiniMaxService(settings: settings)
        let environment = EnvironmentContextService()
        let songStory = SongStoryService(settings: settings)
        let store = SoulDJStore(settings: settings, netease: netease, audioEngine: audioEngine, miniMax: miniMax, environment: environment, songStory: songStory)
        self.store = store

        createWindow(store: store)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createWindow(store: SoulDJStore) {
        let rootView = SoulDJRootView(store: store)
        let hostingView = NSHostingView(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Soul DJ"
        window.minSize = NSSize(width: 760, height: 500)
        window.center()
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private static func resolveProjectDir() -> String {
        let bundleURL = Bundle.main.bundleURL
        let macosDir = bundleURL.deletingLastPathComponent()
        let candidate = macosDir.deletingLastPathComponent()
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: candidate.appendingPathComponent("script/setup_netease_url.sh").path)
            || fileManager.fileExists(atPath: candidate.appendingPathComponent("vendor/Netease_url").path) {
            return candidate.path
        }
        return macosDir.path
    }
}
