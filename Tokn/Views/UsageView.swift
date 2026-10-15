import SwiftUI
import ServiceManagement

private let bg      = Color(red: 0.085, green: 0.085, blue: 0.11)
private let cardBg  = Color(white: 1, opacity: 0.055)
private let stroke  = Color(white: 1, opacity: 0.08)
private let div     = Color(white: 1, opacity: 0.07)
private let accent  = Color(red: 0.55, green: 0.36, blue: 0.96)

struct UsageView: View {
    let appModel: AppModel
    @State private var showSettings = false
    @State private var easterEggActive = false
    @State private var history: [UsagePoint] = []

    var body: some View {
        Group {
            if showSettings {
                SettingsPanel(appModel: appModel, showSettings: $showSettings)
                    .transition(.push(from: .trailing))
            } else {
                mainView
                    .transition(.push(from: .leading))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: showSettings)
        .frame(width: 280)
        .background(bg)
        .clipped()
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in showSettings = false }
        .onAppear { history = appModel.historyService.load() }
        .onChange(of: appModel.usageData) { _, _ in history = appModel.historyService.load() }
    }

    // MARK: Main

    private var mainView: some View {
        VStack(spacing: 0) {
            header
            div.frame(height: 1)
            if appModel.updateChecker.availableVersion != nil {
                updateBanner
                div.frame(height: 1)
            }
            if appModel.usageData != nil, let error = appModel.errorMessage {
                staleBanner(error)
                div.frame(height: 1)
            }
            content
            div.frame(height: 1)
            footer
        }
    }

    private var header: some View {
        HStack {
            // Triple-tap the title for the easter egg
            Text(easterEggActive ? "made with ♥" : "Tokn")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(easterEggActive ? accent : .white)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: easterEggActive)
                .onTapGesture(count: 3) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                        easterEggActive = true
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.easeOut(duration: 0.4)) { easterEggActive = false }
                    }
                }

            Spacer()

            // Native ProgressView when loading — always centred, never wobbles
            Button { Task { await appModel.refresh() } } label: {
                Group {
                    if appModel.isLoading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(white: 0.45))
                    }
                }
                .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if appModel.isLoading && appModel.usageData == nil {
            loadingView
        } else if let error = appModel.errorMessage, appModel.usageData == nil {
            errorView(error)
        } else if let data = appModel.usageData {
            VStack(spacing: 8) {
                UsageCard(icon: "timer",    title: "5h Session", limit: data.sessionUsage,
                          history: history, pct: \.sessionPct)
                UsageCard(icon: "calendar", title: "Weekly",     limit: data.weeklyUsage,
                          history: history, pct: \.weeklyPct)
            }
            .padding(10)
        } else {
            loadingView
        }
    }

    private var loadingView: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("loading…")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(white: 0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private func errorView(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(msg)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    // Shown when a refresh fails but older numbers are still on screen.
    private func staleBanner(_ error: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text("refresh failed — showing \(appModel.usageData?.freshnessDescription ?? "old") data")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.5))
                .help(error)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.07))
    }

    // MARK: Update banner

    private var updateBanner: some View {
        HStack(spacing: 8) {
            Circle().fill(accent).frame(width: 6, height: 6)
            Text("v\(appModel.updateChecker.availableVersion ?? "") available")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.65))
            Spacer()
            updateAction
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(accent.opacity(0.07))
    }

    @ViewBuilder
    private var updateAction: some View {
        switch appModel.autoUpdater.phase {
        case .idle:
            // Auto-download starts immediately; idle here means the Task is in flight
            ProgressView().controlSize(.mini).tint(accent)
        case .downloading(let p):
            HStack(spacing: 5) {
                ProgressView(value: p).progressViewStyle(.linear).frame(width: 48).tint(accent)
                Text("\(Int(p * 100))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(white: 0.4))
            }
        case .installing:
            Text("installing…")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.4))
        case .failed(let msg):
            VStack(alignment: .trailing, spacing: 3) {
                Text(msg)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(white: 0.4))
                    .multilineTextAlignment(.trailing)
                Button("retry") {
                    if let update = appModel.updateChecker.available {
                        appModel.autoUpdater.reset()
                        appModel.autoUpdater.startUpdate(update)
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.orange)
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("settings") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) { showSettings = true }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color(white: 0.38))
            .buttonStyle(.plain)
            Spacer()
            Button("quit") { NSApplication.shared.terminate(nil) }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.38))
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - UsageCard

