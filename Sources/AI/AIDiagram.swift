import AppKit
import SwiftUI
import Security

// Native text-to-diagram drawer. Its interaction model is inspired by the
// MIT-licensed Excalidraw TTD dialog (chat, preview, then explicit insert),
// but the UI and scene conversion below are Macdraw implementations.

enum AIProvider: String, CaseIterable, Identifiable {
    case openAI = "OpenAI / Codex"
    case anthropic = "Anthropic / Claude"
    case grok = "xAI / Grok"
    case groq = "Groq"
    case openRouter = "OpenRouter"
    case gemini = "Google Gemini"
    case custom = "OpenAI-compatible"
    case local = "Local (Ollama)"
    var id: String { rawValue }
    var defaultEndpoint: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .grok: return "https://api.x.ai/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .custom: return ""
        case .local: return "http://127.0.0.1:11434/v1"
        }
    }

    /// Starting point only. Every provider here publishes a models endpoint,
    /// so the Model dropdown lists what the key can actually reach and the
    /// user picks from that instead of typing an id by hand.
    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4.1-mini"
        case .anthropic: return "claude-opus-5-5"
        case .grok: return ""
        case .groq: return ""
        case .openRouter: return "openai/gpt-4.1-mini"
        case .gemini: return "gemini-2.5-flash"
        case .custom: return ""
        case .local: return "llama3.2"
        }
    }

    /// Wire protocol, which is what the request/response code branches on.
    /// Grok, OpenRouter, Ollama and "OpenAI-compatible" all speak the OpenAI
    /// chat-completions shape, so they share one path.
    var wireFormat: AIWireFormat {
        switch self {
        case .anthropic: return .anthropicMessages
        case .gemini: return .geminiGenerateContent
        case .openAI, .grok, .groq, .openRouter, .custom, .local: return .openAIChat
        }
    }

    var keyHelpURL: String? {
        switch self {
        case .anthropic: return "https://platform.claude.com/settings/keys"
        case .grok: return "https://console.x.ai"
        case .groq: return "https://console.groq.com/keys"
        case .openAI: return "https://platform.openai.com/api-keys"
        case .openRouter: return "https://openrouter.ai/keys"
        case .gemini: return "https://aistudio.google.com/app/apikey"
        case .custom, .local: return nil
        }
    }
}

extension AIProvider {
    /// Which provider issued this API key, from its prefix.
    ///
    /// Every vendor prefixes its keys distinctly, so pasting one is enough to
    /// know where it belongs — the user should not have to find the right
    /// entry in a dropdown first. Returns nil when the prefix matches nothing
    /// known, in which case the current selection is left alone.
    ///
    /// Order matters: OpenRouter and Anthropic both start with "sk-", so the
    /// longer prefixes are tested before the bare one.
    static func detect(fromKey key: String) -> AIProvider? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return nil }
        let prefixes: [(String, AIProvider)] = [
            ("sk-ant-", .anthropic),
            ("sk-or-", .openRouter),
            ("xai-", .grok),
            ("gsk_", .groq),
            ("AIza", .gemini),
            ("sk-proj-", .openAI),
            ("sk-", .openAI),
        ]
        for (prefix, provider) in prefixes where trimmed.hasPrefix(prefix) {
            return provider
        }
        return nil
    }

    /// Human-readable note for the settings panel after a key is recognized.
    var keyRecognizedNote: String { "Recognized a \(rawValue) key — provider switched." }
}

/// The three request/response shapes macdraw speaks.
enum AIWireFormat {
    case anthropicMessages
    case openAIChat
    case geminiGenerateContent
}

struct DiagramNode: Codable, Identifiable {
    var id: String
    var label: String
    var kind: String = "process"
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat = 150
    var height: CGFloat = 64
    /// Optional SF Symbol name (e.g. "server.rack", "person.crop.circle",
    /// "brain", "doc.text") rendered as an icon above the label. Omit to draw
    /// a plain shape. When an icon is given, the node renders it prominently.
    var symbol: String? = nil
    /// When true, this node renders as a syntax-highlighted code block
    /// (monospaced text on a translucent background) instead of a shape.
    /// `label` holds the code content. Best for showing a code snippet inside
    /// an architecture or flow diagram.
    var code: Bool = false

    // Decoding is tolerant because the producer is a language model.
    //
    // Swift's synthesized decoder ignores property defaults, so `kind`,
    // `width`, `height` and `code` — every field with a default above — were
    // *required on the wire*. A model that left any of them out failed the
    // whole diagram with "The data couldn't be read because it is missing",
    // which is `DecodingError.keyNotFound` surfacing to the user.
    private enum CodingKeys: String, CodingKey {
        case id, label, kind, x, y, width, height, symbol, code
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Only id and label are genuinely needed to place a node.
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "process"
        x = (try? c.decode(CGFloat.self, forKey: .x)) ?? 0
        y = (try? c.decode(CGFloat.self, forKey: .y)) ?? 0
        width = (try? c.decode(CGFloat.self, forKey: .width)) ?? 150
        height = (try? c.decode(CGFloat.self, forKey: .height)) ?? 64
        symbol = try? c.decode(String.self, forKey: .symbol)
        code = (try? c.decode(Bool.self, forKey: .code)) ?? false
    }

    init(id: String, label: String, kind: String = "process",
         x: CGFloat, y: CGFloat, width: CGFloat = 150, height: CGFloat = 64,
         symbol: String? = nil, code: Bool = false) {
        self.id = id; self.label = label; self.kind = kind
        self.x = x; self.y = y; self.width = width; self.height = height
        self.symbol = symbol; self.code = code
    }
}
struct DiagramEdge: Codable, Identifiable {
    var id: String
    var from: String
    var to: String
    var label: String? = nil
    var style: String = "curved"
    /// Arrowhead on the start of the connector: "none" (default), "arrow",
    /// "triangle", "bar".
    var startArrow: String = "none"
    /// Arrowhead on the end of the connector: "arrow" (default), "none",
    /// "triangle", "bar".
    var endArrow: String = "arrow"

    // Tolerant for the same reason as `DiagramNode`: `style`, `startArrow`
    // and `endArrow` all have defaults the synthesized decoder ignores.
    private enum CodingKeys: String, CodingKey {
        case id, from, to, label, style, startArrow, endArrow
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        // An edge with no endpoints is meaningless; the validator drops it.
        from = (try? c.decode(String.self, forKey: .from)) ?? ""
        to = (try? c.decode(String.self, forKey: .to)) ?? ""
        label = try? c.decode(String.self, forKey: .label)
        style = (try? c.decode(String.self, forKey: .style)) ?? "curved"
        startArrow = (try? c.decode(String.self, forKey: .startArrow)) ?? "none"
        endArrow = (try? c.decode(String.self, forKey: .endArrow)) ?? "arrow"
    }

    init(id: String, from: String, to: String, label: String? = nil,
         style: String = "curved", startArrow: String = "none", endArrow: String = "arrow") {
        self.id = id; self.from = from; self.to = to; self.label = label
        self.style = style; self.startArrow = startArrow; self.endArrow = endArrow
    }
}
struct DiagramSpec: Codable {
    var title: String? = nil
    var nodes: [DiagramNode]
    var edges: [DiagramEdge]

    private enum CodingKeys: String, CodingKey { case title, nodes, edges }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try? c.decode(String.self, forKey: .title)
        nodes = (try? c.decode([DiagramNode].self, forKey: .nodes)) ?? []
        // A diagram of unconnected nodes is still a diagram; a missing
        // `edges` key should not throw the whole response away.
        edges = (try? c.decode([DiagramEdge].self, forKey: .edges)) ?? []
    }

    init(title: String? = nil, nodes: [DiagramNode], edges: [DiagramEdge]) {
        self.title = title; self.nodes = nodes; self.edges = edges
    }
}

