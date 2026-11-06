import AppKit
import SwiftUI

struct AgentsPanel: View {
    @ObservedObject var agents = AgentService.shared
    @ObservedObject var settings = AppSettings.shared
    @State private var draft = ""
    @State private var showOptions = false
    @FocusState private var inputFocused: Bool

    private var kind: AgentKind { agents.kind }

    var body: some View {
        VStack(spacing: 7) {
            header
            Divider().overlay(Theme.hairline)
            conversation
            if let approval = agents.approval, approval.agent == kind {
                ApprovalBar(approval: approval) { agents.replyApproval($0) }
            }
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { agents.activate() }
    }

    private var header: some View {
        HStack(spacing: 5) {
            ForEach(AgentKind.allCases) { agent in
                AgentPill(agent: agent,
                          selected: agent == kind,
                          working: agents.isWorking(for: agent)) {
                    agents.select(agent)
                }
            }
            Spacer(minLength: 4)
            AgentStatusBadge(connection: agents.currentStatus,
                             working: agents.isWorking(for: kind),
                             text: agents.statusLine)
            Button {
                agents.newChat()
                draft = ""
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(PressableButtonStyle())
            .foregroundColor(Theme.textSecondary)
            .help("New chat")

            Button {
                showOptions.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(PressableButtonStyle())
            .foregroundColor(Theme.textSecondary)
            .help("Agent settings")
            .popover(isPresented: $showOptions, arrowEdge: .bottom) {
                AgentOptionsView(agents: agents, settings: settings)
            }
        }
        .frame(height: 24)
    }

    @ViewBuilder private var conversation: some View {
        if agents.messages.isEmpty {
            AgentEmptyState(kind: kind,
                            connection: agents.currentStatus,
                            folder: folderLabel) { text in
                agents.send(text)
            } retry: {
                agents.restart()
            } terminal: {
                agents.openTerminal()
            }
        } else {
            messageList
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(agents.messages) { message in
                        AgentMessageRow(message: message,
                                        working: agents.isWorking(for: kind),
                                        activity: agents.activity[kind] ?? "")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 2)
                .padding(.trailing, 4)
            }
            .onChange(of: agents.tick) { _ in
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Image(systemName: kind.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.accent)
                .padding(.bottom, 5)

            TextField("Ask \(kind.title)…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .lineLimit(1...3)
                .foregroundColor(Theme.text)
                .focused($inputFocused)
                .onSubmit(send)

            if agents.isWorking(for: kind) {
                Button {
                    agents.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(red: 1, green: 0.42, blue: 0.38))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Stop")
            }

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.textTertiary : Color.black)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.shellSoft : Theme.accent))
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agents.isWorking(for: kind))
            .help("Send")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1))
        )
    }

    private var folderLabel: String {
        let path = settings.agentWorkingDirectory
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !agents.isWorking(for: kind) else { return }
        draft = ""
        agents.send(text)
    }
}

// MARK: - header pieces

private struct AgentPill: View {
    let agent: AgentKind
    let selected: Bool
    let working: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: agent.symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(agent.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                if working {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 4, height: 4)
                }
            }
            .foregroundColor(selected ? Theme.text : Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(selected ? Theme.accent.opacity(0.18) : Color.white.opacity(0.05))
            )
            .overlay(
                Capsule().stroke(selected ? Theme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AgentStatusBadge: View {
    let connection: AgentConnection
    let working: Bool
    let text: String

    private var color: Color {
        if working { return Theme.accent }
        switch connection {
        case .ready: return Color(red: 0.36, green: 0.85, blue: 0.62)
        case .connecting: return Color(red: 1, green: 0.78, blue: 0.3)
        case .error: return Color(red: 1, green: 0.42, blue: 0.38)
        case .idle: return Theme.textTertiary
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: 130, alignment: .trailing)
        .help(text)
    }
}

// MARK: - conversation

private struct AgentMessageRow: View {
    let message: AgentMessage
    let working: Bool
    let activity: String

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.accent.opacity(0.16))
                    )
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 5) {
                ForEach(message.tools) { tool in
                    AgentToolRow(tool: tool)
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = message.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 1, green: 0.55, blue: 0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if message.text.isEmpty, message.error == nil, working {
                    HStack(spacing: 6) {
                        TypingDots()
                        Text(activity.isEmpty ? "Working…" : activity)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .system:
            HStack(spacing: 5) {
                Image(systemName: message.error == nil ? "info.circle" : "exclamationmark.triangle.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(message.text)
                    .font(.system(size: 9.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(message.error == nil ? Theme.textTertiary : Color(red: 1, green: 0.55, blue: 0.45))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 2)
        }
    }
}

private struct AgentToolRow: View {
    let tool: AgentTool
    @State private var expanded = false

    private var statusColor: Color {
        switch tool.status {
        case .running: return Theme.accent
        case .done: return Color(red: 0.36, green: 0.85, blue: 0.62)
        case .failed: return Color(red: 1, green: 0.45, blue: 0.4)
        }
    }

    private var statusSymbol: String {
        switch tool.status {
        case .running: return "circle.dotted"
        case .done: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button {
                guard !tool.output.isEmpty else { return }
                expanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: tool.status == .running ? "wrench.and.screwdriver.fill" : statusSymbol)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(statusColor)
                    Text(tool.name)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                    if !tool.detail.isEmpty {
                        Text(tool.detail)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    if !tool.output.isEmpty {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
            }
            .buttonStyle(.plain)

            if expanded, !tool.output.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(tool.output)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 96)
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.black.opacity(0.4))
                )
            }
        }
    }
}

private struct TypingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 4, height: 4)
                    .opacity(phase == index ? 1 : 0.28)
            }
        }
        .onReceive(NotificationCenter.default.timer(interval: 0.3)) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// MARK: - empty / approval / options