private struct UsageCard: View {
    let icon: String
    let title: String
    let limit: UsageLimit
    let history: [UsagePoint]
    let pct: KeyPath<UsagePoint, Double>

    // Initialised from limit so the card never starts at 0 on (re-)appear
    @State private var displayed: Double
    @State private var fillFraction: Double
    @State private var showHistory = false
    @State private var showPrecisePct = false

    init(icon: String, title: String, limit: UsageLimit,
         history: [UsagePoint], pct: KeyPath<UsagePoint, Double>) {
        self.icon    = icon
        self.title   = title
        self.limit   = limit
        self.history = history
        self.pct     = pct
        _displayed    = State(initialValue: limit.utilization)
        _fillFraction = State(initialValue: min(limit.utilization / 100, 1))
    }

    var body: some View {
        let eta = etaDescription
        VStack(alignment: .leading, spacing: 7) {
            // Title + percentage row
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.38))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(white: 0.62))
                Spacer()
                Text("\(Int(displayed))%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(limit.status.color)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4, dampingFraction: 0.82), value: displayed)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(white: 1, opacity: 0.07))
                        .frame(height: 4)
                    Capsule()
                        .fill(limit.status.color)
                        .frame(width: max(3, geo.size.width * fillFraction), height: 4)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: fillFraction)
                }
            }
            .frame(height: 4)

            // Sparkline / history chart — tap to toggle between compact and full view
            if history.count >= 3 {
                Group {
                    if showHistory {
                        HistoryChartView(points: history, pct: pct, color: limit.status.color)
                    } else {
                        SparklineView(points: history.map { $0[keyPath: pct] }, color: limit.status.color)
                            .frame(height: 22)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { showHistory.toggle() }
                }
            }

            // Reset time + status dot always visible; ETA appears as a second line when available
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(limit.resetDescription)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(white: 0.28))
                    Spacer()
                    // Triple-tap the status indicator to reveal exact decimal precision
                    HStack(spacing: 3) {
                        Circle().fill(limit.status.color).frame(width: 5, height: 5)
                        Text(showPrecisePct
                            ? String(format: "%.1f%%", limit.utilization)
                            : limit.status.label.lowercased())
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(limit.status.color.opacity(0.8))
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showPrecisePct)
                    }
                    .onTapGesture(count: 3) {
                        guard !showPrecisePct else { return }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { showPrecisePct = true }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation(.easeOut(duration: 0.4)) { showPrecisePct = false }
                        }
                    }
                }
                if let eta {
                    Text(eta)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(limit.status.color.opacity(0.75))
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cardBg)
                .strokeBorder(stroke, lineWidth: 0.5)
        )
        .onChange(of: limit.utilization) { _, newVal in
            displayed    = newVal
            fillFraction = min(newVal / 100, 1)
        }
    }

    // ETA shown only when the limit would be hit before the window resets, using
    // a least-squares slope over the last 30 min so momentary bursts don't mislead.
    private var etaDescription: String? {
        guard let rate = burnRatePerHour(), rate >= 1.0 else { return nil }
        let hoursLeft = (100.0 - limit.utilization) / rate
        guard hoursLeft > 0, hoursLeft <= 24 else { return nil }
        // Suppress when the window resets before the limit is hit — would be misleading
        let hoursToReset = max(0, limit.resetAt.timeIntervalSinceNow) / 3600
        guard hoursLeft < hoursToReset else { return nil }
        if hoursLeft < 1.0 / 60.0 { return "limit imminent" }
        if hoursLeft < 1 { return "~\(max(1, Int(hoursLeft * 60)))m at this pace" }
        let h = Int(hoursLeft)
        let m = Int((hoursLeft - Double(h)) * 60)
        return m == 0 ? "~\(h)h at this pace" : "~\(h)h \(m)m at this pace"
    }

    // Least-squares linear regression (% per hour) over the last 30 min.
    // Requires 3+ points spanning ≥5 min; least-squares smooths individual spikes.
    private func burnRatePerHour() -> Double? {
        let now = Date()
        let recent = history.filter { now.timeIntervalSince($0.date) <= 30 * 60 }
        guard recent.count >= 3,
              let first = recent.first, let last = recent.last else { return nil }
        let span = last.date.timeIntervalSince(first.date) / 3600
        guard span >= 5.0 / 60.0 else { return nil }  // < 5 min → too noisy
        let xs = recent.map { $0.date.timeIntervalSince(first.date) / 3600 }
        let ys = recent.map { $0[keyPath: pct] }
        let n  = Double(recent.count)
        let sumX  = xs.reduce(0, +)
        let sumY  = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0.0) { $0 + $1.0 * $1.1 }
        let sumXX = xs.reduce(0.0) { $0 + $1 * $1 }
        let denom = n * sumXX - sumX * sumX
        guard abs(denom) > 1e-9 else { return nil }
        return (n * sumXY - sumX * sumY) / denom
    }
}