/// Catalog of SF Symbols the AI may attach to nodes as icons/logos. These are
/// known-good on macOS 13+. Keeps the model from guessing invalid names.
enum AIIconCatalog {
    static let icons: [String] = [
        "person.crop.circle", "person.2", "person.3", "server.rack", "cpu",
        "memorychip", "internaldrive", "externaldrive", "network", "wifi",
        "globe", "cloud", "icloud", "cylinder.split.1x2", "cylinder",
        "bolt", "bolt.horizontal", "flame", "hammer", "wrench", "gearshape",
        "lock.shield", "shield", "key", "ladybug", "shield.lefthalf.filled",
        "checkmark.shield", "exclamationmark.triangle", "checkmark.circle",
        "xmark.circle", "exclamationmark.octagon", "info.circle",
        "lightbulb", "lightbulb.fill", "brain", "sparkles", "scope",
        "chart.bar.xaxis", "chart.line.uptrend.xyaxis", "function",
        "chevron.left.forwardslash.chevron.right", "curlybraces", "terminal",
        "square.stack.3d.up", "cube", "layers", "doc.text", "doc.plaintext",
        "doc.richtext", "folder", "folder.fill", "arrow.triangle.branch",
        "arrow.triangle.merge", "arrow.triangle.pull", "arrow.up.right",
        "arrow.down", "arrow.right", "envelope", "bubble.left",
        "bubble.left.and.bubble.right", "message", "bell", "phone", "video",
        "paperplane", "creditcard", "cart", "bag", "gift", "star", "heart",
        "camera", "photo", "movieclapper", "music.note", "clock", "calendar",
        "location", "map", "mappin", "car", "airplane", "bicycle", "tram",
        "banknote", "percent", "dollarsign", "eurosign", "stethoscope",
        "cross.case", "pill", "syringe", "fork.knife", "cup.and.saucer",
        "tortoise", "hare", "leaf", "drop", "snowflake", "sun.max", "moon",
        "exclamationmark.bubble", "questionmark.circle", "at", "app",
        "square.stack", "rectangle.3.group", "rectangle.grid.2x2",
        "square.grid.2x2", "arrow.triangle.2.circlepath", "repeat",
        "shuffle", "arrow.clockwise", "arrow.counterclockwise", "arrow.up",
        "arrow.up.circle", "play", "pause", "stop", "forward", "backward",
    ]
}

/// A small, deterministic hint the agent loop uses on later passes to fix
/// common structural mistakes the first generation tends to make.
enum AICritiqueRules {
    static let text = """
    Improve the diagram for correctness and clarity:
    - Every edge.from and edge.to must reference an actual node id.
    - Keep labels short; use an icon symbol on key nodes when it helps.
    - Use distinct `kind` values to show meaning (start/end, decision, input,
      process, database, etc.) and pick `style` (curved/orthogonal/straight)
      that reads clearly.
    - Remove duplicate or unreachable nodes; make the flow obvious.
    - Preserve the overall intent of the request. Do not invent unrelated steps.
    - Do not change the JSON schema.
    """
}

final class AISettings: ObservableObject {
    @Published var provider: AIProvider { didSet { saveNonSecret(); loadAPIKeyForCurrentProvider() } }
    @Published var endpoint: String { didSet { saveNonSecret(); invalidateTest() } }
    @Published var model: String { didSet { saveNonSecret(); invalidateTest() } }
    @Published var apiKey: String {
        didSet {
            if !ephemeral { KeychainStore.set(apiKey, account: Self.keychainAccount(for: provider)) }
            invalidateTest()
        }
    }
    @Published var testStatus = "Not tested"

    /// Output ceiling the provider reports for the selected model, when it
    /// reports one. Groq rejects a `max_tokens` above the model's own limit
    /// with a 400, so the request clamps to this.
    @Published var modelMaxOutput: Int?

    /// When true nothing is written to the Keychain or UserDefaults. Used by
    /// `--aitest`, so running a live provider check never leaves a test key
    /// or a changed provider behind in the real settings.
    private let ephemeral: Bool

    static func keychainAccount(for provider: AIProvider) -> String { "ai.apiKey." + provider.rawValue }

    /// In-memory settings for a one-off live check: nothing is read from or
    /// written to the user's stored configuration.
    init(ephemeralProvider: AIProvider, key: String) {
        ephemeral = true
        provider = ephemeralProvider
        endpoint = ephemeralProvider.defaultEndpoint
        model = ephemeralProvider.defaultModel
        apiKey = key
    }

    init() {
        ephemeral = false
        let d = UserDefaults.standard
        let savedProvider = AIProvider(rawValue: d.string(forKey: "ai.provider") ?? "") ?? .local
        provider = savedProvider
        endpoint = d.string(forKey: "ai.endpoint") ?? savedProvider.defaultEndpoint
        model = d.string(forKey: "ai.model") ?? savedProvider.defaultModel
        let providerKey = KeychainStore.get(account: Self.keychainAccount(for: savedProvider))
        let legacyKey = KeychainStore.get(account: "ai.apiKey")
        apiKey = providerKey ?? legacyKey ?? ""
        // Preserve existing installations: the old single key was most often
        // an OpenRouter key, so associate it with the provider selected by the
        // user instead of making them enter it again after upgrading.
        if providerKey == nil, let legacyKey { KeychainStore.set(legacyKey, account: Self.keychainAccount(for: savedProvider)) }
    }
    func useProviderDefaults() { endpoint = provider.defaultEndpoint; model = provider.defaultModel; loadAPIKeyForCurrentProvider() }

    /// Stores a key against whichever provider issued it.
    ///
    /// Returns the provider it was recognized as, or nil when the prefix is
    /// unknown — in which case the key is stored against the current
    /// selection, since a self-hosted or OpenAI-compatible endpoint can use
    /// any format.
    @discardableResult
    func adopt(pastedKey raw: String) -> AIProvider? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        guard let detected = AIProvider.detect(fromKey: key) else {
            apiKey = key
            return nil
        }
        if detected != provider {
            // Switching provider reloads that provider's stored key, so the
            // new key has to be written after the switch, not before.
            provider = detected
            endpoint = detected.defaultEndpoint
            model = detected.defaultModel
        }
        apiKey = key
        return detected
    }
    private func loadAPIKeyForCurrentProvider() {
        guard !ephemeral else { return }
        let key = KeychainStore.get(account: Self.keychainAccount(for: provider)) ?? ""
        if apiKey != key { apiKey = key }
    }
    private func invalidateTest() { if testStatus != "Not tested" { testStatus = "Not tested" } }
    private func saveNonSecret() {
        guard !ephemeral else { return }
        let d = UserDefaults.standard
        d.set(provider.rawValue, forKey: "ai.provider")
        d.set(endpoint, forKey: "ai.endpoint")
        d.set(model, forKey: "ai.model")
    }
}

/// Lists the models a provider will actually serve for the configured key, so
/// the Model field can be a dropdown instead of a free-text box the user has
/// to type an exact id into. Every supported provider publishes this; the
/// shapes differ, so each one is normalized to a plain list of ids here.
@MainActor
final class AIModelCatalog: ObservableObject {
    @Published private(set) var models: [String] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    /// Per-provider cache, so switching back and forth doesn't refetch.
    private var cache: [AIProvider: [ModelOption]] = [:]

    func models(for provider: AIProvider) -> [String] { (cache[provider] ?? []).map(\.id) }

    func options(for provider: AIProvider) -> [ModelOption] { cache[provider] ?? [] }

