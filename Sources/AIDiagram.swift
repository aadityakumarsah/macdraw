import AppKit
import SwiftUI
import Security

// Native text-to-diagram drawer. Its interaction model is inspired by the
// MIT-licensed Excalidraw TTD dialog (chat, preview, then explicit insert),
// but the UI and scene conversion below are Macdraw implementations.

enum AIProvider: String, CaseIterable, Identifiable {
    case openAI = "OpenAI / Codex"
    case anthropic = "Anthropic / Claude"
    case openRouter = "OpenRouter"
    case custom = "OpenAI-compatible"
    case local = "Local (Ollama)"
    var id: String { rawValue }
    var defaultEndpoint: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .custom: return ""
        case .local: return "http://127.0.0.1:11434/v1"
        }
    }
    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4.1-mini"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .openRouter: return "openai/gpt-4.1-mini"
        case .custom: return ""
        case .local: return "llama3.2"
        }
    }
}

struct DiagramNode: Codable, Identifiable {
    var id: String
    var label: String
    var kind: String = "process"
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat = 150
    var height: CGFloat = 64
}
struct DiagramEdge: Codable, Identifiable {
    var id: String
    var from: String
    var to: String
    var label: String? = nil
    var style: String = "curved"
}
struct DiagramSpec: Codable {
    var title: String? = nil
    var nodes: [DiagramNode]
    var edges: [DiagramEdge]
}

final class AISettings: ObservableObject {
    @Published var provider: AIProvider { didSet { saveNonSecret() } }
    @Published var endpoint: String { didSet { saveNonSecret() } }
    @Published var model: String { didSet { saveNonSecret() } }
    @Published var apiKey: String { didSet { KeychainStore.set(apiKey, account: "ai.apiKey") } }
    @Published var testStatus = "Not tested"
    init() {
        let d = UserDefaults.standard
        let savedProvider = AIProvider(rawValue: d.string(forKey: "ai.provider") ?? "") ?? .local
        provider = savedProvider
        endpoint = d.string(forKey: "ai.endpoint") ?? savedProvider.defaultEndpoint
        model = d.string(forKey: "ai.model") ?? savedProvider.defaultModel
        apiKey = KeychainStore.get(account: "ai.apiKey") ?? ""
    }
    func useProviderDefaults() { endpoint = provider.defaultEndpoint; model = provider.defaultModel }
    private func saveNonSecret() {
        let d = UserDefaults.standard
        d.set(provider.rawValue, forKey: "ai.provider")
        d.set(endpoint, forKey: "ai.endpoint")
        d.set(model, forKey: "ai.model")
    }
}

enum KeychainStore {
    static func get(account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.local.macdraw", kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func set(_ value: String, account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.local.macdraw", kSecAttrAccount as String: account]
        if value.isEmpty { SecItemDelete(base as CFDictionary); return }
        let attrs = [kSecValueData as String: Data(value.utf8)]
        if SecItemUpdate(base as CFDictionary, attrs as CFDictionary) != errSecSuccess {
            var add = base; add[kSecValueData as String] = Data(value.utf8); SecItemAdd(add as CFDictionary, nil)
        }
    }
}

/// Installs Ollama through the user's Homebrew setup when needed and pulls the
/// selected model. The model stays local; Macdraw only talks to its localhost
/// OpenAI-compatible endpoint afterward.
enum LocalModelRuntime {
    private static var server: Process?

    static func setUp(model: String) async throws {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw NSError(domain: "MacdrawAI", code: 20, userInfo: [NSLocalizedDescriptionKey: "Enter a local model name first."])
        }
        if try await run("/usr/bin/which", ["ollama"]).status != 0 {
            let install = try await run("/usr/bin/env", ["brew", "install", "ollama"])
            guard install.status == 0 else { throw failure("Ollama installation", install) }
        }
        if server?.isRunning != true {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["ollama", "serve"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            server = process
            try await Task.sleep(for: .milliseconds(500))
        }
        let pull = try await run("/usr/bin/env", ["ollama", "pull", model])
        guard pull.status == 0 else { throw failure("Model download", pull) }
    }

    private static func failure(_ action: String, _ result: (status: Int32, output: String)) -> NSError {
        NSError(domain: "MacdrawAI", code: Int(result.status), userInfo: [NSLocalizedDescriptionKey: "\(action) failed: \(result.output.prefix(280))"])
    }

