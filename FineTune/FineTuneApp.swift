import AppKit
import FluidMenuBarExtra
// FineTune/FineTuneApp.swift
import SwiftUI
import UserNotifications
import os

private let logger = Logger(
    subsystem: "com.finetuneapp.FineTune", category: "App")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var audioEngine: AudioEngine?

    // FluidMenuBarExtra instance is stored programmatically by the delegate
    var menuBarExtra: FluidMenuBarExtra?

    // A provider closure for content so the App can hand a view builder to the delegate
    var menuBarContentProvider: (() -> AnyView)?

    // Expose collaborators so the delegate can create the menu bar content
    var updateManager: UpdateManager?
    var launchIconStyle: MenuBarIconStyle?
    var launchSystemImageName: String?
    var launchAssetImageName: String?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let audioEngine = audioEngine else {
            return
        }
        let urlHandler = URLHandler(audioEngine: audioEngine)

        for url in urls {
            urlHandler.handleURL(url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure required collaborators are available before creating the menu bar
        guard let audioEngine = audioEngine,
              let updateManager = updateManager,
              let launchIconStyle = launchIconStyle else {
            return
        }

        // Build a content closure that captures concrete collaborators (non-optional)
        let contentBuilder: () -> AnyView = {
            AnyView(
                MenuBarPopupView(
                    audioEngine: audioEngine,
                    deviceVolumeMonitor: audioEngine.deviceVolumeMonitor,
                    updateManager: updateManager,
                    launchIconStyle: launchIconStyle
                )
            )
        }

        // Evaluate the builder once to a concrete AnyView so the trailing closure has a known return value
        let contentView = contentBuilder()

         // Choose initializer depending on captured icon names
         let menuBar: FluidMenuBarExtra
         if let asset = launchAssetImageName {
            menuBar = FluidMenuBarExtra(title: "FineTune", image: asset) {
                contentView
            }
         } else if let sysImage = launchSystemImageName {
            menuBar = FluidMenuBarExtra(title: "FineTune", systemImage: sysImage) {
                contentView
            }
         } else {
            menuBar = FluidMenuBarExtra(title: "FineTune", systemImage: "speaker.wave.2") {
                contentView
            }
         }

         self.menuBarExtra = menuBar
    }
}

/// Creates the programmatic FluidMenuBarExtra and stores it on the delegate.
/// This isolates menu-bar lifecycle to the delegate while allowing the App
/// to provide dependencies (audioEngine, updateManager, icon names).
//    func createMenuBar(isInserted: Bool = true) {
//        guard let audioEngine = audioEngine, let updateManager = updateManager, let launchIconStyle = launchIconStyle else {
//            return
//        }
//
//        // If the App provided a content provider closure use it; otherwise build directly
//        let contentBuilder: () -> AnyView = { [weak self] in
//            if let provided = self?.menuBarContentProvider {
//                return provided()
//            }
//            return AnyView(
//                MenuBarPopupView(
//                    audioEngine: audioEngine,
//                    deviceVolumeMonitor: audioEngine.deviceVolumeMonitor,
//                    updateManager: updateManager,
//                    launchIconStyle: launchIconStyle
//                )
//            )
//        }
//
//        // Choose initializer depending on captured icon names
//        let menuBar: FluidMenuBarExtra
//        if let asset = launchAssetImageName {
//            menuBar = FluidMenuBarExtra(title: "FineTune", image: asset) {
//                contentBuilder()
//            }
//        } else if let sysImage = launchSystemImageName {
//            menuBar = FluidMenuBarExtra(title: "FineTune", systemImage: sysImage) {
//                contentBuilder()
//            }
//        } else {
//            menuBar = FluidMenuBarExtra(title: "FineTune", systemImage: "speaker.wave.2") {
//                contentBuilder()
//            }
//        }
//
//        self.menuBarExtra = menuBar
//    }