    func load(settings: AISettings, force: Bool = false) async {
        let provider = settings.provider
        if !force, let hit = cache[provider], !hit.isEmpty {
            models = hit.map(\.id)
            error = nil
            selectModelIfNeeded(settings: settings, options: hit)
            return
        }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let list = try await Self.fetch(settings: settings)
            guard settings.provider == provider else { return }  // user switched mid-flight
            cache[provider] = list
            models = list.map(\.id)
            if list.isEmpty { error = "The provider returned no models." }
            selectModelIfNeeded(settings: settings, options: list)
        } catch {
            guard settings.provider == provider else { return }
            models = []
            self.error = error.localizedDescription
        }
    }

    /// Picks a model when the saved one is empty, or belongs to a different
    /// provider.
    ///
    /// Without this, switching provider — including automatically, from a
    /// pasted key — left the model either blank or set to the previous
    /// provider's id. `Test connection` still passed, because it only lists
    /// models, and then every generation failed with the provider's own
    /// `model_not_found` 404.
    private func selectModelIfNeeded(settings: AISettings, options: [ModelOption]) {
        guard !options.isEmpty else { return }
        let current = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, options.contains(where: { $0.id == current }) {
            settings.modelMaxOutput = Self.maxOutput(for: current, in: options)
            return
        }
        guard let preferred = Self.preferredModel(from: options) else { return }
        settings.model = preferred
        settings.modelMaxOutput = Self.maxOutput(for: preferred, in: options)
    }

    /// Clears the list when the provider changes, so a stale list is never
    /// shown against the wrong provider.
    func reset() {
        models = []
        error = nil
    }

    static func fetch(settings: AISettings) async throws -> [ModelOption] {
        let endpoint = settings.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !endpoint.isEmpty else {
            throw NSError(domain: "MacdrawAI", code: 30, userInfo: [NSLocalizedDescriptionKey: "Set the endpoint first."])
        }
        if settings.provider != .local, settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NSError(domain: "MacdrawAI", code: 31, userInfo: [NSLocalizedDescriptionKey: "Add an API key to list models."])
        }

        // Ollama serves the OpenAI-compatible list at /v1/models, but older
        // builds only answer the native /api/tags — try both.
        if settings.provider == .local {
            if let list = try? await request(url: endpoint + "/models", settings: settings), !list.isEmpty {
                return list
            }
            let native = endpoint.replacingOccurrences(of: "/v1", with: "")
            return (try? await request(url: native + "/api/tags", settings: settings)) ?? []
        }

        let path = settings.provider == .anthropic ? "/models?limit=200" : "/models"
        return try await request(url: endpoint + path, settings: settings)
    }

    private static func request(url urlString: String, settings: AISettings) async throws -> [ModelOption] {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "MacdrawAI", code: 32, userInfo: [NSLocalizedDescriptionKey: "The endpoint URL is invalid."])
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        switch settings.provider.wireFormat {
        case .anthropicMessages:
            req.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .geminiGenerateContent:
            req.setValue(settings.apiKey, forHTTPHeaderField: "x-goog-api-key")
        case .openAIChat:
            if !settings.apiKey.isEmpty {
                req.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
            }
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "MacdrawAI", code: 33, userInfo: [NSLocalizedDescriptionKey: "No response from provider."])
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "MacdrawAI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey:
                "Provider returned \(http.statusCode): \(text.prefix(180))"])
        }
        return parseOptions(data, provider: settings.provider)
    }

    /// One entry from a provider's model list, with the metadata needed to
    /// tell a chat model from a transcription or text-to-speech one and to
    /// rank the plausible defaults.
    struct ModelOption {
        let id: String
        /// Whether the model can return chat text at all.
        let isChat: Bool
        /// `max_completion_tokens` where the provider reports it. A 512-token
        /// classifier should never be auto-picked over a real chat model.
        let maxOutput: Int?
    }

    /// The model to use when the saved one is empty or gone: the chat model
    /// with the most output headroom, falling back to list order (Anthropic
    /// and OpenRouter return newest-first) when the provider reports no
    /// metadata.
    static func preferredModel(from options: [ModelOption]) -> String? {
        let chat = options.filter(\.isChat)
        guard !chat.isEmpty else { return options.first?.id }
        // Drop anything that physically cannot hold a diagram: Groq lists
        // 512-token prompt-guard classifiers as text-to-text models.
        let roomy = chat.filter { ($0.maxOutput ?? Int.max) >= 2048 }
        let pool = roomy.isEmpty ? chat : roomy

        // Where the provider reports output ceilings, rank by them — Groq
        // returns its list in a *different order on every request*, so
        // "take the first" picks a different model each time (and picked a
        // 4096-token 7B model on one run). Ties break on id so the result is
        // stable. Where no ceiling is reported (Anthropic, OpenRouter) list
        // order is both meaningful and stable, so it wins.
        let measured = pool.filter { $0.maxOutput != nil }
        if !measured.isEmpty {
            return measured.sorted {
                ($0.maxOutput ?? 0, $1.id) > ($1.maxOutput ?? 0, $0.id)
            }.first?.id
        }
        return pool.first?.id
    }

    /// Reported output ceiling for a model id, when the provider gave one.
    static func maxOutput(for model: String, in options: [ModelOption]) -> Int? {
        options.first { $0.id == model }?.maxOutput
    }

    /// Normalizes every known list shape:
    ///   Anthropic / OpenAI / Grok / OpenRouter  ->  { "data": [ { "id": … } ] }
    ///   Gemini                                  ->  { "models": [ { "name": "models/…" } ] }
    ///   Ollama (native)                         ->  { "models": [ { "name": … } ] }
    static func parse(_ data: Data, provider: AIProvider) -> [String] {
        parseOptions(data, provider: provider).map(\.id)
    }

    static func parseOptions(_ data: Data, provider: AIProvider) -> [ModelOption] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        let rows = (root["data"] as? [[String: Any]]) ?? (root["models"] as? [[String: Any]]) ?? []
        var out: [ModelOption] = []
        var seen = Set<String>()
        for row in rows {
            guard var id = (row["id"] ?? row["name"] ?? row["model"]) as? String else { continue }
            // Gemini reports "models/gemini-…"; the request path adds the
            // prefix back itself.
            if provider == .gemini, id.hasPrefix("models/") { id.removeFirst("models/".count) }
            // Gemini lists embedding and other non-chat models too.
            if provider == .gemini {
                let methods = (row["supportedGenerationMethods"] as? [String]) ?? []
                if !methods.isEmpty, !methods.contains("generateContent") { continue }
            }
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)

            // Groq (and other OpenAI-compatible hosts) list speech and
            // transcription models alongside chat ones. `output_modalities`
            // separates them: a chat model emits text, Whisper emits
            // "transcription" and Orpheus emits "speech". Offering those in a
            // text-to-diagram picker is how you end up sending a prompt to a
            // speech synthesiser.
            let outputs = (row["output_modalities"] as? [String]) ?? []
            let isChat = outputs.isEmpty || outputs.contains("text")
            let maxOutput = (row["max_completion_tokens"] as? Int)
                ?? (row["max_output_length"] as? Int)

            out.append(ModelOption(id: trimmed, isChat: isChat, maxOutput: maxOutput))
        }
        // Anthropic and OpenRouter already return newest-first, which is the
        // order a user wants to pick from; local tags come back arbitrary.
        let chatFirst = out.filter(\.isChat) + out.filter { !$0.isChat }
        return provider == .local ? chatFirst.sorted { $0.id < $1.id } : chatFirst
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
@MainActor enum LocalModelRuntime {
    private static var server: Process?

    struct SetupProgress {
        let message: String
        let fraction: Double?
    }

    static func setUp(model: String, progress: (SetupProgress) -> Void = { _ in }) async throws {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw NSError(domain: "MacdrawAI", code: 20, userInfo: [NSLocalizedDescriptionKey: "Enter a local model name first."])
        }

