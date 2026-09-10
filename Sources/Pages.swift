import AppKit
import Combine

/// One page of the canvas. Each page is an independent drawing that keeps its
/// own annotations and its own pan/zoom view state, saved forever until the
/// user deletes it. Pages are stored together in a single JSON file.
///
/// The id is a *stable string* (UUID or workspace-suffixed) so the same page
/// is identified identically on the React Roadmap side and on Supabase —
/// pages created on the web and on the Mac reconcile by this id alone.
struct CanvasPage: Codable, Identifiable {
    var id: String
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

    init(id: String = UUID().uuidString, name: String, annotations: [PersistedAnnotation] = []) {
        self.id = id
        self.name = name
        self.annotations = annotations
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

/// The canvas payload stored in Supabase `"Page"."contentJson"`. Both clients
/// keep their own drawing JSON; name/description existence is the canonical
/// shared surface.
private struct SyncPageContent: Codable {
    var annotations: [PersistedAnnotation]
    var panX: CGFloat
    var panY: CGFloat
    var zoom: CGFloat
}

/// Holds every page and the one currently shown. The CanvasView renders the
/// current page's annotations and reports edits back here, which are written
/// to disk with every save. Page switching is done through `switchPage`, which
/// persists the outgoing page's view state first.
final class PagesManager: ObservableObject {
    @Published private(set) var pages: [CanvasPage] = []
    @Published private(set) var currentPageID: String = ""

    var currentPage: CanvasPage? {
        pages.first { $0.id == currentPageID }
    }

    var currentPageName: String {
        currentPage?.name ?? "Untitled"
    }

    private struct Store: Codable {
        var pages: [CanvasPage]
        var currentPageID: String
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

    /// Hook for the sync service. Set once at app start; every mutator marks
    /// its page ids dirty and `save()` writes locally + notifies the hook.
    var syncHook: SyncSource?

    /// Page ids with unsynced local changes since the last flush.
    private var dirty = Set<String>()

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
        // Debounced push to Supabase for every locally dirty page.
        if !dirty.isEmpty {
            let ids = dirty
            dirty = []
            DispatchQueue.main.async {
                self.syncHook?.noteDirty(pageIDs: ids)
            }
        }
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
    func addPage(named name: String = "New page", description: String = "") -> String {
        var page = CanvasPage(name: name.isEmpty ? "New page" : name)
        page.note = description.trimmingCharacters(in: .whitespacesAndNewlines)
        pages.append(page)
        dirty.insert(page.id)
        save()
        return page.id
    }

    func renamePage(id: String, to name: String) {
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        pages[i].name = trimmed.isEmpty ? "Untitled" : trimmed
        pages[i].updatedAt = Date()
        dirty.insert(id)
        save()
    }

    /// Sets a page's description line.
    func setNote(id: String, to note: String) {
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[i].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        pages[i].updatedAt = Date()
        dirty.insert(id)
        save()
    }

    /// Deletes a page (the last remaining page is never deleted). Returns the
    /// id of the page that should now be shown. Asks the sync service to soft
    /// delete the remote row too.
    @discardableResult
    func deletePage(id: String) -> String? {
        guard pages.count > 1, let i = pages.firstIndex(where: { $0.id == id }) else { return nil }
        pages.remove(at: i)
        if currentPageID == id {
            currentPageID = pages[min(i, pages.count - 1)].id
        }
        syncHook?.noteDeleted(pageID: id)
        save()
        return currentPageID
    }

    func switchPage(id: String) {
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
        dirty.insert(currentPageID)
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
        dirty.insert(currentPageID)
        save()
    }

    // MARK: - sync sink (remote → local)

    /// Serialize one local page into its server row.
    private func remoteRow(for page: CanvasPage) -> RemotePage {
        let content = SyncPageContent(
            annotations: page.annotations,
            panX: page.panX,
            panY: page.panY,
            zoom: page.zoom
        )
        let json = (try? JSONEncoder().encode(content)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return RemotePage(
            id: page.id,
            workspaceId: syncHook?.currentWorkspaceID ?? "",
            parentId: nil,
            name: page.name,
            description: page.note.isEmpty ? nil : page.note,
            icon: nil,
            orderIndex: 0,
            contentJson: json,
            createdBy: syncHook?.currentRemoteUserID ?? "",
            createdAt: SyncService.rfc3339(page.createdAt),
            updatedAt: SyncService.rfc3339(page.updatedAt),
            deletedAt: nil,
            version: 1
        )
    }

    /// Decode a remote row's canvas JSON into a local page's drawing.
    private func applyRemoteDrawing(to page: inout CanvasPage, remote: RemotePage) {
        guard !remote.contentJson.isEmpty,
              let data = remote.contentJson.data(using: .utf8),
              let content = try? JSONDecoder().decode(SyncPageContent.self, from: data) else { return }
        // Remote may be a placeholder ("{}") — keep existing drawing then.
        if !content.annotations.isEmpty {
            page.annotations = content.annotations
        }
        page.panX = content.panX
        page.panY = content.panY
        page.zoom = content.zoom
    }
}

// MARK: - PageSyncSink

extension PagesManager: PageSyncSink {
    func snapshot(pagesForUpload ids: Set<String>) -> [RemotePage] {
        pages.filter { ids.contains($0.id) }.map(remoteRow(for:))
    }

    /// Reconcile remote rows into the local store (pull + realtime, main).
    func applyRemote(pages remote: [RemotePage]) {
        for r in remote {
            applyOne(r)
        }
        save()
    }

    private func applyOne(_ r: RemotePage) {
        if r.deletedAt != nil {
            removeRemote(id: r.id)
            return
        }
        guard !r.name.isEmpty else { return }
        let remoteUpdated: Date
        if r.updatedAt.isEmpty {
            remoteUpdated = .distantPast
        } else {
            remoteUpdated = ISO8601DateFormatter().date(from: r.updatedAt) ?? .distantPast
        }

        if let i = pages.firstIndex(where: { $0.id == r.id }) {
            // Local already knows this page — apply only newer remote states.
            guard remoteUpdated >= pages[i].updatedAt else { return }
            var page = pages[i]
            page.name = r.name
            if let note = r.description, !note.isEmpty { page.note = note }
            page.updatedAt = remoteUpdated
            applyRemoteDrawing(to: &page, remote: r)
            pages[i] = page
            if page.id == currentPageID, let canvas = (NSApp.delegate as? AppDelegate)?.activeCanvas {
                canvas.applyCurrentPage()
            }
        } else {
            var page = CanvasPage(id: r.id, name: r.name)
            if let note = r.description { page.note = note }
            page.updatedAt = remoteUpdated
            applyRemoteDrawing(to: &page, remote: r)
            pages.append(page)
        }
    }

    func removeRemote(id: String) {
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        let removingCurrent = pages[i].id == currentPageID
        pages.remove(at: i)
        if removingCurrent {
            currentPageID = pages[0].id
            if let canvas = (NSApp.delegate as? AppDelegate)?.activeCanvas {
                canvas.applyCurrentPage()
            }
        }
    }
}