/// Programmatically set whether the menu bar extra is inserted (visible).
/// This attempts to reuse the existing menuBarExtra if present; if not present,
/// it will create one when requested.
//    func setMenuBarInserted(_ inserted: Bool) {
//        if inserted {
//            if menuBarExtra == nil {
//                createMenuBar(isInserted: true)
//            }
//            // If FluidMenuBarExtra exposes a public API to change insertion at runtime,
//            // prefer calling that here (e.g. menuBarExtra?.isInserted = true). If not,
//            // recreating the menuBarExtra is the fallback.
//        } else {
//            // If the library supports removing/hiding, call the API here. As a
//            // conservative fallback we nil out our reference so it can be deallocated.
//            menuBarExtra = nil menuBarExtra.
//        }
//    }

@main
struct FineTuneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var audioEngine: AudioEngine

    @StateObject private var updateManager = UpdateManager()
    @State private var showMenuBarExtra = true

    /// Icon style captured at launch (doesn't change during runtime)
    private let launchIconStyle: MenuBarIconStyle

    /// Icon name captured at launch for SF Symbols
    private let launchSystemImageName: String?

    /// Icon name captured at launch for asset catalog
    private let launchAssetImageName: String?

    var body: some Scene {
        Settings {}
    }

    /// Show SF Symbol menu bar when launch style is a system symbol
    private var systemIconBinding: Binding<Bool> {
        Binding(
            get: { showMenuBarExtra && launchIconStyle.isSystemSymbol },
            set: { showMenuBarExtra = $0 }
        )
    }

    /// Show asset catalog menu bar when launch style is not a system symbol
    private var assetIconBinding: Binding<Bool> {
        Binding(
            get: { showMenuBarExtra && !launchIconStyle.isSystemSymbol },
            set: { showMenuBarExtra = $0 }
        )
    }

    init() {
        // Install crash handler to clean up aggregate devices on abnormal exit
        CrashGuard.install()
        // Destroy any orphaned aggregate devices from previous crashes
        OrphanedTapCleanup.destroyOrphanedDevices()

        let settings = SettingsManager()
        let profileManager = AutoEQProfileManager()
        let engine = AudioEngine(settingsManager: settings, autoEQProfileManager: profileManager)
        _audioEngine = State(initialValue: engine)

        // Pass engine to AppDelegate
        _appDelegate.wrappedValue.audioEngine = engine

        // Capture icon style at launch - requires restart to change
        let iconStyle = settings.appSettings.menuBarIconStyle
        launchIconStyle = iconStyle

        // Capture the correct icon name based on type
        if iconStyle.isSystemSymbol {
            launchSystemImageName = iconStyle.iconName
            launchAssetImageName = nil
        } else {
            launchSystemImageName = nil
            launchAssetImageName = iconStyle.iconName
        }

        // Pass additional collaborators to the delegate so it can create the menu bar
        _appDelegate.wrappedValue.updateManager = updateManager
        _appDelegate.wrappedValue.launchIconStyle = launchIconStyle
        _appDelegate.wrappedValue.launchSystemImageName = launchSystemImageName
        _appDelegate.wrappedValue.launchAssetImageName = launchAssetImageName

        // Provide a content provider closure that captures the correct stateful values
        _appDelegate.wrappedValue.menuBarContentProvider = {
            [engine, updateManager, launchIconStyle] in
            AnyView(
                MenuBarPopupView(
                    audioEngine: engine,
                    deviceVolumeMonitor: engine.deviceVolumeMonitor,
                    updateManager: updateManager,
                    launchIconStyle: launchIconStyle
                )
            )
        }

        // Create the programmatic menu bar now that collaborators are set
        // _appDelegate.wrappedValue.createMenuBar(isInserted: showMenuBarExtra)

        // Request notification authorization (for device disconnect alerts)
        UNUserNotificationCenter.current().requestAuthorization(options: [
            .alert
        ]) { granted, error in
            if let error {
                logger.error(
                    "Notification authorization error: \(error.localizedDescription)"
                )
            }
            // If not granted, notifications will silently not appear - acceptable behavior
        }

        // Flush settings on app termination to prevent data loss from debounced saves
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [settings] _ in
            Task { @MainActor in
                settings.flushSync()
            }
        }
    }
}