    private static func run(_ executable: String, _ arguments: [String]) async throws -> (status: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { task in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (task.terminationStatus, String(data: data, encoding: .utf8) ?? "Unknown error"))
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

@MainActor enum DiagramAI {
    static let systemPrompt = """
    Convert the request into an editable diagram. Return ONLY valid JSON: {"title":"", "nodes":[{"id":"n1","label":"short label","kind":"start|end|decision|input|process|database","x":0,"y":0,"width":150,"height":64}],"edges":[{"id":"e1","from":"n1","to":"n2","label":"optional","style":"curved|orthogonal|straight"}]}. Use a readable left-to-right or top-to-bottom layout. Every edge must refer to a node id. Keep labels concise.
    """
    static func generate(prompt: String, settings: AISettings) async throws -> DiagramSpec {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NSError(domain: "MacdrawAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Describe the diagram first."]) }
        if settings.provider == .local && settings.endpoint.isEmpty { throw NSError(domain: "MacdrawAI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Set the local Ollama endpoint."]) }
        if settings.provider != .local && settings.apiKey.isEmpty { throw NSError(domain: "MacdrawAI", code: 3, userInfo: [NSLocalizedDescriptionKey: "Add an API key in Settings."]) }
        let content = try await request(prompt: prompt, settings: settings)
        return try decode(content)
    }
    static func test(settings: AISettings) async -> String {
        do {
            if settings.provider == .local {
                let endpoint = settings.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard let url = URL(string: endpoint + "/models") else { return "The endpoint URL is invalid." }
                var request = URLRequest(url: url)
                request.timeoutInterval = 8
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    return "Ollama is not responding at \(endpoint)."
                }
                let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let models = payload?["models"] as? [[String: Any]] ?? []
                let wanted = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
                let available = models.compactMap { $0["name"] as? String }
                if !wanted.isEmpty && !available.contains(where: { $0 == wanted || $0.hasPrefix(wanted + ":") }) {
                    return "Ollama connected, but \(wanted) is not downloaded yet."
                }
                return "Connected (Ollama)"
            }
            if settings.provider != .anthropic {
                return await healthCheck(settings: settings)
            }
            _ = try await request(prompt: "Return an empty diagram.", settings: settings, maxTokens: 40)
            return "Connected"
        } catch { return error.localizedDescription }
    }

    private static func healthCheck(settings: AISettings) async -> String {
        let endpoint = settings.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: endpoint + "/models") else { return "The endpoint URL is invalid." }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !settings.apiKey.isEmpty { request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "No response from provider." }
            guard (200..<300).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? "Unknown error"
                return "Provider returned \(http.statusCode): \(text.prefix(180))"
            }
            return "Connected (API key accepted)"
        } catch { return error.localizedDescription }
    }
    private static func request(prompt: String, settings: AISettings, maxTokens: Int = 1400) async throws -> String {
        let endpoint = settings.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString: String
        var body: [String: Any]
        var headers = ["Content-Type": "application/json"]
        if settings.provider == .anthropic {
            urlString = endpoint + "/messages"
            headers["x-api-key"] = settings.apiKey; headers["anthropic-version"] = "2023-06-01"
            body = ["model": settings.model, "max_tokens": maxTokens, "system": systemPrompt, "messages": [["role": "user", "content": prompt]]]
        } else {
            urlString = endpoint + "/chat/completions"
            if !settings.apiKey.isEmpty { headers["Authorization"] = "Bearer \(settings.apiKey)" }
            body = ["model": settings.model, "temperature": 0.2, "response_format": ["type": "json_object"], "max_tokens": maxTokens, "messages": [["role": "system", "content": systemPrompt], ["role": "user", "content": prompt]]]
        }
        guard let url = URL(string: urlString) else { throw NSError(domain: "MacdrawAI", code: 4, userInfo: [NSLocalizedDescriptionKey: "The endpoint URL is invalid."]) }
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 35
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NSError(domain: "MacdrawAI", code: 5, userInfo: [NSLocalizedDescriptionKey: "No response from provider."]) }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "MacdrawAI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Provider returned \(http.statusCode): \(text.prefix(240))"])
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if settings.provider == .anthropic, let blocks = json?["content"] as? [[String: Any]], let text = blocks.first?["text"] as? String { return text }
        if let choices = json?["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any], let text = message["content"] as? String { return text }
        throw NSError(domain: "MacdrawAI", code: 6, userInfo: [NSLocalizedDescriptionKey: "Provider did not return chat text."])
    }
    static func decode(_ text: String) throws -> DiagramSpec {
        let cleaned = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") else { throw NSError(domain: "MacdrawAI", code: 7, userInfo: [NSLocalizedDescriptionKey: "The model did not return a diagram JSON object."]) }
        let json = String(cleaned[start...end])
        let spec = try JSONDecoder().decode(DiagramSpec.self, from: Data(json.utf8))
        guard !spec.nodes.isEmpty else { throw NSError(domain: "MacdrawAI", code: 8, userInfo: [NSLocalizedDescriptionKey: "The generated diagram has no nodes."]) }
        return spec
    }
}

