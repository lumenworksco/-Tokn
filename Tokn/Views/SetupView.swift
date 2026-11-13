import SwiftUI

struct SetupView: View {
    let appModel: AppModel

    @State private var rawKey = ""
    @State private var label = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    private let bg     = Color(red: 0.085, green: 0.085, blue: 0.11)
    private let cardBg = Color(white: 1, opacity: 0.055)
    private let stroke = Color(white: 1, opacity: 0.08)
    private let div    = Color(white: 1, opacity: 0.07)
    private let accent = Color(red: 0.55, green: 0.36, blue: 0.96)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(white: 0.35))
                }
                Spacer()
                if appModel.isSetupComplete {
                    Button("cancel") { appModel.setupMode = nil }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(white: 0.4))
                        .buttonStyle(.plain)
                        .disabled(isConnecting)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 12)

            div.frame(height: 1)

            VStack(alignment: .leading, spacing: 0) {
                Text("SESSION KEY")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(white: 0.32))
                    .kerning(0.8)
                    .padding(.bottom, 6)

                SecureField("paste your session key…", text: $rawKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(cardBg)
                            .strokeBorder(stroke, lineWidth: 0.5)
                    )
                    .padding(.bottom, 8)

                Text("claude.ai → DevTools (⌘⌥I), copy the sessionKey cookie\nChrome: Application → Cookies\nSafari: Storage → Cookies")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(white: 0.28))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)

                if appModel.setupMode == .add {
                    Text("NAME")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(white: 0.32))
                        .kerning(0.8)
                        .padding(.bottom, 6)

                    TextField("optional — e.g. work, personal", text: $label)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(cardBg)
                                .strokeBorder(stroke, lineWidth: 0.5)
                        )
                        .padding(.bottom, 12)
                }

                if let error = errorMessage {
                    Text("✗ \(error)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.red)
                        .padding(.bottom, 8)
                }

                Button(action: connect) {
                    HStack(spacing: 5) {
                        if isConnecting {
                            ProgressView().controlSize(.mini)
                            Text("connecting…")
                        } else {
                            Text("connect →")
                        }
                    }
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(accent.opacity(isConnecting ? 0.5 : 1))
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(rawKey.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
                .opacity(rawKey.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .frame(width: 280)
        .background(bg)
    }

    private var replacingId: UUID? {
        if case .replaceKey(let id) = appModel.setupMode { return id }
        return nil
    }

    private var isReplacing: Bool { replacingId != nil }

    private var title: String {
        if let id = replacingId, let account = appModel.accounts.first(where: { $0.id == id }) {
            return "New key · \(account.label)"
        }
        return appModel.isSetupComplete ? "Add account" : "Tokn"
    }

    private var subtitle: String {
        if isReplacing { return "Paste a fresh session key." }
        return appModel.isSetupComplete
            ? "Track another Claude login's limits."
            : "Claude session usage in your menu bar."
    }

    private func connect() {
        let key = rawKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        isConnecting = true
        errorMessage = nil

        Task {
            defer { isConnecting = false }
            do {
                try await appModel.saveSessionKey(key, label: label, replacing: replacingId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