        progress(SetupProgress(message: "Checking for Ollama…", fraction: nil))
        var executable = findExecutable(named: "ollama")
        if executable == nil {
            if let brew = findExecutable(named: "brew") {
                progress(SetupProgress(message: "Installing Ollama…", fraction: nil))
                let install = try await run(brew, ["install", "ollama"])
                guard install.status == 0 else { throw failure("Ollama installation", install) }
                executable = findExecutable(named: "ollama")
            } else {
                // Do not require users to know about Homebrew. Install the
                // official app into the user's Applications directory, which
                // avoids sudo/password prompts and works for Finder-launched
                // macdraw processes with a minimal PATH.
                executable = try await installOfficialOllama(progress: progress)
            }
        }
        guard let executable else {
            throw NSError(domain: "MacdrawAI", code: 22, userInfo: [NSLocalizedDescriptionKey: "Ollama was installed, but its command could not be found. Restart macdraw and try again."])
        }

        // Ollama may already be running as a menu-bar app or a launch agent.
        // Only start a child process when the local API is not ready.
        if !(await isServerReady()) && server?.isRunning != true {
            progress(SetupProgress(message: "Starting Ollama…", fraction: nil))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["serve"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            server = process
        }
        guard await waitForServer() else {
            throw NSError(domain: "MacdrawAI", code: 23, userInfo: [NSLocalizedDescriptionKey: "Ollama did not become ready. Open the Ollama app or run `ollama serve`, then try again."])
        }

        progress(SetupProgress(message: "Preparing \(model)…", fraction: nil))
        try await pullModel(model, progress: progress)
        progress(SetupProgress(message: "\(model) is ready.", fraction: 1))
    }

    private static func findExecutable(named name: String) -> String? {
        let fm = FileManager.default
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map { String($0) }
            .map { "\($0)/\(name)" }
        let fixedCandidates: [String]
        if name == "ollama" {
            fixedCandidates = [
                "/opt/homebrew/bin/ollama",
                "/usr/local/bin/ollama",
                "/Applications/Ollama.app/Contents/Resources/ollama",
                "\(NSHomeDirectory())/Applications/Ollama.app/Contents/Resources/ollama",
                "\(NSHomeDirectory())/.local/bin/ollama"
            ]
        } else {
            fixedCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew", "/usr/bin/brew"]
        }
        return (pathCandidates + fixedCandidates).first { fm.isExecutableFile(atPath: $0) }
    }