private struct AIChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let text: String
}

private struct AIChatBubble: View {
    let message: AIChatMessage
    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            if message.role == "assistant" { Image(systemName: "sparkles").foregroundStyle(.purple) }
            Text(message.text).font(.system(size: 11)).padding(.horizontal, 9).padding(.vertical, 7)
                .background(message.role == "user" ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            if message.role == "user" { Spacer(minLength: 24) }
        }
    }
}

struct AIDiagramDrawer: View {
    @ObservedObject var settings: AISettings
    let onInsert: (DiagramSpec) -> Void
    let onClose: () -> Void
    @State private var prompt = ""
    @State private var diagram: DiagramSpec?
    @State private var isGenerating = false
    @State private var error = ""
    @State private var settingsOpen = false
    @State private var messages: [AIChatMessage] = []
    var body: some View {
        VStack(spacing: 0) {
            HStack { Label("Text to diagram", systemImage: "sparkles").font(.system(size: 15, weight: .bold)); Spacer(); Button { settingsOpen.toggle() } label: { Image(systemName: "gearshape") }.buttonStyle(.plain); Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.plain) }.padding(14)
            Divider()
            if settingsOpen { AISettingsView(settings: settings) }
            ScrollView { VStack(alignment: .leading, spacing: 12) {
                Text("Describe a flowchart, architecture, or process. Review it before it reaches your canvas.").font(.system(size: 12)).foregroundStyle(.secondary)
                ForEach(messages) { message in AIChatBubble(message: message) }
                TextEditor(text: $prompt).font(.system(size: 13)).frame(height: 108).padding(7).background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                HStack { Button("Example") { prompt = "Create an onboarding flow: Start, create account, verify email, decision: verified?, dashboard or resend email." }.buttonStyle(.borderless); Spacer(); if !messages.isEmpty { Button("Clear chat") { messages.removeAll(); diagram = nil; error = "" }.buttonStyle(.borderless) }; Button { generate() } label: { Label(isGenerating ? "Generating…" : "Generate", systemImage: "arrow.up.circle.fill") }.disabled(isGenerating).buttonStyle(.borderedProminent) }
                if !error.isEmpty { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
                if let diagram { DiagramPreview(diagram: diagram).frame(height: 245).background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 10)); HStack { Text("\(diagram.nodes.count) objects · \(diagram.edges.count) editable connectors").font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); Button("Insert into canvas") { onInsert(diagram) }.buttonStyle(.borderedProminent) } }
            }.padding(14) }
        }.frame(width: 390, height: 520).background(.ultraThinMaterial)
    }
    private func generate() {
        let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { error = "Describe the diagram first."; return }
        let previous = diagram.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        let modelPrompt = previous.map { "Update this existing diagram according to the request. Preserve useful nodes and edges unless the request changes them. Existing JSON: \($0)\nRequest: \(request)" } ?? request
        messages.append(AIChatMessage(role: "user", text: request))
        prompt = ""
        isGenerating = true; error = ""
        Task {
            do {
                let output = try await DiagramAI.generate(prompt: modelPrompt, settings: settings)
                await MainActor.run { diagram = output; messages.append(AIChatMessage(role: "assistant", text: "Generated \(output.nodes.count) nodes and \(output.edges.count) connectors. Review the preview, then insert it into the canvas.")); isGenerating = false }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isGenerating = false }
            }
        }
    }
}

