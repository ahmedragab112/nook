import AppKit
import Combine
import Foundation

// MARK: - models

enum AgentKind: String, CaseIterable, Identifiable, Codable {
    case qoder
    case opencode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qoder: return "Qoder"
        case .opencode: return "OpenCode"
        }
    }

    var symbol: String {
        switch self {
        case .qoder: return "sparkles"
        case .opencode: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct AgentTool: Identifiable, Equatable {
    enum Status: String { case running, done, failed }
    var id: String
    var name: String
    var detail: String
    var output: String = ""
    var status: Status = .running
}

struct AgentMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant, system }
    var id = UUID()
    var role: Role
    var text: String = ""
    var tools: [AgentTool] = []
    var error: String?
}

struct AgentApproval: Identifiable, Equatable {
    var id: String { serverID }
    var agent: AgentKind
    var serverID: String
    var title: String
    var detail: String
}

enum AgentConnection: Equatable {
    case idle
    case connecting
    case ready
    case error(String)

    var isReady: Bool { self == .ready }
}

// MARK: - service

@MainActor
final class AgentService: ObservableObject {
    static let shared = AgentService()

    @Published private(set) var kind: AgentKind
    @Published private(set) var status: [AgentKind: AgentConnection] = [:]
    @Published private(set) var transcripts: [AgentKind: [AgentMessage]] = [:]
    @Published private(set) var running: Set<AgentKind> = []
    @Published private(set) var activity: [AgentKind: String] = [:]
    @Published var approval: AgentApproval?
    @Published private(set) var tick: Int = 0

    private let settings = AppSettings.shared
    private let qoder = QoderProcess()
    private let opencode = OpenCodeConnection()
    private var sessions: [AgentKind: String] = [:]
    private var stopRequested = false
    private var activated = false

    private var ocBase: URL?
    private var ocStream: OpenCodeStream?
    private var ocConnecting = false
    private var ocRetry: DispatchWorkItem?
    private var ocServer: Process?
    private var ocMessageIndex: [String: Int] = [:]
    private var ocRoles: [String: String] = [:]
    private var ocToolIndex: [String: Int] = [:]
    private var ocLastAssistant: UUID?
    private var ocPendingAssistant: UUID?
    private var qoderAssistant: UUID?

    init() {
        kind = AgentKind(rawValue: UserDefaults.standard.string(forKey: "agentKind") ?? "") ?? .qoder
        status = [.qoder: .idle, .opencode: .idle]
        let sandbox = RunMode.isRendering
        if !sandbox {
            status[.qoder] = QoderProcess.locate() == nil
                ? .error("Qoder CLI not found at ~/.local/bin/qodercli")
                : .ready
        } else {
            status[.qoder] = .ready
            status[.opencode] = .ready
        }
    }

    // MARK: derived state

    var messages: [AgentMessage] { transcripts[kind] ?? [] }

    var currentStatus: AgentConnection { status[kind] ?? .idle }

    var anyWorking: Bool { !running.isEmpty }

    func isWorking(for kind: AgentKind) -> Bool { running.contains(kind) }

    var statusLine: String {
        if running.contains(kind) {
            return activity[kind].flatMap { $0.isEmpty ? nil : $0 } ?? "Working…"
        }
        switch currentStatus {
        case .ready: return "Ready"
        case .idle: return "Idle"
        case .connecting: return "Starting…"
        case .error(let message): return message
        }
    }

    // MARK: lifecycle

    func activate() {
        guard !activated else { return }
        activated = true
        if kind == .opencode { connectOpenCode() }
    }

    func select(_ next: AgentKind) {
        guard next != kind else { return }
        kind = next
        settings.agentKind = next.rawValue
        if next == .opencode { connectOpenCode() }
        tick &+= 1
    }

    func newChat() {
        if running.contains(kind) { stop() }
        sessions[kind] = nil
        transcripts[kind] = []
        switch kind {
        case .qoder:
            qoder.finish()
            qoderAssistant = nil
        case .opencode:
            approval = nil
            ocMessageIndex = [:]
            ocRoles = [:]
            ocToolIndex = [:]
            ocLastAssistant = nil
            ocPendingAssistant = nil
        }
        tick &+= 1
    }

    func restart() {
        if running.contains(.opencode) { stop() }
        qoder.finish()
        sessions[.qoder] = nil
        sessions[.opencode] = nil
        if kind == .opencode { connectOpenCode(force: true) }
        if kind == .qoder {
            status[.qoder] = QoderProcess.locate() == nil
                ? .error("Qoder CLI not found at ~/.local/bin/qodercli")
                : .ready
        }
        tick &+= 1
    }