// MARK: - HistoryChartView

private struct HistoryChartView: View {
    let points: [UsagePoint]
    let pct: KeyPath<UsagePoint, Double>
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Canvas { ctx, size in
                guard points.count >= 2,
                      let first = points.first, let last = points.last else { return }
                let timeSpan = last.date.timeIntervalSince(first.date)
                guard timeSpan > 0 else { return }

                let pts: [CGPoint] = points.map { pt in
                    let x = CGFloat(pt.date.timeIntervalSince(first.date) / timeSpan) * size.width
                    let y = size.height * CGFloat(1.0 - pt[keyPath: pct] / 100.0)
                    return CGPoint(x: x, y: max(0, min(size.height, y)))
                }

                // Dashed threshold lines (orange = 50%, red = 80%)
                for (fraction, lineColor): (CGFloat, Color) in [
                    (0.80, Color(red: 1.0, green: 0.27, blue: 0.23)),
                    (0.50, Color(red: 1.0, green: 0.62, blue: 0.04))
                ] {
                    let y = size.height * (1 - fraction)
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(lineColor.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }

                // Fill gradient beneath the line
                var fillPath = Path()
                if let fp = pts.first, let lp = pts.last {
                    fillPath.move(to: CGPoint(x: fp.x, y: size.height))
                    pts.forEach { fillPath.addLine(to: $0) }
                    fillPath.addLine(to: CGPoint(x: lp.x, y: size.height))
                    fillPath.closeSubpath()
                }
                ctx.fill(fillPath, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.22), color.opacity(0)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

                // Chart line
                var chartLine = Path()
                for (i, pt) in pts.enumerated() {
                    i == 0 ? chartLine.move(to: pt) : chartLine.addLine(to: pt)
                }
                ctx.stroke(chartLine, with: .color(color.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                // Dot at current (rightmost) value
                if let lastPt = pts.last {
                    ctx.fill(Path(ellipseIn: CGRect(x: lastPt.x - 2.5, y: lastPt.y - 2.5,
                                                    width: 5, height: 5)),
                             with: .color(color))
                }
            }
            .frame(height: 52)

            // Time span: oldest recorded point → now
            HStack {
                Text(spanLabel)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(white: 0.25))
                Spacer()
                Text("now")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(white: 0.25))
            }
        }
    }

    private var spanLabel: String {
        guard let first = points.first else { return "" }
        let elapsed = Date().timeIntervalSince(first.date)
        if elapsed < 3600 { return "\(max(1, Int(elapsed / 60)))m ago" }
        let h = Int(elapsed / 3600)
        let m = Int(elapsed.truncatingRemainder(dividingBy: 3600) / 60)
        return m == 0 ? "\(h)h ago" : "\(h)h \(m)m ago"
    }
}