    private static func installOfficialOllama(progress: (SetupProgress) -> Void) async throws -> String {
        guard #available(macOS 14.0, *) else {
            throw NSError(domain: "MacdrawAI", code: 21, userInfo: [NSLocalizedDescriptionKey: "Automatic Ollama installation requires macOS 14 or newer. Open ollama.com/download/mac, install Ollama, then click setup again."])
        }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("macdraw-ollama-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        progress(SetupProgress(message: "Downloading Ollama…", fraction: nil))
        let archive = work.appendingPathComponent("Ollama-darwin.zip")
        let download = try await run("/usr/bin/curl", ["--fail", "--location", "--silent", "--show-error", "--output", archive.path, "https://ollama.com/download/Ollama-darwin.zip"])
        guard download.status == 0 else { throw failure("Ollama download", download) }

        progress(SetupProgress(message: "Installing Ollama…", fraction: nil))
        let extracted = work.appendingPathComponent("extracted")
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        let unpack = try await run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
        guard unpack.status == 0 else { throw failure("Ollama unpack", unpack) }
        let downloadedApp = extracted.appendingPathComponent("Ollama.app")
        guard fm.isExecutableFile(atPath: downloadedApp.appendingPathComponent("Contents/Resources/ollama").path) else {
            throw NSError(domain: "MacdrawAI", code: 22, userInfo: [NSLocalizedDescriptionKey: "The Ollama download did not contain a usable macOS app. Open ollama.com/download/mac and install it once, then try again."])
        }

        let userApplications = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true)
        try fm.createDirectory(at: userApplications, withIntermediateDirectories: true)
        let destination = userApplications.appendingPathComponent("Ollama.app")
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.copyItem(at: downloadedApp, to: destination)
        return destination.appendingPathComponent("Contents/Resources/ollama").path
    }

    private static func pullModel(_ model: String, progress: (SetupProgress) -> Void) async throws {
        guard let url = URL(string: "http://127.0.0.1:11434/api/pull") else {
            throw NSError(domain: "MacdrawAI", code: 24, userInfo: [NSLocalizedDescriptionKey: "The local Ollama URL is invalid."])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60 * 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "MacdrawAI", code: 25, userInfo: [NSLocalizedDescriptionKey: "No response from Ollama while downloading the model."])
        }
        guard (200..<300).contains(http.statusCode) else {
            var text = ""
            for try await line in bytes.lines {
                text += line
                if text.count > 240 { break }
            }
            let detail = text.isEmpty ? "HTTP \(http.statusCode)" : text
            throw NSError(domain: "MacdrawAI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Ollama could not download \(model): \(detail)"])
        }

        var didSucceed = false
        for try await line in bytes.lines where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                  let update = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let error = update["error"] as? String {
                throw NSError(domain: "MacdrawAI", code: 26, userInfo: [NSLocalizedDescriptionKey: "Ollama could not download \(model): \(error)"])
            }
            let status = update["status"] as? String ?? "Downloading \(model)…"
            let total = (update["total"] as? NSNumber)?.doubleValue ?? 0
            let completed = (update["completed"] as? NSNumber)?.doubleValue ?? 0
            let fraction = total > 0 ? min(1, completed / total) : nil
            let message: String
            if let fraction {
                message = "\(status.capitalized) — \(Int((fraction * 100).rounded()))%"
            } else {
                message = status.capitalized
            }
            progress(SetupProgress(message: message, fraction: fraction))
            if status.lowercased() == "success" { didSucceed = true }
        }
        guard didSucceed else {
            throw NSError(domain: "MacdrawAI", code: 27, userInfo: [NSLocalizedDescriptionKey: "Ollama stopped before \(model) finished downloading. Click Download model to try again."])
        }
    }

    private static func isServerReady() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else { return false }
        var request = URLRequest(url: url); request.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch { return false }
    }

    private static func waitForServer() async -> Bool {
        for _ in 0..<30 {
            if await isServerReady() { return true }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
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
    You build precise, editable text-to-diagram JSON for a drawing canvas.

    Return ONLY a valid JSON object with this exact schema (no markdown, no prose):
    {"title":"short title","nodes":[{"id":"n1","label":"short label","kind":"...","x":0,"y":0,"width":150,"height":64,"symbol":"optional SF Symbol name","code":false}],"edges":[{"id":"e1","from":"n1","to":"n2","label":"optional","style":"curved|orthogonal|straight","startArrow":"none|arrow|triangle|bar","endArrow":"arrow|none|triangle|bar"}]}

    Rules:
    - Every edge.from and edge.to MUST reference an existing node id. Every node
      should participate in the flow unless it is intentionally standalone.
    - Use a clean left-to-right or top-to-bottom layout: meaningfully spaced x and
      y positions (e.g. step by ~220 in x or ~140 in y) so nothing overlaps. Do
      not return all zeros.
    - Choose `kind` from: start, end, decision, input, process, database,
      predefined, cloud, cube, storage (server stack), note, callout, shape,
      data (linked list / sequence), page. Map them to the natural meaning:
        - start/end/terminator -> start/end
        - a yes/no or branch -> decision
        - a user type/entry -> input
        - an external service or system -> cloud
        - database or a store -> database
        - a highlighted remark/annotation -> note
        - anything else that does work -> process
    - `symbol`: OPTIONALLY pick ONE SF Symbol name (a small logo/icon) that best
      matches a node, ONLY from this allowed list:
      \(AIIconCatalog.icons.joined(separator: ", "))
      Use "" (or omit) on most nodes; reserve icons for the 2-5 most important
      ones so the diagram stays clean.
    - `code`: set true ONLY when the "label" is an actual code snippet the user
      asked to show (rendered as a highlighted code block). Keep code short.
    - Edges: `style` curved is fine, but use orthogonal or straight for clean
      right-angle flows. Set `label` only when a connection deserves a word
      (e.g. "yes"/"no", a reason, a request/response).
    - Prefer concrete, specific labels over vague ones. Keep labels concise.
    - For long flows, prefer breadth over depth but never drop required steps.
    """

    /// Maximum number of refinement passes the agent loop runs. Each pass asks
    /// the model to improve the previous draft. The best validated result wins.
    static let maxAgentIterations = 3

    /// Generates a diagram, then runs an agent loop that critiques and refines
    /// the draft up to `maxAgentIterations - 1` more times, returning the best
    /// structurally-valid result.
    static func generate(prompt: String, settings: AISettings, progress: ((String) -> Void)? = nil) async throws -> DiagramSpec {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NSError(domain: "MacdrawAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Describe the diagram first."]) }
        if settings.provider == .local && settings.endpoint.isEmpty { throw NSError(domain: "MacdrawAI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Set the local Ollama endpoint."]) }
        if settings.provider != .local && settings.apiKey.isEmpty { throw NSError(domain: "MacdrawAI", code: 3, userInfo: [NSLocalizedDescriptionKey: "Add an API key in Settings."]) }
        if settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw NSError(domain: "MacdrawAI", code: 4, userInfo: [NSLocalizedDescriptionKey: "Set a model name in Settings."]) }

        // Pass 0: initial generation.
        progress?("Drafting \(prompt)…")
        let first = try await request(prompt: prompt, settings: settings)
        var best = try decode(first)

        // Agent loop: critique + refine repeatedly, keeping the best draft.
        for pass in 1..<maxAgentIterations {
            guard let currentJSON = specJSON(best) else { break }
            progress?("Refining pass \(pass) of \(maxAgentIterations - 1)…")
            let refinePrompt = """
            Original request: \(prompt)

            Current draft JSON:
            \(currentJSON)

            \(AICritiqueRules.text)

            Return the improved JSON only.
            """
            let response = try await request(prompt: refinePrompt, settings: settings)
            guard let candidate = try? decode(response) else { continue }
            // Keep the candidate only if it is at least as complete and valid.
            if isValid(candidate) && completeness(candidate) >= completeness(best) {
                best = candidate
            }
        }
        return best
    }

    /// Serializes a spec to a compact JSON string for iterative refinement.
    private static func specJSON(_ spec: DiagramSpec) -> String? {
        (try? JSONEncoder().encode(spec)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Structural sanity check beyond Decodable: every edge references real
    /// nodes, nodes are uniquely id'd, and the diagram isn't empty.
    static func isValid(_ spec: DiagramSpec) -> Bool {
        guard !spec.nodes.isEmpty else { return false }
        var seen = Set<String>()
        for n in spec.nodes {
            if seen.contains(n.id) || n.id.isEmpty { return false }
            seen.insert(n.id)
        }
        for e in spec.edges {
            guard seen.contains(e.from), seen.contains(e.to) else { return false }
        }
        return true
    }

    /// A simple completeness score used to prefer denser, more faithful drafts.
    static func completeness(_ spec: DiagramSpec) -> Int {
        spec.nodes.count * 2 + spec.edges.count
    }
    static func test(settings: AISettings) async -> String {
        do {
            if settings.provider != .local && settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add an API key in Settings." }
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
                // Native Ollama uses "models"/"name", while its OpenAI-
                // compatible /v1/models endpoint uses "data"/"id".
                let models = (payload?["models"] as? [[String: Any]])
                    ?? (payload?["data"] as? [[String: Any]])
                    ?? []
                let wanted = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
                let available = models.compactMap { ($0["name"] ?? $0["id"] ?? $0["model"]) as? String }
                if !wanted.isEmpty && !available.contains(where: { modelNameMatches($0, wanted: wanted) }) {
                    return "Ollama connected, but \(wanted) is not downloaded yet."
                }
                return "Connected (Ollama)"
            }
            // Every remaining provider has a models endpoint, so the check
            // is a free GET. It used to send a real Anthropic completion,
            // which costs tokens — and with adaptive thinking on, a small
            // allowance can be spent entirely on reasoning and come back with
            // no text, reporting a working key as broken.
            let status = await healthCheck(settings: settings)
            guard status.hasPrefix("Connected") else { return status }
            // A valid key with a model the provider doesn't serve used to
            // report "Connected" and then 404 on the first generation. The
            // listing is already in hand, so check the model against it.
            let wanted = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wanted.isEmpty else { return "Connected, but no model is selected." }
            if settings.provider == .gemini { return status }
            guard let options = try? await AIModelCatalog.fetch(settings: settings), !options.isEmpty else {
                return status
            }
            guard let match = options.first(where: { $0.id == wanted }) else {
                return "Connected, but \(wanted) is not available on this key."
            }
            if !match.isChat {
                return "Connected, but \(wanted) does not return text — pick a chat model."
            }
            return status
        } catch { return error.localizedDescription }
    }

    private static func modelNameMatches(_ available: String, wanted: String) -> Bool {
        let available = available.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = wanted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !available.isEmpty, !wanted.isEmpty else { return false }
        if available == wanted { return true }
        if !wanted.contains(":") { return available.hasPrefix(wanted + ":") }
        return false
    }

    private static func healthCheck(settings: AISettings) async -> String {
        let endpoint = settings.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path: String
        if settings.provider == .gemini {
            let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "models/", with: "")
            guard !model.isEmpty else { return "Set a Gemini model name in Settings." }
            guard let escapedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return "The model name is invalid." }
            path = "/models/\(escapedModel)"
        } else {
            path = "/models"
        }
        guard let url = URL(string: endpoint + path) else { return "The endpoint URL is invalid." }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch settings.provider.wireFormat {
        case .geminiGenerateContent:
            request.setValue(settings.apiKey, forHTTPHeaderField: "x-goog-api-key")
        case .anthropicMessages:
            request.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openAIChat:
            if !settings.apiKey.isEmpty {
                request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
            }
        }
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
    /// Output ceiling for one diagram pass. A diagram spec is small, but on
    /// Claude the ceiling has to cover thinking tokens as well as the JSON —
    /// at the old 2600 an adaptive-thinking model could spend the whole
    /// allowance reasoning and return nothing.
    static let maxOutputTokens = 12000

    /// How hard Claude works per pass. `medium` is the default on
    /// claude-opus-5-5; the harness raises it for the final polish pass.
    static let defaultEffort = "medium"

    /// One completion, against whichever provider is configured. `system` is
    /// a parameter so scene generation can share this transport instead of
    /// duplicating the seven-provider branching.
    static func request(
        prompt: String,
        system: String? = nil,
        settings: AISettings,
        maxTokens: Int = maxOutputTokens,
        effort: String = defaultEffort,
        retriesLeft: Int = 1
    ) async throws -> String {
        let systemPrompt = system ?? Self.systemPrompt
        // Respect the model's own output ceiling. Groq rejects anything above
        // it with a 400 rather than clamping, and small models cap at 4096.
        var maxTokens = maxTokens
        if let ceiling = settings.modelMaxOutput, ceiling > 0 {
            maxTokens = min(maxTokens, ceiling)
        }
        let endpoint = settings.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString: String
        var body: [String: Any]
        var headers = ["Content-Type": "application/json"]
        if settings.provider == .gemini {
            let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "models/", with: "")
            guard let escapedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { throw NSError(domain: "MacdrawAI", code: 4, userInfo: [NSLocalizedDescriptionKey: "The model name is invalid."]) }
            urlString = endpoint + "/models/\(escapedModel):generateContent"
            headers["x-goog-api-key"] = settings.apiKey
            body = [
                "systemInstruction": ["parts": [["text": systemPrompt]]],
                "contents": [["role": "user", "parts": [["text": prompt]]]],
                "generationConfig": ["temperature": 0.2, "maxOutputTokens": maxTokens, "responseMimeType": "application/json"]
            ]
        } else if settings.provider == .anthropic {
            urlString = endpoint + "/messages"
            headers["x-api-key"] = settings.apiKey; headers["anthropic-version"] = "2023-06-01"
            // Adaptive thinking + effort is the current way to control how
            // much reasoning Claude spends; `budget_tokens` is rejected on
            // claude-opus-5-5 and the rest of the 5 family, and so is
            // `temperature` (which is why this branch sets neither).
            body = [
                "model": settings.model,
                "max_tokens": maxTokens,
                "system": systemPrompt,
                "thinking": ["type": "adaptive"],
                "output_config": ["effort": effort],
                "messages": [["role": "user", "content": prompt]],
            ]
        } else {
            urlString = endpoint + "/chat/completions"
            if !settings.apiKey.isEmpty { headers["Authorization"] = "Bearer \(settings.apiKey)" }
            // Do not force response_format here: many valid OpenRouter models
            // are OpenAI-compatible but do not expose JSON-mode parameters.
            body = ["model": settings.model, "temperature": 0.2, "max_tokens": maxTokens, "messages": [["role": "system", "content": systemPrompt], ["role": "user", "content": prompt]]]
        }
        guard let url = URL(string: urlString) else { throw NSError(domain: "MacdrawAI", code: 4, userInfo: [NSLocalizedDescriptionKey: "The endpoint URL is invalid."]) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        // A thinking model can spend a minute or more on one pass before the
        // first byte arrives, and the harness runs several passes. The old 35s
        // was tuned for a non-thinking one-shot and would abort a request that
        // was working fine. Each response is a small JSON object, so a
        // generous non-streaming timeout is enough here; streaming would only
        // be needed for long prose output.
        req.timeoutInterval = 240
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NSError(domain: "MacdrawAI", code: 5, userInfo: [NSLocalizedDescriptionKey: "No response from provider."]) }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown error"
            // 404 from a chat endpoint almost always means the model id, not
            // a bad URL — say so, because "404" on its own sends people
            // looking at their endpoint.
            if http.statusCode == 404 {
                let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
                let named = model.isEmpty ? "No model is selected" : "\(model) is not available on this key"
                throw NSError(domain: "MacdrawAI", code: 404, userInfo: [NSLocalizedDescriptionKey:
                    "\(named). Open Settings and pick one from the Model dropdown."])
            }
            // Rate limiting: the harness makes several calls per run, which
            // on a free tier can exhaust a per-minute token budget mid-run.
            // The provider tells us how long to wait, so wait rather than
            // throwing away the work already done.
            if http.statusCode == 429, retriesLeft > 0 {
                let headerDelay = (http.value(forHTTPHeaderField: "retry-after")).flatMap(Double.init)
                let delay = min(headerDelay ?? Self.parseRetryAfter(from: text) ?? 20, 60)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await request(
                    prompt: prompt, system: system, settings: settings,
                    maxTokens: maxTokens, effort: effort, retriesLeft: retriesLeft - 1
                )
            }
            if http.statusCode == 429 {
                throw NSError(domain: "MacdrawAI", code: 429, userInfo: [NSLocalizedDescriptionKey:
                    "\(settings.provider.rawValue) rate limit reached for \(settings.model). Wait a minute and try again, or pick a model with a higher quota."])
            }
            // Some providers report no output ceiling in their model list and
            // then reject the request for exceeding it. Retry once, smaller,
            // rather than making the user discover the number by hand.
            if http.statusCode == 400, text.contains("max_tokens"), maxTokens > 4096 {
                return try await request(
                    prompt: prompt, system: system, settings: settings,
                    maxTokens: 4096, effort: effort, retriesLeft: retriesLeft
                )
            }
            throw NSError(domain: "MacdrawAI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Provider returned \(http.statusCode): \(text.prefix(240))"])
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if settings.provider == .gemini,
           let candidates = json?["candidates"] as? [[String: Any]],
           let parts = candidates.first?["content"] as? [String: Any],
           let values = parts["parts"] as? [[String: Any]] {
            let text = values.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty { return text }
        }
        if settings.provider == .anthropic {
            // A refusal is an HTTP 200 with no usable content — check it
            // before reading the blocks.
            if (json?["stop_reason"] as? String) == "refusal" {
                let details = json?["stop_details"] as? [String: Any]
                let category = details?["category"] as? String ?? "unspecified"
                throw NSError(domain: "MacdrawAI", code: 9, userInfo: [NSLocalizedDescriptionKey:
                    "Claude declined this request (\(category)). Rephrase the diagram description and try again."])
            }
            if let blocks = json?["content"] as? [[String: Any]] {
                // With thinking on, content[0] is a thinking block and
                // carries no "text" — reading only the first block made every
                // response look like "no chat text". Join every text block.
                let text = blocks
                    .filter { ($0["type"] as? String) == "text" }
                    .compactMap { $0["text"] as? String }
                    .joined()
                if !text.isEmpty { return text }
                if (json?["stop_reason"] as? String) == "max_tokens" {
                    throw NSError(domain: "MacdrawAI", code: 10, userInfo: [NSLocalizedDescriptionKey:
                        "Claude used the whole output allowance on reasoning. Lower the effort or raise max tokens."])
                }
            }
        }
        if let choices = json?["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any], let text = message["content"] as? String { return text }
        throw NSError(domain: "MacdrawAI", code: 6, userInfo: [NSLocalizedDescriptionKey: "Provider did not return chat text."])
    }
    /// Seconds from a provider's prose hint ("Please try again in 36.48s").
    /// Used when there is no `retry-after` header.
    static func parseRetryAfter(from body: String) -> Double? {
        guard let range = body.range(of: "try again in ") else { return nil }
        let tail = body[range.upperBound...]
        let number = tail.prefix { $0.isNumber || $0 == "." }
        return Double(number)
    }

    static func decode(_ text: String) throws -> DiagramSpec {
        let cleaned = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") else { throw NSError(domain: "MacdrawAI", code: 7, userInfo: [NSLocalizedDescriptionKey: "The model did not return a diagram JSON object."]) }
        let json = String(cleaned[start...end])
        var spec = try JSONDecoder().decode(DiagramSpec.self, from: Data(json.utf8))
        guard !spec.nodes.isEmpty else { throw NSError(domain: "MacdrawAI", code: 8, userInfo: [NSLocalizedDescriptionKey: "The generated diagram has no nodes."]) }
        // Drop edges that reference nothing instead of letting one bad edge
        // fail `isValid` and discard an otherwise good diagram. The canvas
        // converter skips unresolvable edges anyway.
        let ids = Set(spec.nodes.map(\.id))
        spec.edges = spec.edges.filter { ids.contains($0.from) && ids.contains($0.to) }
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

/// What the drawer produced, so the canvas can place it the right way.
enum AIGeneration {
    case diagram(DiagramSpec)
    case scene(SceneSpec)
}

/// Which generator the drawer runs. A diagram is a node/edge flowchart that
/// the connector system wires together; a scene is a free composition using
/// macdraw's full shape, colour and fill vocabulary.
enum AIGenerationMode: String, CaseIterable, Identifiable {
    case scene = "Drawing"
    case diagram = "Diagram"
    var id: String { rawValue }
    var blurb: String {
        switch self {
        case .scene: return "Any shapes, colours and hand-drawn fills. Best for illustrations and layouts."
        case .diagram: return "Nodes and connectors that stay glued together. Best for flows and architecture."
        }
    }
}

struct AIDiagramDrawer: View {
    @ObservedObject var settings: AISettings
    let onInsert: (AIGeneration) -> Void
    let onClose: () -> Void
    @State private var prompt = ""
    @State private var mode: AIGenerationMode = .scene
    @State private var scene: SceneSpec?
    @State private var sceneReport = ""
    @State private var diagram: DiagramSpec?
    @State private var isGenerating = false
    @State private var generatingStatus = ""
    @State private var error = ""
    /// Opens with the settings panel expanded under `--ai`, so the provider
    /// and model controls can be screenshotted without a click.
    @State private var settingsOpen = CommandLine.arguments.contains("--ai")
    @State private var messages: [AIChatMessage] = []
    var body: some View {
        VStack(spacing: 0) {
            HStack { Label("Text to diagram", systemImage: "sparkles").font(.system(size: 15, weight: .bold)); Spacer(); Button { settingsOpen.toggle() } label: { Image(systemName: "gearshape") }.buttonStyle(.plain); Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.plain) }.padding(14)
            Divider()
            if settingsOpen { AISettingsView(settings: settings) }
            ScrollView { VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $mode) { ForEach(AIGenerationMode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                Text(mode.blurb).font(.system(size: 12)).foregroundStyle(.secondary)
                ForEach(messages) { message in AIChatBubble(message: message) }
                TextEditor(text: $prompt).font(.system(size: 13)).frame(height: 108).padding(7).background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                HStack {
                    Button("Example") { prompt = mode == .scene ? exampleScenePrompt : exampleDiagramPrompt }.buttonStyle(.borderless)
                    Spacer()
                    if !messages.isEmpty { Button("Clear chat") { messages.removeAll(); diagram = nil; scene = nil; sceneReport = ""; error = "" }.buttonStyle(.borderless) }
                    Button { generate() } label: { Label(isGenerating ? "Generating…" : "Generate", systemImage: "arrow.up.circle.fill") }.disabled(isGenerating).buttonStyle(.borderedProminent)
                }
                if isGenerating && !generatingStatus.isEmpty { Text(generatingStatus).font(.system(size: 11)).foregroundStyle(.secondary) }
                if !error.isEmpty { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
                if let diagram { DiagramPreview(diagram: diagram).frame(height: 245).background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 10)); HStack { Text("\(diagram.nodes.count) objects · \(diagram.edges.count) editable connectors").font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); Button("Insert into canvas") { onInsert(.diagram(diagram)) }.buttonStyle(.borderedProminent) } }
                if let scene {
                    HStack {
                        Text(sceneReport).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Insert into canvas") { onInsert(.scene(scene)) }.buttonStyle(.borderedProminent)
                    }
                }
            }.padding(14) }
        }.frame(width: 390, height: 520).background(.ultraThinMaterial)
    }
    private var exampleScenePrompt: String {
        "A hand-drawn poster of a coffee shop menu: a big framed title, three drink cards with icons and prices, and a small note at the bottom."
    }
    private var exampleDiagramPrompt: String {
        "Create an onboarding flow: Start, create account, verify email, decision: verified?, dashboard or resend email."
    }

    private func generate() {
        let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { error = mode == .scene ? "Describe what to draw first." : "Describe the diagram first."; return }
        if mode == .scene { generateScene(request); return }
        let previous = diagram.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        let modelPrompt = previous.map { "Update this existing diagram according to the request. Preserve useful nodes and edges unless the request changes them. Existing JSON: \($0)\nRequest: \(request)" } ?? request
        messages.append(AIChatMessage(role: "user", text: request))
        prompt = ""
        isGenerating = true; generatingStatus = "Starting…"; error = ""
        Task {
            do {
                let output = try await DiagramAI.generate(prompt: modelPrompt, settings: settings) { status in
                    Task { @MainActor in self.generatingStatus = status }
                }
                await MainActor.run { diagram = output; generatingStatus = ""; messages.append(AIChatMessage(role: "assistant", text: "Generated \(output.nodes.count) nodes and \(output.edges.count) connectors. Review the preview, then insert it into the canvas.")); isGenerating = false }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; generatingStatus = ""; isGenerating = false }
            }
        }
    }

    /// Runs the scene harness. The status line reports what the harness
    /// measured on each pass, so a long run shows its working instead of
    /// sitting on "Generating…".
    private func generateScene(_ request: String) {
        let previous = scene.flatMap { SceneAI.encode($0) }
        let modelPrompt = previous.map {
            """
            Update this existing drawing according to the request. Keep what
            still fits; change only what the request asks for.

            Existing scene:
            \($0)

            Request: \(request)
            """
        } ?? request
        messages.append(AIChatMessage(role: "user", text: request))
        prompt = ""
        isGenerating = true; generatingStatus = "Starting…"; error = ""
        Task {
            do {
                let output = try await SceneAI.generate(prompt: modelPrompt, settings: settings) { status in
                    Task { @MainActor in self.generatingStatus = status }
                }
                let remaining = SceneCritic.defects(output)
                await MainActor.run {
                    scene = output
                    diagram = nil
                    sceneReport = remaining.isEmpty
                        ? "\(output.elements.count) elements · no issues found"
                        : "\(output.elements.count) elements · \(remaining.count) issue\(remaining.count == 1 ? "" : "s") left"
                    generatingStatus = ""
                    messages.append(AIChatMessage(role: "assistant", text: sceneReport + ". Insert it into the canvas to edit it."))
                    isGenerating = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; generatingStatus = ""; isGenerating = false }
            }
        }
    }
}

private struct AISettingsView: View {
    @ObservedObject var settings: AISettings
    @StateObject private var catalog = AIModelCatalog()
    @State private var testing = false
    @State private var typingModel = false
    @State private var keyNote = ""
    @State private var installing = false
    @State private var setupStatus = ""
    @State private var setupNeedsHelp = false
    @State private var downloadFraction: Double?
    var body: some View { VStack(alignment: .leading, spacing: 8) {
        Picker("Provider", selection: $settings.provider) { ForEach(AIProvider.allCases) { Text($0.rawValue).tag($0) } }
            .onChange(of: settings.provider) { _, _ in
                settings.useProviderDefaults()
                catalog.reset()
                Task { await catalog.load(settings: settings) }
            }
        TextField("Endpoint", text: $settings.endpoint).textFieldStyle(.roundedBorder)
        modelPicker
        if settings.provider != .local {
            HStack(spacing: 6) {
                SecureField("API key (stored in Keychain)", text: $settings.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { adopt(settings.apiKey) }
                    .onChange(of: settings.apiKey) { _, newValue in
                        // A paste lands as one large change; typing arrives a
                        // character at a time. Only react to the former, so
                        // the provider never switches mid-keystroke.
                        guard newValue.count > 12, AIProvider.detect(fromKey: newValue) != nil else { return }
                        adopt(newValue)
                    }
                Button { pasteAPIKey() } label: { Image(systemName: "doc.on.clipboard") }.help("Paste a key — macdraw detects which provider it belongs to")
            }
            if !keyNote.isEmpty {
                Text(keyNote).font(.system(size: 10)).foregroundStyle(.green)
            }
            if let keyURL = settings.provider.keyHelpURL, let url = URL(string: keyURL) {
                Link("Get an API key for \(settings.provider.rawValue)", destination: url)
                    .font(.system(size: 10))
            }
        }
        if settings.provider == .local {
            HStack(spacing: 8) {
                if installing {
                    if let downloadFraction {
                        ProgressView(value: downloadFraction).frame(width: 72)
                        Text("\(Int((downloadFraction * 100).rounded()))%").font(.system(size: 10)).monospacedDigit()
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                Button(setupButtonTitle) { setUpOllama() }.disabled(installing)
            }
            if installing || !setupStatus.isEmpty { Text(setupStatus).font(.system(size: 10)).foregroundStyle(setupNeedsHelp ? .orange : .secondary) }
            if setupNeedsHelp {
                Button("Open Ollama download page") { openOllamaDownloadPage() }.buttonStyle(.borderless).font(.system(size: 10))
            }
            Text("Setup finds or installs Ollama, starts it, and downloads the selected model. Prompts never leave localhost.").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        HStack {
            Button(testing ? "Testing…" : "Test connection") { testing = true; Task { let status = await DiagramAI.test(settings: settings); await MainActor.run { settings.testStatus = status; testing = false } } }.disabled(testing)
            Image(systemName: settings.testStatus.hasPrefix("Connected") ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(settings.testStatus.hasPrefix("Connected") ? .green : .secondary)
            Text(settings.testStatus).font(.system(size: 11)).foregroundStyle(settings.testStatus.hasPrefix("Connected") ? .green : .secondary)
        }
        if settings.provider == .local { Text("If automatic setup cannot finish, install Ollama from ollama.com/download/mac and click the setup button again.").font(.system(size: 10)).foregroundStyle(.secondary) }
    }
    .padding(14)
    .background(Color.primary.opacity(0.05))
    .task { await catalog.load(settings: settings) } }

    /// Model chooser. Lists what the provider says the key can reach, with a
    /// refresh, and falls back to free text when the list can't be fetched (an
    /// unreachable custom endpoint, a key without list permission) so the
    /// field is never a dead end.
    @ViewBuilder
    private var modelPicker: some View {
        HStack(spacing: 6) {
            if typingModel || (catalog.models.isEmpty && !catalog.loading) {
                TextField("Model", text: $settings.model).textFieldStyle(.roundedBorder)
            } else {
                Picker("Model", selection: $settings.model) {
                    // The saved model may not be in the fetched list (a
                    // preview id, or a list that came back filtered) — keep it
                    // selectable rather than silently switching the user's
                    // model.
                    if !settings.model.isEmpty, !catalog.models.contains(settings.model) {
                        Text(settings.model).tag(settings.model)
                    }
                    ForEach(catalog.models, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if catalog.loading {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await catalog.load(settings: settings, force: true) }
                } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh the model list from \(settings.provider.rawValue)")
            }
            Button {
                typingModel.toggle()
            } label: { Image(systemName: typingModel ? "list.bullet" : "character.cursor.ibeam") }
                .help(typingModel ? "Choose from the provider's list" : "Type a model id by hand")
        }
        if let error = catalog.error, !typingModel {
            Text(error).font(.system(size: 10)).foregroundStyle(.orange)
        }
    }

    private func pasteAPIKey() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        adopt(value)
    }

    /// Takes a key, points the app at whichever provider issued it, and
    /// refreshes the model list — a key is usually the thing that was
    /// blocking it.
    private func adopt(_ value: String) {
        let before = settings.provider
        if let detected = settings.adopt(pastedKey: value) {
            keyNote = detected == before
                ? "Recognized a \(detected.rawValue) key."
                : detected.keyRecognizedNote
        } else {
            keyNote = ""
        }
        catalog.reset()
        Task { await catalog.load(settings: settings, force: true) }
    }

    private func openOllamaDownloadPage() {
        if let url = URL(string: "https://ollama.com/download/mac") { NSWorkspace.shared.open(url) }
    }

    private var modelIsMissing: Bool {
        settings.testStatus.hasPrefix("Ollama connected, but")
    }

    private var setupButtonTitle: String {
        if installing { return "Setting up…" }
        if modelIsMissing {
            let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
            return model.isEmpty ? "Download model" : "Download \(model)"
        }
        return "Set up Ollama & pull model"
    }

    private func setUpOllama() {
        installing = true
        setupNeedsHelp = false
        downloadFraction = nil
        setupStatus = "Checking for Ollama…"
        settings.testStatus = "Preparing Ollama…"
        Task {
            do {
                try await LocalModelRuntime.setUp(model: settings.model) { update in
                    Task { @MainActor in
                        setupStatus = update.message
                        downloadFraction = update.fraction
                    }
                }
                await MainActor.run { setupStatus = "Testing local connection…" }
                let status = await DiagramAI.test(settings: settings)
                await MainActor.run {
                    settings.testStatus = status
                    setupNeedsHelp = !status.hasPrefix("Connected")
                    setupStatus = status.hasPrefix("Connected") ? "Ollama is ready." : "The model is still unavailable. Click Download model to try again."
                    downloadFraction = nil
                    installing = false
                }
            } catch {
                await MainActor.run {
                    settings.testStatus = "Needs setup"
                    setupStatus = error.localizedDescription
                    setupNeedsHelp = true
                    downloadFraction = nil
                    installing = false
                }
            }
        }
    }
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
    var body: some View {
        ZStack {
            Path { path in
                path.move(to: start)
                if edge.style == "curved" { path.addCurve(to: end, control1: CGPoint(x: start.x + (end.x-start.x)*0.45, y: start.y), control2: CGPoint(x: start.x + (end.x-start.x)*0.55, y: end.y)) } else { path.addLine(to: end) }
            }.stroke(Color.accentColor, style: SwiftUI.StrokeStyle(lineWidth: 1.5, lineCap: .round))
            if edge.startArrow != "none" {
                ArrowGlyph(at: start, toward: end)
            }
            if edge.endArrow != "none" {
                ArrowGlyph(at: end, toward: start)
            }
        }
    }
}

private struct ArrowGlyph: View {
    let at: CGPoint
    let toward: CGPoint
    private var angle: CGFloat { atan2(toward.y - at.y, toward.x - at.x) }
    var body: some View {
        let len: CGFloat = 7
        Path { p in
            p.move(to: CGPoint(x: at.x + cos(angle) * len, y: at.y + sin(angle) * len))
            p.addLine(to: CGPoint(x: at.x + cos(angle + 2.6) * len, y: at.y + sin(angle + 2.6) * len))
            p.move(to: CGPoint(x: at.x + cos(angle) * len, y: at.y + sin(angle) * len))
            p.addLine(to: CGPoint(x: at.x + cos(angle - 2.6) * len, y: at.y + sin(angle - 2.6) * len))
        }.stroke(Color.accentColor, lineWidth: 1.5).frame(width: 0, height: 0)
    }
}

private struct DiagramPreviewNode: View {
    let node: DiagramNode; let rect: CGRect
    private var shapeFill: Color {
        switch node.kind.lowercased() {
        case "start", "end": return Color.green.opacity(0.9)
        case "decision": return Color.yellow.opacity(0.55)
        case "input": return Color.blue.opacity(0.35)
        case "database": return Color.purple.opacity(0.35)
        case "cloud": return Color.cyan.opacity(0.35)
        case "note": return Color.orange.opacity(0.35)
        default: return Color(nsColor: .windowBackgroundColor)
        }
    }
    var body: some View {
        if node.code {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1))
                .overlay(
                    Text(node.label)
                        .font(.system(size: max(7, min(10, rect.height * 0.16)), design: .monospaced))
                        .foregroundStyle(Color.green)
                        .lineLimit(4)
                        .padding(3),
                    alignment: .topLeading
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        } else {
            ZStack {
                shape(rect: rect)
                    .fill(shapeFill)
                    .overlay(shape(rect: rect).stroke(Color.accentColor, lineWidth: 1))
                VStack(spacing: 2) {
                    if let sym = node.symbol, !sym.isEmpty {
                        Image(systemName: sym)
                            .font(.system(size: max(8, rect.height * 0.26), weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(node.label)
                        .font(.system(size: max(8, min(12, rect.height * 0.24))))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                }
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
        }
    }
    private func shape(rect: CGRect) -> some Shape {
        switch node.kind.lowercased() {
        case "start", "end", "terminator": AnyShape(Capsule())
        case "decision": AnyShape(Rhombus())
        case "input": AnyShape(ParallelogramShape())
        case "cloud": AnyShape(Capsule())
        default: AnyShape(RoundedRectangle(cornerRadius: 7))
        }
    }
}

private struct Rhombus: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

private struct ParallelogramShape: Shape {
    func path(in rect: CGRect) -> Path {
        let skew = rect.height * 0.3
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + skew, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - skew, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