    func shutdown() {
        qoder.finish()
        ocStream?.stop()
        ocRetry?.cancel()
        ocServer?.terminate()
    }

    // MARK: sending

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if QoderProcess.debug { print("AGENT send: kind=\(kind.rawValue) text=\(text)") }
        guard !text.isEmpty, !running.contains(kind) else { return }
        var list = transcripts[kind] ?? []
        list.append(AgentMessage(role: .user, text: text))
        transcripts[kind] = list
        stopRequested = false
        switch kind {
        case .qoder: sendQoder(text)
        case .opencode: sendOpenCode(text)
        }
    }

    func stop() {
        guard running.contains(kind) else { return }
        stopRequested = true
        switch kind {
        case .qoder:
            qoder.finish()
            appendSystem(kind, "Stopped.")
        case .opencode:
            if let sid = sessions[.opencode] {
                Task { try? await opencode.post("/session/\(sid)/abort", query: ["directory": workDir], body: nil) }
            }
        }
        finish(kind)
    }

    func replyApproval(_ reply: String) {
        guard let approval, approval.agent == .opencode else { return }
        let requestID = approval.serverID
        let sid = sessions[.opencode]
        self.approval = nil
        if running.contains(.opencode) {
            activity[.opencode] = "Resuming…"
            refreshNotch()
        }
        Task {
            var lastError: Error?
            do {
                _ = try await opencode.post("/permission/\(requestID)/reply",
                                            query: nil,
                                            body: ["reply": reply])
                return
            } catch { lastError = error }
            if let sid {
                do {
                    _ = try await opencode.post("/api/session/\(sid)/permission/\(requestID)/reply",
                                                query: nil,
                                                body: ["reply": reply])
                    return
                } catch { lastError = error }
                do {
                    _ = try await opencode.post("/session/\(sid)/permissions/\(requestID)",
                                                query: nil,
                                                body: ["response": reply])
                    return
                } catch { lastError = error }
            }
            self.approval = approval
            if self.running.contains(.opencode) {
                self.activity[.opencode] = "Waiting for approval"
                self.refreshNotch()
            }
            self.appendSystem(.opencode, "Could not answer approval: \(lastError?.localizedDescription ?? "unknown error")")
        }
    }

    func openTerminal() {
        let dir = workDir
        let url = URL(fileURLWithPath: dir)
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([url], withApplicationAt: terminal,
                                configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: qoder

    private var workDir: String {
        let path = settings.agentWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        var isDir: ObjCBool = false
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return NSHomeDirectory()
        }
        return path
    }

    private func sendQoder(_ text: String) {
        guard QoderProcess.locate() != nil else {
            fail(.qoder, "Qoder CLI not found. Install it with `npm i -g @qoder-ai/qodercli` or open Qoder Desktop.")
            return
        }
        running.insert(.qoder)
        activity[.qoder] = "Thinking…"
        status[.qoder] = .ready
        refreshNotch()

        if !qoder.isRunning {
            var list = transcripts[.qoder] ?? []
            list.append(AgentMessage(role: .assistant, text: ""))
            transcripts[.qoder] = list
            qoderAssistant = list.last?.id
            do {
                try qoder.start(cwd: workDir,
                                permissionMode: settings.qoderPermissionMode,
                                model: settings.qoderModel,
                                resume: sessions[.qoder],
                                onEvent: { [weak self] event in
                                    Task { @MainActor in self?.handleQoder(event) }
                                },
                                onExit: { [weak self] code, message in
                                    Task { @MainActor in self?.qoderExited(code: code, message: message) }
                                })
            } catch {
                fail(.qoder, "Could not start Qoder: \(error.localizedDescription)")
                return
            }
        } else {
            var list = transcripts[.qoder] ?? []
            list.append(AgentMessage(role: .assistant, text: ""))
            transcripts[.qoder] = list
            qoderAssistant = list.last?.id
        }

        do {
            try qoder.send(text)
            tick &+= 1
            refreshNotch()
        } catch {
            fail(.qoder, "Could not send to Qoder: \(error.localizedDescription)")
        }
    }

    private func handleQoder(_ event: [String: Any]) {
        let type = event["type"] as? String ?? ""
        if let sid = event["session_id"] as? String, !sid.isEmpty {
            sessions[.qoder] = sid
        }
        switch type {
        case "assistant":
            guard running.contains(.qoder) else { return }
            let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            for block in content {
                switch block["type"] as? String {
                case "thinking":
                    activity[.qoder] = "Thinking…"
                case "text":
                    let text = block["text"] as? String ?? ""
                    guard !text.isEmpty else { continue }
                    appendAssistantText(.qoder, text, separator: "\n\n")
                    activity[.qoder] = "Writing…"
                case "tool_use":
                    let id = block["id"] as? String ?? UUID().uuidString
                    let name = block["name"] as? String ?? "Tool"
                    let input = block["input"] as? [String: Any] ?? [:]
                    let detail = QoderProcess.toolDetail(name: name, input: input)
                    addTool(.qoder, id: id, name: name, detail: detail)
                    activity[.qoder] = detail.isEmpty ? name : "\(name) · \(detail)"
                default:
                    break
                }
            }
            refreshNotch()
            tick &+= 1
        case "user":
            guard running.contains(.qoder) else { return }
            guard let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return }
            let meta = event["tool_use_result"] as? [String: Any]
            for block in content where block["type"] as? String == "tool_result" {
                let id = block["tool_use_id"] as? String ?? ""
                let raw = Self.text(from: block["content"])
                var output = raw
                if let meta {
                    let stdout = meta["stdout"] as? String ?? ""
                    let stderr = meta["stderr"] as? String ?? ""
                    let combined = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
                    if !combined.isEmpty { output = combined }
                }
                let exit = meta?["exitCode"] as? Int ?? 0
                let isError = block["is_error"] as? Bool ?? (exit != 0)
                finishTool(.qoder, id: id, output: output, failed: isError)
            }
            tick &+= 1
        case "result":
            guard running.contains(.qoder) else { return }
            let result = event["result"] as? String ?? ""
            let failed = event["is_error"] as? Bool ?? false
            if failed {
                let messages = (event["errors"] as? [String]) ?? []
                let detail = messages.first ?? (result.isEmpty ? "Qoder returned an error." : result)
                var list = transcripts[.qoder] ?? []
                if let index = assistantIndex(.qoder), list.indices.contains(index) {
                    list[index].error = detail
                } else {
                    list.append(AgentMessage(role: .system, text: detail, error: detail))
                }
                transcripts[.qoder] = list
                finish(.qoder)
                return
            }
            if !result.isEmpty, (transcripts[.qoder]?.last?.text ?? "").isEmpty {
                if qoderAssistant == nil {
                    var list = transcripts[.qoder] ?? []
                    list.append(AgentMessage(role: .assistant, text: result))
                    transcripts[.qoder] = list
                    qoderAssistant = list.last?.id
                } else {
                    setAssistantText(.qoder, result)
                }
            }
            if let denials = event["permission_denials"] as? [[String: Any]], !denials.isEmpty {
                appendSystem(.qoder, "\(denials.count) action\(denials.count == 1 ? "" : "s") denied by the current permission mode.")
            }
            if stopRequested {
                appendSystem(.qoder, "Stopped.")
            }
            finish(.qoder)
        default:
            break
        }
    }

    private func qoderExited(code: Int32, message: String) {
        guard running.contains(.qoder) else {
            if code != 0, !message.isEmpty {
                appendSystem(.qoder, "Qoder exited: \(message)")
            }
            return
        }
        let detail = message.isEmpty ? "Exit code \(code)" : message
        fail(.qoder, "Qoder stopped: \(detail)")
    }

    // MARK: opencode

    private func connectOpenCode(force: Bool = false) {
        if !force, status[.opencode] == .ready { return }
        if ocConnecting, !force { return }
        ocStream?.stop()
        ocStream = nil
        ocRetry?.cancel()
        ocBase = nil
        ocConnecting = true
        status[.opencode] = .connecting
        tick &+= 1

        Task {
            do {
                let base = try opencode.baseURL(from: settings.opencodeBaseURL)
                try await ensureServer(base: base)
                self.ocBase = base
                self.status[.opencode] = .ready
                self.ocConnecting = false
                self.startStream(base: base)
                if self.kind == .opencode, self.running.contains(.opencode) { self.refreshNotch() }
            } catch {
                self.ocConnecting = false
                self.status[.opencode] = .error(error.localizedDescription)
                if self.running.contains(.opencode) { self.fail(.opencode, error.localizedDescription) }
            }
            self.tick &+= 1
        }
    }

    private func ensureServer(base: URL) async throws {
        if await opencode.isHealthy(base: base) { return }
        guard settings.agentAutoStart else {
            throw AgentError.message("OpenCode isn't running at \(base.absoluteString). Start it with `opencode serve` or enable auto-start.")
        }
        guard let binary = OpenCodeConnection.locate() else {
            throw AgentError.message("OpenCode CLI not found. Install it with `npm i -g opencode-ai`, then start `opencode serve`.")
        }
        if ocServer?.isRunning != true {
            let process = Process()
            process.executableURL = binary
            process.arguments = ["serve", "--port", "\(base.port ?? 4096)"]
            process.currentDirectoryURL = URL(fileURLWithPath: workDir)
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.environment = {
                var env = ProcessInfo.processInfo.environment
                let path = env["PATH"] ?? ""
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + path
                return env
            }()
            try process.run()
            ocServer = process
        }
        for _ in 0..<40 {
            if await opencode.isHealthy(base: base) { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        throw AgentError.message("OpenCode server did not start. Open a terminal, run `opencode serve`, and retry.")
    }

    private func startStream(base: URL) {
        if QoderProcess.debug { print("OC stream start \(base.absoluteString)") }
        ocStream?.stop()
        let stream = OpenCodeStream()
        stream.onEvent = { [weak self] object in
            DispatchQueue.main.async { self?.handleOpenCodeObject(object) }
        }
        stream.onFailure = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.ocBase == base else { return }
                self.ocRetry?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.ocBase == base else { return }
                    self.startStream(base: base)
                }
                self.ocRetry = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
            }
        }
        ocStream = stream
        stream.start(base: base)
    }

    private func handleOpenCodeObject(_ object: [String: Any]) {
        let type = object["type"] as? String ?? ""
        let props = object["properties"] as? [String: Any] ?? [:]
        if QoderProcess.debug, type.hasPrefix("message") || type.hasPrefix("session") || type.hasPrefix("permission") || type == "server.connected" {
            print("OC event \(type) sid=\(props["sessionID"] as? String ?? "-") ours=\(sessions[.opencode] ?? "-")")
        }
        handleOpenCode(type: type, props: props)
    }

    private func handleOpenCode(type: String, props: [String: Any]) {
        if let sid = props["sessionID"] as? String, !sid.isEmpty {
            guard sid == sessions[.opencode] else { return }
        }

        switch type {
        case "message.updated":
            guard let info = props["info"] as? [String: Any],
                  let id = info["id"] as? String,
                  let role = info["role"] as? String else { return }
            ocRoles[id] = role
            guard role == "assistant", ocMessageIndex[id] == nil, running.contains(.opencode) else { return }
            var list = transcripts[.opencode] ?? []
            if let pending = ocPendingAssistant,
               let index = list.lastIndex(where: { $0.id == pending }) {
                ocMessageIndex[id] = index
                ocPendingAssistant = nil
                tick &+= 1
                return
            }
            list.append(AgentMessage(role: .assistant))
            transcripts[.opencode] = list
            ocMessageIndex[id] = list.count - 1
            ocLastAssistant = list.last?.id
            tick &+= 1
        case "message.part.updated":
            guard let part = props["part"] as? [String: Any],
                  let messageID = part["messageID"] as? String else { return }
            let role = ocRoles[messageID] ?? "assistant"
            let partType = part["type"] as? String ?? ""
            switch partType {
            case "text":
                guard role == "assistant" else { return }
                let text = part["text"] as? String ?? ""
                if let index = ocMessageIndex[messageID] {
                    var list = transcripts[.opencode] ?? []
                    guard list.indices.contains(index) else { return }
                    list[index].text = text
                    transcripts[.opencode] = list
                    tick &+= 1
                }
                activity[.opencode] = "Writing…"
                refreshNotch()
            case "reasoning":
                activity[.opencode] = "Thinking…"
                refreshNotch()
            case "tool":
                let callID = part["callID"] as? String ?? part["id"] as? String ?? UUID().uuidString
                let name = part["tool"] as? String ?? "Tool"
                let state = part["state"] as? [String: Any] ?? [:]
                let input = state["input"] as? [String: Any] ?? [:]
                let title = state["title"] as? String ?? ""
                let detail = QoderProcess.toolDetail(name: name, input: input, fallback: title)
                let status = state["status"] as? String ?? "running"
                if ocToolIndex[callID] == nil {
                    addOC(callID: callID, name: name, detail: detail)
                } else if !detail.isEmpty {
                    setToolMeta(.opencode, id: callID, name: name, detail: detail)
                }
                if let output = Self.toolOutput(state: state), !output.isEmpty {
                    if status == "completed" || status == "error" || status == "failed" {
                        finishTool(.opencode, id: callID, output: output, failed: status == "error" || status == "failed")
                    } else {
                        setToolOutput(.opencode, id: callID, output: output)
                    }
                } else if status == "completed" || status == "error" {
                    finishTool(.opencode, id: callID, output: "", failed: status == "error")
                }
                activity[.opencode] = detail.isEmpty ? name : "\(name) · \(detail)"
                refreshNotch()
            default:
                break
            }
        case "session.status":
            if let status = props["status"] as? [String: Any], status["type"] as? String == "idle" {
                finish(.opencode)
            }
        case "session.idle":
            finish(.opencode)
        case "session.error":
            let error = props["error"] as? [String: Any] ?? [:]
            let data = error["data"] as? [String: Any] ?? [:]
            let message = data["message"] as? String ?? error["name"] as? String ?? "OpenCode error"
            fail(.opencode, message)
        case "permission.updated", "permission.asked", "permission.v2.asked":
            guard running.contains(.opencode) else { return }
            let id = props["id"] as? String ?? props["requestID"] as? String ?? ""
            guard !id.isEmpty else { return }
            let raw = props["permission"] as? String ?? props["action"] as? String ?? ""
            let title = props["title"] as? String ?? Self.permissionTitle(raw)
            let detail = Self.permissionDetail(props)
            approval = AgentApproval(agent: .opencode, serverID: id, title: title, detail: detail)
            activity[.opencode] = "Waiting for approval"
            refreshNotch()
            tick &+= 1
        case "permission.replied", "permission.v2.replied":
            approval = nil
            if running.contains(.opencode) {
                activity[.opencode] = "Thinking…"
                refreshNotch()
            }
        default:
            break
        }
    }

    private func sendOpenCode(_ text: String) {
        running.insert(.opencode)
        activity[.opencode] = "Thinking…"
        var list = transcripts[.opencode] ?? []
        let pending = AgentMessage(role: .assistant)
        list.append(pending)
        transcripts[.opencode] = list
        ocPendingAssistant = pending.id
        ocLastAssistant = pending.id
        refreshNotch()
        tick &+= 1
        Task {
            do {
                let base = try await readyBase()
                let sid = try await ensureSession(base: base)
                var body: [String: Any] = [
                    "parts": [["type": "text", "text": text]]
                ]
                if let model = Self.model(settings.opencodeModel) { body["model"] = model }
                sessions[.opencode] = sid
                status[.opencode] = .ready
                _ = try await opencode.post("/session/\(sid)/prompt_async",
                                            query: ["directory": workDir],
                                            body: body)
                tick &+= 1
            } catch {
                self.fail(.opencode, error.localizedDescription)
            }
        }
    }

    private func readyBase() async throws -> URL {
        if let base = ocBase, status[.opencode] == .ready { return base }
        connectOpenCode()
        for _ in 0..<80 {
            try? await Task.sleep(nanoseconds: 125_000_000)
            if let base = ocBase, status[.opencode] == .ready { return base }
            if case .error(let message) = status[.opencode] { throw AgentError.message(message) }
        }
        throw AgentError.message("OpenCode didn't become ready. Check the server and its model.")
    }

    private func ensureSession(base: URL) async throws -> String {
        if let existing = sessions[.opencode] { return existing }
        let data = try await opencode.post("/session",
                                           query: ["directory": workDir],
                                           body: ["title": "Nook"])
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String else {
            throw AgentError.message("OpenCode did not return a session")
        }
        sessions[.opencode] = id
        return id
    }

    // MARK: transcript helpers

    private func appendAssistantText(_ kind: AgentKind, _ text: String, separator: String) {
        var list = transcripts[kind] ?? []
        guard let index = assistantIndex(kind), list.indices.contains(index) else {
            list.append(AgentMessage(role: .assistant, text: text))
            transcripts[kind] = list
            if kind == .qoder { qoderAssistant = list.last?.id }
            return
        }
        if list[index].text.isEmpty {
            list[index].text = text
        } else if !list[index].text.hasSuffix(text) {
            list[index].text += separator + text
        }
        transcripts[kind] = list
        tick &+= 1
    }

    private func setAssistantText(_ kind: AgentKind, _ text: String) {
        guard let index = assistantIndex(kind) else { return }
        var list = transcripts[kind] ?? []
        guard list.indices.contains(index) else { return }
        list[index].text = text
        transcripts[kind] = list
        tick &+= 1
    }

    private func assistantIndex(_ kind: AgentKind) -> Int? {
        let list = transcripts[kind] ?? []
        if kind == .qoder {
            guard let id = qoderAssistant else { return nil }
            return list.lastIndex(where: { $0.id == id })
        }
        guard let id = ocLastAssistant else { return nil }
        return list.lastIndex(where: { $0.id == id })
    }

    private func addTool(_ kind: AgentKind, id: String, name: String, detail: String) {
        guard let index = assistantIndex(kind) else { return }
        var list = transcripts[kind] ?? []
        guard list.indices.contains(index) else { return }
        if list[index].tools.contains(where: { $0.id == id }) { return }
        list[index].tools.append(AgentTool(id: id, name: name, detail: detail))
        transcripts[kind] = list
        if kind == .opencode { ocToolIndex[id] = index }
        tick &+= 1
    }

    private func addOC(callID: String, name: String, detail: String) {
        var list = transcripts[.opencode] ?? []
        var index: Int?
        if let last = ocLastAssistant { index = list.lastIndex(where: { $0.id == last }) }
        guard let index, list.indices.contains(index) else { return }
        if list[index].tools.contains(where: { $0.id == callID }) { return }
        list[index].tools.append(AgentTool(id: callID, name: name, detail: detail))
        transcripts[.opencode] = list
        ocToolIndex[callID] = index
        tick &+= 1
    }

    private func setToolMeta(_ kind: AgentKind, id: String, name: String, detail: String) {
        var list = transcripts[kind] ?? []
        for messageIndex in list.indices {
            if let toolIndex = list[messageIndex].tools.firstIndex(where: { $0.id == id }) {
                var changed = false
                if !name.isEmpty, list[messageIndex].tools[toolIndex].name != name {
                    list[messageIndex].tools[toolIndex].name = name
                    changed = true
                }
                if list[messageIndex].tools[toolIndex].detail != detail {
                    list[messageIndex].tools[toolIndex].detail = detail
                    changed = true
                }
                if changed {
                    transcripts[kind] = list
                    tick &+= 1
                }
                return
            }
        }
    }

    private func setToolOutput(_ kind: AgentKind, id: String, output: String) {
        var list = transcripts[kind] ?? []
        for messageIndex in list.indices {
            if let toolIndex = list[messageIndex].tools.firstIndex(where: { $0.id == id }) {
                list[messageIndex].tools[toolIndex].output = String(output.prefix(12_000))
                transcripts[kind] = list
                tick &+= 1
                return
            }
        }
    }

    private func finishTool(_ kind: AgentKind, id: String, output: String, failed: Bool) {
        var list = transcripts[kind] ?? []
        for messageIndex in list.indices {
            if let toolIndex = list[messageIndex].tools.firstIndex(where: { $0.id == id }) {
                list[messageIndex].tools[toolIndex].output = String(output.prefix(12_000))
                list[messageIndex].tools[toolIndex].status = failed ? .failed : .done
                transcripts[kind] = list
                tick &+= 1
                return
            }
        }
    }

    private func appendSystem(_ kind: AgentKind, _ text: String) {
        var list = transcripts[kind] ?? []
        list.append(AgentMessage(role: .system, text: text))
        transcripts[kind] = list
        tick &+= 1
    }

    // MARK: completion

    private func finish(_ kind: AgentKind) {
        guard running.remove(kind) != nil else { return }
        activity[kind] = nil
        approval = nil
        if kind == .opencode { ocPendingAssistant = nil }
        tick &+= 1
        refreshNotch()
        if stopRequested { stopRequested = false }
        if !NotchController.shared.state.expanded {
            NotchController.shared.show(hud: HUDMessage(symbol: kind.symbol,
                                                       title: "\(kind.title) finished",
                                                       detail: nil, progress: nil))
        }
    }

    private func fail(_ kind: AgentKind, _ message: String) {
        let trimmed = message.count > 800 ? String(message.prefix(800)) + "…" : message
        var list = transcripts[kind] ?? []
        if let index = assistantIndex(kind), list.indices.contains(index), list[index].text.isEmpty {
            list[index].error = trimmed
        } else {
            list.append(AgentMessage(role: .system, text: trimmed, error: trimmed))
        }
        transcripts[kind] = list
        status[kind] = kind == .opencode ? .error(message) : .ready
        running.remove(kind)
        activity[kind] = nil
        tick &+= 1
        refreshNotch()
    }

    private func refreshNotch() {
        if let agent = AgentKind.allCases.first(where: { running.contains($0) }) {
            let text = activity[agent] ?? ""
            NotchController.shared.setActivity(.init(kind: .agent,
                                                     symbol: agent.symbol,
                                                     text: agent.title,
                                                     detail: text.isEmpty ? "Working" : text,
                                                     progress: nil))
        } else {
            NotchController.shared.clearActivity(.agent)
        }
    }

    // MARK: parsing helpers

    private static func text(from value: Any?) -> String {
        if let string = value as? String { return string }
        if let blocks = value as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }

    private static func model(_ raw: String) -> [String: Any]? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let pieces = value.split(separator: "/", maxSplits: 1).map(String.init)
        if pieces.count == 2 { return ["providerID": pieces[0], "modelID": pieces[1]] }
        return ["modelID": value]
    }

    private static func toolOutput(state: [String: Any]) -> String? {
        if let output = state["output"] as? String, !output.isEmpty { return output }
        if let metadata = state["metadata"] as? [String: Any] {
            if let output = metadata["output"] as? String, !output.isEmpty { return output }
            if let diff = metadata["diff"] as? String, !diff.isEmpty { return diff }
        }
        return nil
    }

    private static func permissionTitle(_ raw: String) -> String {
        switch raw.lowercased() {
        case "": return "Permission requested"
        case "bash", "shell": return "Run a command"
        case "edit", "write": return "Edit a file"
        case "read": return "Read a file"
        case "webfetch", "websearch": return "Use the web"
        case "task": return "Start a subtask"
        case "external_directory": return "Access another folder"
        default: return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    private static func permissionDetail(_ props: [String: Any]) -> String {
        if let metadata = props["metadata"] as? [String: Any] {
            for key in ["command", "filePath", "path", "pattern", "url", "description"] {
                if let value = metadata[key] as? String, !value.isEmpty { return value }
            }
            if let raw = metadata["diff"] as? String, !raw.isEmpty { return String(raw.prefix(400)) }
        }
        let patterns = (props["patterns"] as? [String]) ?? (props["resources"] as? [String]) ?? []
        if !patterns.isEmpty { return patterns.joined(separator: ", ") }
        if let detail = props["detail"] as? String { return detail }
        return "Review this request before OpenCode continues."
    }
}

enum AgentError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

// MARK: - qoder process

final class QoderProcess {
    static let debug = ProcessInfo.processInfo.environment["NOOK_AGENT_DEBUG"] == "1"
    private var process: Process?
    private var stdin: Pipe?
    private var buffer = Data()
    private var stderr = ""
    private var intentional = false
    private let queue = DispatchQueue(label: "com.nook.qoder")
    private var onEvent: (([String: Any]) -> Void)?
    private var onExit: ((Int32, String) -> Void)?
    private var sessionID = ""

    static func locate() -> URL? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/qodercli",
            "\(home)/.qoder/bin/qodercli/qodercli",
            "/opt/homebrew/bin/qodercli",
            "/usr/local/bin/qodercli"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    var isRunning: Bool { process?.isRunning ?? false }

    func start(cwd: String,
               permissionMode: String,
               model: String,
               resume: String?,
               onEvent: @escaping ([String: Any]) -> Void,
               onExit: @escaping (Int32, String) -> Void) throws {
        guard let binary = Self.locate() else { throw AgentError.message("Qoder CLI not found") }
        finish()
        intentional = false
        stderr = ""
        buffer = Data()
        sessionID = resume ?? ""
        self.onEvent = onEvent
        self.onExit = onExit

        let process = Process()
        process.executableURL = binary
        var arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--cwd", cwd]
        if !permissionMode.isEmpty { arguments += ["--permission-mode", permissionMode] }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty { arguments += ["--model", trimmedModel] }
        if let resume, !resume.isEmpty { arguments += ["-r", resume] }
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.environment = {
            var env = ProcessInfo.processInfo.environment
            // Qoder Desktop exports partial SDK variables into agent shells. A
            // standalone CLI needs to use its normal login instead.
            env = env.filter { key, _ in
                !key.hasPrefix("QODER") && !key.hasPrefix("CLAUDE_CODE")
            }
            let path = env["PATH"] ?? ""
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + path
            env["HOME"] = NSHomeDirectory()
            env["TERM"] = env["TERM"] ?? "xterm-256color"
            return env
        }()

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            if QoderProcess.debug { print("QODER stderr: \(text)") }
            self?.queue.async {
                guard let self else { return }
                self.stderr = String((self.stderr + text).suffix(2_000))
            }
        }

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            if QoderProcess.debug { print("QODER exited: \(proc.terminationStatus) stderr=\(self.stderr)") }
            self.queue.async {
                let intentional = self.intentional
                let message = String(self.stderr.suffix(600)).trimmingCharacters(in: .whitespacesAndNewlines)
                self.process = nil
                if !intentional {
                    DispatchQueue.main.async { self.onExit?(proc.terminationStatus, message) }
                }
            }
        }

        try process.run()
        self.process = process
        self.stdin = input
        if Self.debug { print("QODER: started \(arguments.joined(separator: " "))") }
    }

    func send(_ text: String) throws {
        guard let stdin, let process, process.isRunning else {
            throw AgentError.message("Qoder process is not running")
        }
        let payload: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": [["type": "text", "text": text]]],
            "parent_tool_use_id": NSNull(),
            "session_id": sessionID
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        stdin.fileHandleForWriting.write(data)
        stdin.fileHandleForWriting.write(Data([0x0A]))
    }

    func finish() {
        guard let process else { return }
        intentional = true
        process.terminationHandler = nil
        if process.isRunning { process.terminate() }
        self.process = nil
        stdin = nil
    }

    private func consume(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            self.buffer.append(data)
            while let newline = self.buffer.firstIndex(of: 0x0A) {
                let line = self.buffer[..<newline]
                self.buffer.removeSubrange(...newline)
                if QoderProcess.debug { print("QODER raw: \(String(data: Data(line), encoding: .utf8) ?? "")") }
                guard !line.isEmpty,
                      let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
                if let sid = object["session_id"] as? String, !sid.isEmpty {
                    self.sessionID = sid
                }
                let event = object
                DispatchQueue.main.async { self.onEvent?(event) }
            }
        }
    }

    static func toolDetail(name: String, input: [String: Any], fallback: String = "") -> String {
        let keys: [String]
        switch name.lowercased() {
        case "bash", "shell": keys = ["command", "description"]
        case "edit", "write", "multiedit", "read": keys = ["file_path", "path", "filePath"]
        case "glob": keys = ["pattern", "path"]
        case "grep": keys = ["pattern", "path"]
        case "webfetch": keys = ["url"]
        case "task": keys = ["description", "prompt"]
        default: keys = ["command", "file_path", "path", "pattern", "url", "query", "description"]
        }
        for key in keys {
            if let value = input[key] as? String, !value.isEmpty {
                return value.count > 140 ? String(value.prefix(137)) + "…" : value
            }
        }
        if !fallback.isEmpty { return fallback }
        for (_, value) in input {
            if let text = value as? String, !text.isEmpty {
                return text.count > 140 ? String(text.prefix(137)) + "…" : text
            }
        }
        return ""
    }
}

