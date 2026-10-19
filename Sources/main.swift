import AppKit

setbuf(stdout, nil)

let app = NSApplication.shared

// --install mode: show the sleek installer window and nothing else.
if CommandLine.arguments.contains("--install") {
    app.setActivationPolicy(.accessory)
    let delegate = InstallModeDelegate()
    app.delegate = delegate
    app.run()
} else {
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate

    if CommandLine.arguments.contains("--selftest") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            delegate.runSelfTest()
        }
    }

    // Live provider check: `--aitest "<prompt>"`, with MACDRAW_AI_KEY set.
    // Runs the real pipeline — key detection, model listing and selection,
    // then a generation — against the provider the key belongs to, and exits.
    // Settings are in-memory only, so nothing touches the user's Keychain.
    if CommandLine.arguments.contains("--aitest") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Task { await runAITest() }
        }
    }

    if CommandLine.arguments.contains("--synctest") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            delegate.runSyncTest()
        }
    }

    app.run()
}

/// Drives one real request through the provider pipeline and prints what
/// happened at each step, so a connection problem can be told apart from a
/// model problem and from a generation problem.
@MainActor
func runAITest() async {
    let env = ProcessInfo.processInfo.environment
    guard let key = env["MACDRAW_AI_KEY"], !key.isEmpty else {
        print("[aitest] set MACDRAW_AI_KEY")
        exit(2)
    }
    let args = CommandLine.arguments
    let prompt = args.firstIndex(of: "--aitest").map { $0 + 1 }.flatMap { $0 < args.count ? args[$0] : nil }
        ?? "A simple two-box flow: Request then Response."

    guard let provider = AIProvider.detect(fromKey: key) else {
        print("[aitest] FAIL: no provider recognized from that key prefix")
        exit(1)
    }
    print("[aitest] key detected as: \(provider.rawValue)")

    let settings = AISettings(ephemeralProvider: provider, key: key)
    print("[aitest] endpoint: \(settings.endpoint)")
    print("[aitest] default model: \(settings.model.isEmpty ? "(none)" : settings.model)")

    let catalog = AIModelCatalog()
    await catalog.load(settings: settings, force: true)
    if let error = catalog.error {
        print("[aitest] FAIL listing models: \(error)")
        exit(1)
    }
    print("[aitest] \(catalog.models.count) models listed; chat-capable first")
    print("[aitest] auto-selected model: \(settings.model.isEmpty ? "(none)" : settings.model)")
    guard !settings.model.isEmpty else {
        print("[aitest] FAIL: no model was selected — generation would 404")
        exit(1)
    }

    let status = await DiagramAI.test(settings: settings)
    print("[aitest] test connection: \(status)")
    guard status.hasPrefix("Connected") else { exit(1) }

    print("[aitest] generating a scene for: \(prompt)")
    do {
        let scene = try await SceneAI.generate(prompt: prompt, settings: settings) { step in
            print("[aitest]   \(step)")
        }
        let defects = SceneCritic.defects(scene)
        print("[aitest] scene: \(scene.elements.count) elements, \(defects.count) remaining issues")
        for element in scene.elements.prefix(8) {
            print("[aitest]   \(element.id) \(element.kind) at (\(Int(element.x)),\(Int(element.y))) \(Int(element.w))x\(Int(element.h)) text=\(element.text ?? "")")
        }
    } catch {
        print("[aitest] FAIL generating a scene: \(error.localizedDescription)")
        exit(1)
    }

    // Diagram mode goes through a different generator and a different
    // system prompt, so passing on scenes says nothing about it.
    print("[aitest] generating a diagram for the same prompt")
    do {
        let diagram = try await DiagramAI.generate(prompt: prompt, settings: settings) { step in
            print("[aitest]   \(step)")
        }
        print("[aitest] diagram: \(diagram.nodes.count) nodes, \(diagram.edges.count) connectors, valid=\(DiagramAI.isValid(diagram))")
        for node in diagram.nodes.prefix(6) {
            print("[aitest]   node \(node.id) [\(node.kind)] \(node.label)")
        }
        for edge in diagram.edges.prefix(6) {
            print("[aitest]   edge \(edge.from) -> \(edge.to) \(edge.label ?? "")")
        }
        guard DiagramAI.isValid(diagram) else {
            print("[aitest] FAIL: the diagram is structurally invalid")
            exit(1)
        }
        print("[aitest] AITEST PASS")
        exit(0)
    } catch {
        print("[aitest] FAIL generating a diagram: \(error.localizedDescription)")
        exit(1)
    }
}

/// Minimal delegate used in --install mode — does nothing except keep the
/// run loop alive so the InstallerWindow can display.
final class InstallModeDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { _ = InstallerWindowController() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
