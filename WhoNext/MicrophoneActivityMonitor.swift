//
//  MicrophoneActivityMonitor.swift
//  WhoNext
//
//  Created on 1/1/26.
//

import Foundation
import AVFoundation
import Combine
import AppKit

/// Monitors system-wide microphone usage to detect ad-hoc meetings/calls
/// This catches meetings that aren't on the calendar (Slack huddles, quick calls, etc.)
class MicrophoneActivityMonitor: ObservableObject {

    // MARK: - Published Properties
    @Published var isMicrophoneInUse = false
    @Published var activeApplication: String?
    @Published var activityDuration: TimeInterval = 0

    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var checkTimer: Timer?
    private var activityStartTime: Date?

    // Threshold for considering it a "meeting" vs just a quick voice note
    private let minimumDurationForMeeting: TimeInterval = 30 // 30 seconds

    // Callback when potential meeting detected
    var onPotentialMeetingDetected: ((String) -> Void)?

    // MARK: - Initialization

    init() {
        // Monitor mic usage every 2 seconds
        startMonitoring()
    }

    // MARK: - Public Methods

    func startMonitoring() {
        print("🎤 Starting microphone activity monitoring...")

        checkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkMicrophoneActivity()
        }

        // Check immediately
        checkMicrophoneActivity()
    }

    func stopMonitoring() {
        print("🎤 Stopping microphone activity monitoring")
        checkTimer?.invalidate()
        checkTimer = nil
        resetActivity()
    }

    // MARK: - Private Methods

    private func checkMicrophoneActivity() {
        let wasMicInUse = isMicrophoneInUse

        // Check if any app is using the microphone
        let (isInUse, appName) = isMicrophoneCurrentlyInUse()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.isMicrophoneInUse = isInUse
            self.activeApplication = appName

            if isInUse && !wasMicInUse {
                // Mic just became active
                self.activityStartTime = Date()
                print("🎤 Microphone activated by: \(appName ?? "Unknown")")
            } else if !isInUse && wasMicInUse {
                // Mic just became inactive
                self.handleMicrophoneDeactivated()
            } else if isInUse, let startTime = self.activityStartTime {
                // Ongoing mic usage
                self.activityDuration = Date().timeIntervalSince(startTime)

                // Check if this looks like a meeting
                if self.activityDuration >= self.minimumDurationForMeeting && !self.hasNotifiedAboutCurrentActivity {
                    self.handlePotentialMeetingDetected()
                }
            }
        }
    }

    private var hasNotifiedAboutCurrentActivity = false

    private func handlePotentialMeetingDetected() {
        guard let appName = activeApplication else { return }
        hasNotifiedAboutCurrentActivity = true

        print("📞 Potential meeting detected via microphone: \(appName) (duration: \(Int(activityDuration))s)")
        onPotentialMeetingDetected?(appName)
    }

    private func handleMicrophoneDeactivated() {
        print("🎤 Microphone deactivated (was active for \(Int(activityDuration))s)")
        resetActivity()
    }

    private func resetActivity() {
        activityStartTime = nil
        activityDuration = 0
        hasNotifiedAboutCurrentActivity = false
        activeApplication = nil
    }

    /// Check if microphone is currently in use by checking running applications
    private func isMicrophoneCurrentlyInUse() -> (Bool, String?) {
        // Get all running applications
        let runningApps = NSWorkspace.shared.runningApplications

        // Common apps that use microphone for meetings/calls
        let meetingApps = [
            "us.zoom.xos": "Zoom",
            "com.microsoft.teams": "Microsoft Teams",
            "com.microsoft.teams2": "Microsoft Teams",
            "com.google.Chrome": "Chrome",
            "com.apple.Safari": "Safari",
            "org.mozilla.firefox": "Firefox",
            "com.tinyspeck.slackmacgap": "Slack",
            "com.discord.Discord": "Discord",
            "com.skype.skype": "Skype",
            "com.apple.FaceTime": "FaceTime",
            "WhatsApp": "WhatsApp",
            "company.thebrowser.Browser": "Arc"
        ]

        // Check if any meeting app is running and frontmost
        // (Heuristic: if a meeting app is frontmost, it's likely using the mic for a call)
        let frontmostApp = NSWorkspace.shared.frontmostApplication

        if let bundleID = frontmostApp?.bundleIdentifier,
           let appName = meetingApps[bundleID] {
            // Additionally check if the app's window title suggests an active call
            if isLikelyInCall(bundleID: bundleID) {
                return (true, appName)
            }
        }

        // Fallback: Check all running meeting apps
        for app in runningApps {
            if let bundleID = app.bundleIdentifier,
               let appName = meetingApps[bundleID],
               isLikelyInCall(bundleID: bundleID) {
                return (true, appName)
            }
        }

        return (false, nil)
    }

    /// Heuristic to determine if app is likely in a call
    /// This is imperfect but better than nothing
    private func isLikelyInCall(bundleID: String) -> Bool {
        // For native apps like Zoom, Teams, check if they're running
        let nativeCallApps = [
            "us.zoom.xos",
            "com.microsoft.teams",
            "com.microsoft.teams2",
            "com.tinyspeck.slackmacgap",
            "com.discord.Discord",
            "com.skype.skype",
            "com.apple.FaceTime"
        ]

        if nativeCallApps.contains(bundleID) {
            // If app is running, assume potential call
            // More sophisticated: check window title for "Meeting", "Call", etc.
            return checkWindowTitleForCallKeywords(bundleID: bundleID)
        }

        // For browsers, harder to detect - would need to check window titles
        // for "Meet", "Zoom", "Teams", etc.
        if bundleID.contains("Chrome") || bundleID.contains("Safari") || bundleID.contains("firefox") || bundleID.contains("Browser") {
            return checkWindowTitleForCallKeywords(bundleID: bundleID)
        }

        return false
    }

    /// Check if window title contains call-related keywords
    private func checkWindowTitleForCallKeywords(bundleID: String) -> Bool {
        // This requires Accessibility permissions
        // Get the app's windows and check titles
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return false
        }

        // Get window titles using Accessibility API
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowList: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowList)

        guard result == .success,
              let windows = windowList as? [AXUIElement] else {
            return false
        }

        let callKeywords = ["meeting", "call", "zoom", "teams", "meet", "huddle", "voice", "video"]

        for window in windows {
            var titleRef: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)

            if titleResult == .success,
               let title = titleRef as? String {
                let lowercaseTitle = title.lowercased()
                if callKeywords.contains(where: { lowercaseTitle.contains($0) }) {
                    return true
                }
            }
        }

        return false
    }
}