// MARK: - opencode http

final class OpenCodeConnection {
    private var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }

    static func locate() -> URL? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.opencode/bin/opencode",
            "\(home)/.local/bin/opencode",
            "/opt/homebrew/bin/opencode",
            "/usr/local/bin/opencode",
            "\(home)/.bun/bin/opencode"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    func baseURL(from raw: String) throws -> URL {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { value = "http://127.0.0.1:4096" }
        if !value.contains("://") { value = "http://" + value }
        guard let url = URL(string: value), url.host != nil else {
            throw AgentError.message("Invalid OpenCode server address")
        }
        return url
    }

    func isHealthy(base: URL) async -> Bool {
        var request = URLRequest(url: base.appendingPathComponent("config"))
        request.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse).map { (200..<500).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }

    func post(_ path: String, query: [String: String]?, body: [String: Any]?) async throws -> Data {
        guard var components = URLComponents(url: try baseFromSettings(), resolvingAgainstBaseURL: false) else {
            throw AgentError.message("Invalid OpenCode server address")
        }
        components.path = path
        if let query, !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw AgentError.message("Invalid OpenCode address") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else {
            request.httpBody = Data("{}".utf8)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentError.message("OpenCode did not respond")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw AgentError.message("OpenCode \(http.statusCode): \(text.prefix(300))")
        }
        return data
    }

    private func baseFromSettings() throws -> URL {
        var value = AppSettings.shared.opencodeBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { value = "http://127.0.0.1:4096" }
        if !value.contains("://") { value = "http://" + value }
        guard let url = URL(string: value) else { throw AgentError.message("Invalid OpenCode server address") }
        return url
    }
}

// MARK: - opencode event stream

final class OpenCodeStream: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var pending: [String] = []
    private var buffer = Data()
    private var failed = false

    var onEvent: (([String: Any]) -> Void)?
    var onFailure: (() -> Void)?

    func start(base: URL) {
        stop()
        failed = false
        pending = []
        buffer = Data()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60 * 60
        config.timeoutIntervalForResource = 60 * 60 * 24
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: base.appendingPathComponent("event"))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func stop() {
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            completionHandler(.cancel)
            reportFailure()
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
            } else if trimmed.hasPrefix("data:") {
                pending.append(String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil, !failed { reportFailure() }
    }

    private func flush() {
        guard !pending.isEmpty else { return }
        let payload = pending.joined(separator: "\n")
        pending = []
        guard let raw = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return }
        onEvent?(object)
    }

    private func reportFailure() {
        guard !failed else { return }
        failed = true
        onFailure?()
    }
}
