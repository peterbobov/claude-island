//
//  ScreenSelector.swift
//  ClaudeIsland
//
//  Manages screen selection for multi-monitor setups
//

import AppKit
import Combine

// MARK: - Screen Selection Mode

enum ScreenSelectionMode: Codable, Equatable {
    case automatic
    case specificScreen(ScreenIdentifier)
}

// MARK: - Screen Identifier

/// Identifies a screen by display ID or name for persistence across reconnects
struct ScreenIdentifier: Codable, Equatable {
    let displayID: CGDirectDisplayID?
    let name: String

    init(screen: NSScreen) {
        self.displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        self.name = screen.localizedName
    }

    func matches(_ screen: NSScreen) -> Bool {
        // First try to match by display ID (most reliable)
        if let displayID = displayID,
           let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
           displayID == screenID {
            return true
        }
        // Fall back to name matching for reconnected displays
        return screen.localizedName == name
    }
}

// MARK: - Screen Selector

@MainActor
class ScreenSelector: ObservableObject {
    static let shared = ScreenSelector()

    // MARK: - Published State

    @Published private(set) var availableScreens: [NSScreen] = []
    @Published var isPickerExpanded: Bool = false
    @Published private(set) var selectionMode: ScreenSelectionMode = .automatic

    // MARK: - Persistence Keys

    private let modeKey = "ScreenSelector.mode"
    private let identifierKey = "ScreenSelector.identifier"

    // MARK: - Computed Properties

    /// The currently selected screen based on selection mode
    var selectedScreen: NSScreen? {
        switch selectionMode {
        case .automatic:
            // Prefer built-in display, fall back to main
            return NSScreen.builtin ?? NSScreen.main
        case .specificScreen(let identifier):
            // Find the screen matching the identifier
            if let match = availableScreens.first(where: { identifier.matches($0) }) {
                return match
            }
            // Fall back to automatic if selected screen is disconnected
            return NSScreen.builtin ?? NSScreen.main
        }
    }

    /// Height added to menu when picker is expanded
    var expandedPickerHeight: CGFloat {
        guard isPickerExpanded else { return 0 }
        // Base height for "Automatic" option + per-screen height
        let baseHeight: CGFloat = 36
        let perScreenHeight: CGFloat = 32
        return baseHeight + CGFloat(availableScreens.count) * perScreenHeight + 8
    }

    // MARK: - Initialization

    private init() {
        loadPreferences()
        refreshScreens()
        observeScreenChanges()
    }

    // MARK: - Screen Management

    /// Refresh the list of available screens
    func refreshScreens() {
        availableScreens = NSScreen.screens
    }

    /// Select automatic mode (built-in or main)
    func selectAutomatic() {
        selectionMode = .automatic
        savePreferences()
    }

    /// Select a specific screen
    func selectScreen(_ screen: NSScreen) {
        let identifier = ScreenIdentifier(screen: screen)
        selectionMode = .specificScreen(identifier)
        savePreferences()
    }

    /// Check if a screen is currently selected
    func isSelected(_ screen: NSScreen) -> Bool {
        guard case .specificScreen(let identifier) = selectionMode else {
            return false
        }
        return identifier.matches(screen)
    }

    // MARK: - Screen Change Observation

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screensDidChange() {
        refreshScreens()
    }

    // MARK: - Persistence

    private func loadPreferences() {
        // Load mode
        if let modeData = UserDefaults.standard.data(forKey: modeKey),
           let mode = try? JSONDecoder().decode(ScreenSelectionMode.self, from: modeData) {
            selectionMode = mode
        }
    }

    private func savePreferences() {
        if let modeData = try? JSONEncoder().encode(selectionMode) {
            UserDefaults.standard.set(modeData, forKey: modeKey)
        }
    }
}
