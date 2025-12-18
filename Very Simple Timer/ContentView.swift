import SwiftUI
import AppKit
import Combine

// =====================================================
// MARK: - Main View
// =====================================================
struct ContentView: View {
    private let presets: [String] = ["00:15", "00:30", "00:45", "01:00", "Custom…"]

    @State private var selectedPreset: String = "01:00"
    @State private var customSheetPresented: Bool = false
    @State private var customInput: String = ""
    @State private var statusText: String = "Select a duration and press Start."
    
    private let runningText = "Timer running…"

    // Keep seconds for internal accuracy
    @State private var totalSeconds: Int = 60 * 60
    @State private var remainingSeconds: Int = 60 * 60
    @State private var timerRunning: Bool = false

    // NEW: end date for “minute-based” display updates
    @State private var endDate: Date? = nil

    @State private var endAlertPresented: Bool = false
    @State private var originalLabel: String = "01:00"

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // NEW: what we actually display (minutes change only every 60 seconds)
    private var displayedRemainingSeconds: Int {
        guard timerRunning, let endDate else {
            return remainingSeconds
        }
        let secondsLeft = endDate.timeIntervalSinceNow
        // ceil => 15:00..14:01 shows 15 minutes; drops to 14 only after 60 seconds
        let minutesLeft = max(0, Int(ceil(secondsLeft / 60.0)))
        return minutesLeft * 60
    }
    
    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, Double(remainingSeconds) / Double(totalSeconds)))
    }

    var body: some View {
        VStack(spacing: 16) {

            // Controls row (native macOS look)
            HStack(spacing: 12) {

                Picker("How long?", selection: $selectedPreset) {
                    ForEach(presets, id: \.self) { p in
                        Text(p).tag(p)
                    }
                }
                .frame(width: 180)
                .onChange(of: selectedPreset) {
                    if selectedPreset == "Custom…" {
                        customInput = ""
                        customSheetPresented = true
                    } else {
                        originalLabel = selectedPreset
                        totalSeconds = hmToSeconds(selectedPreset)
                        remainingSeconds = totalSeconds
                        endDate = nil
                        statusText = "Duration selected. Press Start when ready."
                    }
                }                

                if timerRunning {
                    Button("Reset", action: resetTimer)
                        .buttonStyle(.bordered)
                } else {
                    Button("Start", action: startTimer)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.bottom, 6)
            
            Text(statusText)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Divider()

            // NOTE: Use displayedRemainingSeconds instead of remainingSeconds
            Text(secondsToHMString(displayedRemainingSeconds))
                .font(.system(size: 84, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
            
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 1)
                    Rectangle()
                        .fill(timerRunning ? Color.accentColor : Color(nsColor: .separatorColor))
                        .frame(width: geo.size.width * progress, height: 1)
                }
            }
            .frame(height: 1)
        }
        .padding(20)
        // Native macOS window background
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(ticker) { _ in
            guard timerRunning, let endDate else { return }

            let secondsLeft = endDate.timeIntervalSinceNow
            let newRemaining = max(0, Int(ceil(secondsLeft)))

            remainingSeconds = newRemaining

            if newRemaining <= 0 {
                timerRunning = false
                remainingSeconds = 0
                self.endDate = nil
                statusText = "Time's up!"
                beep()
                endAlertPresented = true
                return
            }

            // Only show seconds during the last minute (60 -> 1)
            if newRemaining <= 60 {
                statusText = "Timer running, last minute remaining: \(newRemaining)"
            } else {
                statusText = runningText
            }
        }
        .alert("End of the \(originalLabel) timer", isPresented: $endAlertPresented) {
            Button("OK") { }
        }
        .sheet(isPresented: $customSheetPresented) {
            CustomInputSheet(
                customInput: $customInput,
                onConfirm: handleCustomConfirm,
                onCancel: handleCustomCancel
            )
            .frame(width: 360)
        }
    }

    // MARK: - Actions
    private func startTimer() {
        guard !timerRunning else { return }
        guard remainingSeconds > 0 else {
            beep()
            endAlertPresented = true
            return
        }

        // NEW: set endDate from remainingSeconds (keeps continuity if you later add pause/resume)
        endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        timerRunning = true
        statusText = runningText
    }

    private func resetTimer() {
        timerRunning = false
        endDate = nil
        remainingSeconds = totalSeconds
        statusText = "Timer reset."
    }

    private func handleCustomConfirm() {
        let trimmed = customInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validateHHMM(trimmed) else { return }
        let parts = trimmed.split(separator: ":").map(String.init)
        let hh = Int(parts[0]) ?? 0
        let mm = Int(parts[1]) ?? 0
        totalSeconds = hh * 3600 + mm * 60
        remainingSeconds = totalSeconds
        endDate = nil
        originalLabel = trimmed
        statusText = "Custom duration set. Press Start when ready."
        customSheetPresented = false
        selectedPreset = "Custom…"
    }

    private func handleCustomCancel() {
        selectedPreset = originalLabel
        customSheetPresented = false
    }

    // MARK: - Helpers
    private func hmToSeconds(_ hm: String) -> Int {
        let parts = hm.split(separator: ":").map(String.init)
        guard parts.count == 2, let hh = Int(parts[0]), let mm = Int(parts[1]) else { return 0 }
        return hh * 3600 + mm * 60
    }

    private func secondsToHMString(_ total: Int) -> String {
        let clamped = max(total, 0)
        let hh = clamped / 3600
        let mm = (clamped % 3600) / 60
        return String(format: "%02d:%02d", hh, mm)
    }

    private func beep() {
        NSSound.beep()
    }

    private func validateHHMM(_ input: String) -> Bool {
        let regex = try! NSRegularExpression(pattern: #"^\d{2}:\d{2}$"#)
        let range = NSRange(location: 0, length: input.utf16.count)
        guard regex.firstMatch(in: input, options: [], range: range) != nil else { return false }
        let parts = input.split(separator: ":").map(String.init)
        guard parts.count == 2, let mm = Int(parts[1]), (0...59).contains(mm) else { return false }
        return true
    }
}

// =====================================================
// MARK: - Custom Duration Sheet
// =====================================================
struct CustomInputSheet: View {
    @Binding var customInput: String
    var onConfirm: () -> Void
    var onCancel: () -> Void

    private var isValid: Bool {
        let trimmed = customInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let regex = try! NSRegularExpression(pattern: #"^\d{2}:\d{2}$"#)
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        guard regex.firstMatch(in: trimmed, options: [], range: range) != nil else { return false }
        let parts = trimmed.split(separator: ":").map(String.init)
        guard parts.count == 2, let mm = Int(parts[1]), (0...59).contains(mm) else { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("Enter the value, format HH:MM")
                .font(.headline)
                .foregroundStyle(.primary)

            TextField("HH:MM", text: $customInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity)

            HStack {
                Spacer()

                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)

                Button("OK") { onConfirm() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