private struct AISettingsView: View {
    @ObservedObject var settings: AISettings
    @State private var testing = false
    @State private var installing = false
    @State private var setupStatus = ""
    var body: some View { VStack(alignment: .leading, spacing: 8) {
        Picker("Provider", selection: $settings.provider) { ForEach(AIProvider.allCases) { Text($0.rawValue).tag($0) } }.onChange(of: settings.provider) { _, _ in settings.useProviderDefaults() }
        TextField("Endpoint", text: $settings.endpoint).textFieldStyle(.roundedBorder)
        TextField("Model", text: $settings.model).textFieldStyle(.roundedBorder)
        if settings.provider != .local { SecureField("API key (stored in Keychain)", text: $settings.apiKey).textFieldStyle(.roundedBorder) }
        if settings.provider == .local {
            HStack(spacing: 8) {
                if installing { ProgressView().controlSize(.small) }
                Button(installing ? "Setting up…" : "Set up Ollama & pull model") {
                    installing = true
                    setupStatus = "Checking for Ollama…"
                    settings.testStatus = "Installing Ollama and downloading \(settings.model)…"
                    Task {
                        do {
                            await MainActor.run { setupStatus = "Starting local runtime and checking model…" }
                            try await LocalModelRuntime.setUp(model: settings.model)
                            await MainActor.run { setupStatus = "Testing local connection…" }
                            let status = await DiagramAI.test(settings: settings)
                            await MainActor.run { settings.testStatus = status; setupStatus = "Done"; installing = false }
                        } catch {
                            await MainActor.run { settings.testStatus = error.localizedDescription; setupStatus = "Setup failed"; installing = false }
                        }
                    }
                }.disabled(installing)
            }
            if installing || !setupStatus.isEmpty { Text(setupStatus).font(.system(size: 10)).foregroundStyle(.secondary) }
            Text("Uses local Ollama; setup installs it through Homebrew and pulls the selected model. Prompts never leave localhost.").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        HStack { Button(testing ? "Testing…" : "Test connection") { testing = true; Task { let status = await DiagramAI.test(settings: settings); await MainActor.run { settings.testStatus = status; testing = false } } }.disabled(testing); Text(settings.testStatus).font(.system(size: 11)).foregroundStyle(settings.testStatus == "Connected" ? .green : .secondary) }
        if settings.provider == .local { Text("Local mode uses Ollama. Install it once in Terminal: `brew install ollama`; then run `ollama serve` and `ollama pull \(settings.model.isEmpty ? "llama3.2" : settings.model)`.").font(.system(size: 10)).foregroundStyle(.secondary) }
    }.padding(14).background(Color.primary.opacity(0.05)) }
}

private struct DiagramPreview: View {
    let diagram: DiagramSpec
    private var bounds: CGRect { diagram.nodes.reduce(CGRect.null) { $0.union(CGRect(x: $1.x, y: $1.y, width: $1.width, height: $1.height)) } }
    var body: some View { GeometryReader { proxy in
        let scale = min((proxy.size.width - 20) / max(bounds.width, 1), (proxy.size.height - 20) / max(bounds.height, 1), 1)
        ZStack {
            ForEach(diagram.edges) { edge in
                if let a = diagram.nodes.first(where: { $0.id == edge.from }), let b = diagram.nodes.first(where: { $0.id == edge.to }) {
                    DiagramPreviewEdge(edge: edge, start: point(for: a, scale: scale), end: point(for: b, scale: scale))
                }
            }
            ForEach(diagram.nodes) { node in DiagramPreviewNode(node: node, rect: rect(for: node, scale: scale)) }
        }
    } }
    private func point(for node: DiagramNode, scale: CGFloat) -> CGPoint { CGPoint(x: (node.x + node.width / 2 - bounds.minX) * scale + 10, y: (node.y + node.height / 2 - bounds.minY) * scale + 10) }
    private func rect(for node: DiagramNode, scale: CGFloat) -> CGRect { CGRect(x: (node.x - bounds.minX) * scale + 10, y: (node.y - bounds.minY) * scale + 10, width: node.width * scale, height: node.height * scale) }
}

private struct DiagramPreviewEdge: View {
    let edge: DiagramEdge; let start: CGPoint; let end: CGPoint
    var body: some View { Path { path in
        path.move(to: start)
        if edge.style == "curved" { path.addCurve(to: end, control1: CGPoint(x: start.x + (end.x-start.x)*0.45, y: start.y), control2: CGPoint(x: start.x + (end.x-start.x)*0.55, y: end.y)) } else { path.addLine(to: end) }
    }.stroke(Color.accentColor, style: SwiftUI.StrokeStyle(lineWidth: 1.5, lineCap: .round)) }
}

private struct DiagramPreviewNode: View {
    let node: DiagramNode; let rect: CGRect
    var body: some View { ZStack { RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .windowBackgroundColor)).overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.accentColor, lineWidth: 1)); Text(node.label).font(.system(size: max(8, min(12, rect.height * 0.24)))).lineLimit(2).multilineTextAlignment(.center).padding(4) }.frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY) }
}