// MARK: - SettingsPanel

private struct SettingsPanel: View {
    let appModel: AppModel
    @Binding var showSettings: Bool
    @State private var selectedInterval: TimeInterval = 60
    @State private var showClearConfirm = false
    @State private var clearError: String?

    private let intervals: [(label: String, value: TimeInterval)] = [
        ("1 min",  60),
        ("2 min",  120),
        ("5 min",  300),
        ("10 min", 600)
    ]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.8))
                HStack {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) { showSettings = false }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .semibold))
                            Text("back")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundStyle(Color(white: 0.4))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            div.frame(height: 1)

            VStack(alignment: .leading, spacing: 0) {
                rowLabel("Refresh")
                Picker("", selection: $selectedInterval) {
                    ForEach(intervals, id: \.value) { Text($0.label).tag($0.value) }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 14)

                div.frame(height: 1).padding(.bottom, 12)

                rowLabel("Menu Bar Icon")
                Picker("", selection: Binding(
                    get: { appModel.settings.menuBarStyle },
                    set: { appModel.settings.menuBarStyle = $0 }
                )) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 14)

                div.frame(height: 1).padding(.bottom, 12)

                rowLabel("Notifications")
                Toggle(isOn: Binding(
                    get: { appModel.settings.notificationsEnabled },
                    set: { appModel.settings.notificationsEnabled = $0 }
                )) {
                    Text("Alert at \(appModel.settings.notificationThreshold)% and 100%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(white: 0.55))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .padding(.bottom, appModel.settings.notificationsEnabled ? 8 : 14)

                if appModel.settings.notificationsEnabled {
                    Picker("", selection: Binding(
                        get: { appModel.settings.notificationThreshold },
                        set: { appModel.settings.notificationThreshold = $0 }
                    )) {
                        ForEach([50, 60, 70, 80, 90], id: \.self) { t in
                            Text("\(t)%").tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 14)
                }

                rowLabel("Startup")
                Toggle(isOn: Binding(
                    get: { appModel.settings.launchAtLogin },
                    set: { newValue in
                        appModel.settings.launchAtLogin = newValue
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
                )) {
                    Text("Launch at login")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(white: 0.55))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .padding(.bottom, 14)

                div.frame(height: 1).padding(.bottom, 12)

                if let error = clearError {
                    Text(error)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.red)
                        .padding(.bottom, 8)
                }

                // confirmationDialog doesn't work in MenuBarExtra NSPanel —
                // use inline confirmation instead.
                if showClearConfirm {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("remove session key?")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(white: 0.55))
                        HStack(spacing: 10) {
                            Button("confirm") {
                                do {
                                    try appModel.clearSessionKey()
                                    showSettings = false
                                } catch {
                                    clearError = error.localizedDescription
                                    showClearConfirm = false
                                }
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.85))
                            .buttonStyle(.plain)

                            Button("cancel") { showClearConfirm = false }
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(white: 0.38))
                                .buttonStyle(.plain)
                        }
                    }
                } else {
                    Button { showClearConfirm = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "trash").font(.system(size: 11))
                            Text("remove session key")
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.85))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            div.frame(height: 1)

            HStack {
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(white: 0.35))
                Spacer()
                Button("quit") { NSApplication.shared.terminate(nil) }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(white: 0.38))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .onAppear {
            selectedInterval = appModel.settings.refreshInterval
            // Sync toggle with actual system state in case user changed it outside the app
            let registered = SMAppService.mainApp.status == .enabled
            if appModel.settings.launchAtLogin != registered {
                appModel.settings.launchAtLogin = registered
            }
        }
        .onChange(of: selectedInterval) { appModel.settings.setRefreshInterval(selectedInterval) }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color(white: 0.32))
            .kerning(0.8)
            .textCase(.uppercase)
            .padding(.bottom, 6)
    }
}