private struct AgentEmptyState: View {
    let kind: AgentKind
    let connection: AgentConnection
    let folder: String
    let send: (String) -> Void
    let retry: () -> Void
    let terminal: () -> Void

    private var examples: [String] {
        switch kind {
        case .qoder:
            return ["What changed in this folder?",
                    "Run the tests and fix what fails",
                    "Summarize the last git commit"]
        case .opencode:
            return ["Explain this codebase",
                    "Find and fix a small bug",
                    "Write a script for me"]
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 2)
            Image(systemName: kind.symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundColor(Theme.accent.opacity(0.85))
            switch connection {
            case .error(let message):
                Text("\(kind.title) is offline")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.text)
                Text(message)
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)
                HStack(spacing: 6) {
                    SmallAction(title: "Retry", symbol: "arrow.clockwise", action: retry)
                    SmallAction(title: "Terminal", symbol: "terminal", action: terminal)
                }
                .padding(.top, 2)
            default:
                Text("Ask \(kind.title)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.text)
                Text(connection == .connecting ? "Starting the local agent…" : "Chat, run commands, and see tool output — all from the notch.")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 8))
                    Text(folder)
                        .font(.system(size: 9, design: .monospaced))
                        .lineLimit(1)
                    Text("· Terminal")
                        .font(.system(size: 9))
                }
                .foregroundColor(Theme.textTertiary.opacity(0.8))
                .padding(.top, 1)
                if connection != .connecting {
                    VStack(spacing: 4) {
                        ForEach(examples, id: \.self) { example in
                            Button { send(example) } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 7, weight: .bold))
                                    Text(example)
                                        .font(.system(size: 9.5))
                                        .lineLimit(1)
                                }
                                .foregroundColor(Theme.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.055)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SmallAction: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 8, weight: .bold))
                Text(title).font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(Theme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

private struct ApprovalBar: View {
    let approval: AgentApproval
    let reply: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(red: 1, green: 0.78, blue: 0.3))
                Text(approval.title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Spacer()
                Text("OpenCode")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
            }
            if !approval.detail.isEmpty {
                Text(approval.detail)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            HStack(spacing: 5) {
                approvalButton("Allow once", tint: Theme.accent) { reply("once") }
                approvalButton("Always", tint: nil) { reply("always") }
                approvalButton("Deny", tint: Color(red: 1, green: 0.45, blue: 0.4)) { reply("reject") }
                Spacer()
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 1, green: 0.78, blue: 0.3).opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color(red: 1, green: 0.78, blue: 0.3).opacity(0.25), lineWidth: 1))
        )
    }

    private func approvalButton(_ title: String, tint: Color?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(tint == nil ? Theme.textSecondary : Color.black.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(tint ?? Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - options

private struct AgentOptionsView: View {
    @ObservedObject var agents: AgentService
    @ObservedObject var settings: AppSettings
    @State private var folder: String = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("AGENT SETTINGS")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(Theme.textTertiary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Working folder")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                HStack(spacing: 5) {
                    Text(folderLabel(folder))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…") { chooseFolder() }
                        .controlSize(.mini)
                }
            }

            if agents.kind == .qoder {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Permission mode")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                    Picker("", selection: $settings.qoderPermissionMode) {
                        Text("Ask when needed").tag("default")
                        Text("Auto-approve edits").tag("accept_edits")
                        Text("Never prompt").tag("dont_ask")
                        Text("Bypass all checks").tag("bypass_permissions")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
                FieldLabel(title: "Model (optional)") {
                    TextField("Default model", text: $settings.qoderModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10))
                }
            } else {
                FieldLabel(title: "Server") {
                    TextField("http://127.0.0.1:4096", text: $settings.opencodeBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                }
                FieldLabel(title: "Model (optional)") {
                    TextField("provider/model", text: $settings.opencodeModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                }
                Toggle("Start server automatically", isOn: $settings.agentAutoStart)
                    .font(.system(size: 9.5))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Theme.accent)
            }

            Divider().overlay(Theme.hairline)
            Text("Changes restart the current session.")
                .font(.system(size: 8.5))
                .foregroundColor(Theme.textTertiary)
            HStack(spacing: 6) {
                Button {
                    agents.openTerminal()
                } label: {
                    Label("Terminal", systemImage: "terminal")
                        .font(.system(size: 9, weight: .semibold))
                }
                .controlSize(.small)
                Spacer()
                Button("Apply & reconnect") {
                    settings.agentWorkingDirectory = folder.isEmpty ? settings.agentWorkingDirectory : folder
                    agents.restart()
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 300)
        .onAppear {
            guard !loaded else { return }
            folder = settings.agentWorkingDirectory
            loaded = true
        }
        .foregroundColor(Theme.text)
        .background(Color(red: 0.09, green: 0.09, blue: 0.10))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: folder.isEmpty ? NSHomeDirectory() : folder)
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            folder = url.path
        }
    }

    private func folderLabel(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path.isEmpty ? "~" : path
    }
}

private struct FieldLabel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
            content
        }
    }
}
