import AppKit
import Combine

/// One page of the canvas. Each page is an independent drawing that keeps its
/// own annotations and its own pan/zoom view state, saved forever until the
/// user deletes it. Pages are stored together in a single JSON file.
struct CanvasPage: Codable, Identifiable {
    var id: UUID
    var name: String
    /// Optional description shown under the page name — a one-line summary of
    /// what the page is about (e.g. "Wireframes for the new onboarding").
    var note: String = ""
    var annotations: [PersistedAnnotation]
    var panX: CGFloat = 0
    var panY: CGFloat = 0
    var zoom: CGFloat = 1
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, annotations: [PersistedAnnotation] = []) {
        self.id = id
        self.name = name
        self.annotations = annotations
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

/// Holds every page and the one currently shown. The CanvasView renders the
/// current page's annotations and reports edits back here, which are written
/// to disk with every save. Page switching is done through `switchPage`, which
/// persists the outgoing page's view state first.
final class PagesManager: ObservableObject {
    @Published private(set) var pages: [CanvasPage] = []
    @Published private(set) var currentPageID: UUID = UUID()

    var currentPage: CanvasPage? {
        pages.first { $0.id == currentPageID }
    }

    var currentPageName: String {
        currentPage?.name ?? "Untitled"
    }

    private struct Store: Codable {
        var pages: [CanvasPage]
        var currentPageID: UUID
    }

    private var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("MacDraw", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pages.json")
    }

    private var legacyURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("MacDraw", isDirectory: true)
            .appendingPathComponent("annotations.json")
    }

    init() {
        if let data = try? Data(contentsOf: storeURL),
           let store = try? JSONDecoder().decode(Store.self, from: data),
           !store.pages.isEmpty {
            pages = store.pages
            currentPageID = store.pages.contains { $0.id == store.currentPageID } ? store.currentPageID : store.pages[0].id
            return
        }
        // First launch: adopt whatever the pre-pages version saved.
        var adopted: [PersistedAnnotation] = []
        if let data = try? Data(contentsOf: legacyURL) {
            adopted = (try? JSONDecoder().decode([PersistedAnnotation].self, from: data)) ?? []
        }
        let page = CanvasPage(name: "Untitled", annotations: adopted)
        pages = [page]
        currentPageID = page.id
        save()
        if !adopted.isEmpty {
            try? FileManager.default.removeItem(at: legacyURL)
        }
    }

    private func save() {
        let store = Store(pages: pages, currentPageID: currentPageID)
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    /// Self-test hook: wipe every page back to a single empty one.
    func selftestReset() {
        let page = CanvasPage(name: "Untitled")
        pages = [page]
        currentPageID = page.id
        save()
    }

    // MARK: - page operations

    @discardableResult
    func addPage(named name: String = "New page", description: String = "") -> UUID {
        var page = CanvasPage(name: name.isEmpty ? "New page" : name)
        page.note = description.trimmingCharacters(in: .whitespacesAndNewlines)
        pages.append(page)
        save()
        return page.id
    }

    func renamePage(id: UUID, to name: String) {
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        pages[i].name = trimmed.isEmpty ? "Untitled" : trimmed
        pages[i].updatedAt = Date()
        save()
    }

    /// Sets a page's description line.
    func setNote(id: UUID, to note: String) {
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[i].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        pages[i].updatedAt = Date()
        save()
    }

    /// Deletes a page (the last remaining page is never deleted). Returns the
    /// id of the page that should now be shown.
    @discardableResult
    func deletePage(id: UUID) -> UUID? {
        guard pages.count > 1, let i = pages.firstIndex(where: { $0.id == id }) else { return nil }
        pages.remove(at: i)
        if currentPageID == id {
            currentPageID = pages[min(i, pages.count - 1)].id
        }
        save()
        return currentPageID
    }

    func switchPage(id: UUID) {
        guard pages.contains(where: { $0.id == id }) else { return }
        currentPageID = id
        save()
    }

    // MARK: - current page contents + view state

    func currentAnnotations() -> [PersistedAnnotation] {
        currentPage?.annotations ?? []
    }

    /// Replaces the current page's annotations (used by the canvas save path).
    func updateCurrentAnnotations(_ items: [PersistedAnnotation]) {
        guard let i = pages.firstIndex(where: { $0.id == currentPageID }) else { return }
        pages[i].annotations = items
        pages[i].updatedAt = Date()
        save()
    }

    func viewState() -> (pan: CGPoint, zoom: CGFloat) {
        guard let p = currentPage else { return (.zero, 1) }
        return (CGPoint(x: p.panX, y: p.panY), p.zoom)
    }

    func setViewState(pan: CGPoint, zoom: CGFloat) {
        guard let i = pages.firstIndex(where: { $0.id == currentPageID }) else { return }
        pages[i].panX = pan.x
        pages[i].panY = pan.y
        pages[i].zoom = zoom
        save()
    }
}