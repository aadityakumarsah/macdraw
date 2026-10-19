import AppKit
import Combine

/// One page of the canvas. Each page is an independent drawing that keeps its
/// own annotations and its own pan/zoom view state, saved forever until the
/// user deletes it.
///
/// On disk a page is two things: a row in `index.json` (name, note, view
/// state, timestamps) and its own `pages/<id>.json` holding the drawing.
/// Keeping them apart is what makes a big library cheap — panning page 1 does
/// not rewrite page 2, and only the pages you actually open are decoded into
/// memory.
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
    /// The drawing. Empty while the page is on disk but not open — ask
    /// `PagesManager` for it rather than reading this directly.
    var annotations: [PersistedAnnotation]
    var panX: CGFloat = 0
    var panY: CGFloat = 0
    var zoom: CGFloat = 1
    var createdAt: Date
    var updatedAt: Date
    /// How many elements the page holds, known even when it isn't loaded.
    var elementCount: Int = 0

    init(id: String = UUID().uuidString, name: String, annotations: [PersistedAnnotation] = []) {
        self.id = id
        self.name = name
        self.annotations = annotations
        self.elementCount = annotations.count
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // Decoding is tolerant on purpose. `CanvasPage` is only ever decoded from
    // the pre-split `pages.json`, written by older builds that had fewer
    // fields — and Swift's synthesized decoder ignores property defaults, so
    // one missing key would throw away the user's whole library.
    private enum CodingKeys: String, CodingKey {
        case id, name, note, annotations, panX, panY, zoom, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "Untitled"
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        annotations = (try? c.decode([PersistedAnnotation].self, forKey: .annotations)) ?? []
        panX = (try? c.decode(CGFloat.self, forKey: .panX)) ?? 0
        panY = (try? c.decode(CGFloat.self, forKey: .panY)) ?? 0
        zoom = (try? c.decode(CGFloat.self, forKey: .zoom)) ?? 1
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
        elementCount = annotations.count
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

extension PersistedAnnotation {
    /// Moves inline base64 image bytes out into the blob store, leaving only
    /// the id behind. Used when adopting a legacy save or a scene that
    /// arrived over sync.
    mutating func externalizeImage() {
        guard imageFileID == nil,
              let legacy = imagePNG,
              let data = Data(base64Encoded: legacy) else { return }
        imageFileID = FileStore.shared.store(data: data, ext: "png")
        imagePNG = nil
    }

    /// The reverse: inlines the image so a client without access to this
    /// Mac's blob store (the web app, another device) still sees it.
    func inliningImage() -> PersistedAnnotation {
        guard imagePNG == nil, let id = imageFileID,
              let data = FileStore.shared.data(for: id) else { return self }
        var copy = self
        copy.imagePNG = data.base64EncodedString()
        return copy
    }
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

    /// `index.json` — one small row per page. Rewritten when a name, note or
    /// view state changes; never carries drawing data.
    private struct Index: Codable {
        var pages: [PageMeta]
        var currentPageID: String
    }

    private struct PageMeta: Codable {
        var id: String
        var name: String
        var note: String
        var panX: CGFloat
        var panY: CGFloat
        var zoom: CGFloat
        var createdAt: Date
        var updatedAt: Date
        var elementCount: Int?
    }

    /// Legacy single-file store: `{ pages: [...], currentPageID }` with every
    /// drawing — and every base64 image — in one blob.
    private struct LegacyStore: Codable {
        var pages: [CanvasPage]
        var currentPageID: String
    }

    private var indexURL: URL { AppStorage.file("index.json") }
    private var pagesDirectory: URL { AppStorage.directory("pages") }
    private func pageURL(_ id: String) -> URL {
        pagesDirectory.appendingPathComponent("\(id).json")
    }

    private var legacyStoreURL: URL { AppStorage.file("pages.json") }
    private var legacyAnnotationsURL: URL { AppStorage.file("annotations.json") }

    /// Ids whose drawing is currently decoded in `pages[].annotations`, most
    /// recently used last. Pages fall out of memory when the window grows;
    /// their file on disk is the source of truth.
    private var loadedOrder: [String] = []
    private let maxLoadedPages = 4

    /// Hook for the sync service. Set once at app start; every mutator marks
    /// its page ids dirty and `save()` writes locally + notifies the hook.
    var syncHook: SyncSource?

    /// Page ids with unsynced local changes since the last flush.
    private var dirty = Set<String>()
    /// Coalesces index writes — pan/zoom updates arrive continuously.
    private var indexWriteScheduled = false

    init() {
        // Preference order: the split store, then a legacy single-file save
        // to adopt, then a fresh library.
        if !loadIndex(), !adoptLegacyStore() {
            let page = CanvasPage(name: "Untitled")
            pages = [page]
            currentPageID = page.id
            loadedOrder = [page.id]
            writePage(page.id)
            writeIndexNow()
        }
        ensureLoaded(currentPageID)
    }

    // MARK: - loading

    private func loadIndex() -> Bool {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(Index.self, from: data),
              !index.pages.isEmpty else { return false }
        pages = index.pages.map { meta in
            var p = CanvasPage(id: meta.id, name: meta.name)
            p.note = meta.note
            p.panX = meta.panX
            p.panY = meta.panY
            p.zoom = meta.zoom
            p.createdAt = meta.createdAt
            p.updatedAt = meta.updatedAt
            p.elementCount = meta.elementCount ?? 0
            p.annotations = []
            return p
        }
        currentPageID = pages.contains { $0.id == index.currentPageID }
            ? index.currentPageID
            : pages[0].id
        return true
    }

    /// First run on a build with the split store: fold the old monolithic
    /// `pages.json` (or the even older `annotations.json`) into per-page files
    /// and push every inline image into the blob store.
    @discardableResult
    private func adoptLegacyStore() -> Bool {
        var adoptedPages: [CanvasPage] = []
        var adoptedCurrent = ""

        if let data = try? Data(contentsOf: legacyStoreURL),
           let store = try? JSONDecoder().decode(LegacyStore.self, from: data),
           !store.pages.isEmpty {
            adoptedPages = store.pages
            adoptedCurrent = store.currentPageID
        } else if let data = try? Data(contentsOf: legacyAnnotationsURL),
                  let items = try? JSONDecoder().decode([PersistedAnnotation].self, from: data) {
            adoptedPages = [CanvasPage(name: "Untitled", annotations: items)]
        }
        guard !adoptedPages.isEmpty else { return false }

        for i in adoptedPages.indices {
            for j in adoptedPages[i].annotations.indices {
                adoptedPages[i].annotations[j].externalizeImage()
            }
            adoptedPages[i].elementCount = adoptedPages[i].annotations.count
        }
        pages = adoptedPages
        currentPageID = adoptedPages.contains { $0.id == adoptedCurrent }
            ? adoptedCurrent
            : adoptedPages[0].id
        loadedOrder = adoptedPages.map(\.id)
        for p in adoptedPages { writePage(p.id) }
        writeIndexNow()
        // Keep the old file as a backup rather than deleting a user's only
        // copy of their drawings.
        let backup = AppStorage.file("pages.json.pre-split-backup")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: legacyStoreURL, to: backup)
        try? FileManager.default.removeItem(at: legacyAnnotationsURL)
        trimLoaded()
        return true
    }

    /// Makes sure a page's drawing is in memory. Called before anything reads
    /// or writes `annotations` for that page.
    func ensureLoaded(_ id: String) {
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        if loadedOrder.contains(id) {
            touchLoaded(id)
            return
        }
        if let data = try? Data(contentsOf: pageURL(id)),
           let items = try? JSONDecoder().decode([PersistedAnnotation].self, from: data) {
            pages[i].annotations = items
            pages[i].elementCount = items.count
        } else {
            pages[i].annotations = []
        }
        loadedOrder.append(id)
        trimLoaded()
    }

    private func touchLoaded(_ id: String) {
        if let i = loadedOrder.firstIndex(of: id) {
            loadedOrder.remove(at: i)
            loadedOrder.append(id)
        }
    }

    /// Drops the drawings of pages the user isn't looking at. Their files are
    /// already written, so this costs nothing but reclaims the memory.
    private func trimLoaded() {
        while loadedOrder.count > maxLoadedPages {
            guard let id = loadedOrder.first(where: { $0 != currentPageID }) else { break }
            loadedOrder.removeAll { $0 == id }
            if let i = pages.firstIndex(where: { $0.id == id }) {
                pages[i].annotations = []
            }
        }
    }

    // MARK: - saving

    /// Writes one page's drawing. Encoding happens on the calling thread (so
    /// the array is read while nothing else can mutate it) and the file write
    /// itself goes to the io queue.
    private func writePage(_ id: String) {
        guard let page = pages.first(where: { $0.id == id }) else { return }
        guard loadedOrder.contains(id) || !page.annotations.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(page.annotations) else { return }
        AppStorage.writeAsync(data, to: pageURL(id))
    }

    private func indexSnapshot() -> Index {
        Index(
            pages: pages.map { p in
                PageMeta(
                    id: p.id, name: p.name, note: p.note,
                    panX: p.panX, panY: p.panY, zoom: p.zoom,
                    createdAt: p.createdAt, updatedAt: p.updatedAt,
                    elementCount: p.elementCount
                )
            },
            currentPageID: currentPageID
        )
    }

    private func writeIndexNow() {
        guard let data = try? JSONEncoder().encode(indexSnapshot()) else { return }
        AppStorage.writeAsync(data, to: indexURL)
    }

    /// Coalesces index writes: pan/zoom reports arrive on every scroll frame
    /// and rewriting the index for each one was pure I/O churn.
    private func scheduleIndexWrite() {
        guard !indexWriteScheduled else { return }
        indexWriteScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.indexWriteScheduled = false
            self.writeIndexNow()
        }
    }

    private func flushDirtyToSync() {
        guard !dirty.isEmpty else { return }
        let ids = dirty
        dirty = []
        DispatchQueue.main.async {
            self.syncHook?.noteDirty(pageIDs: ids)
        }
    }

    /// Writes the index (and notifies sync) after a metadata change.
    private func save() {
        scheduleIndexWrite()
        flushDirtyToSync()
    }

    /// Self-test hook: wipe every page back to a single empty one.
    func selftestReset() {
        for p in pages {
            try? FileManager.default.removeItem(at: pageURL(p.id))
        }
        let page = CanvasPage(name: "Untitled")
        pages = [page]
        currentPageID = page.id
        loadedOrder = [page.id]
        writePage(page.id)
        writeIndexNow()
    }

    // MARK: - page operations

    @discardableResult
    func addPage(named name: String = "New page", description: String = "") -> String {
        var page = CanvasPage(name: name.isEmpty ? "New page" : name)
        page.note = description.trimmingCharacters(in: .whitespacesAndNewlines)
        pages.append(page)
        loadedOrder.append(page.id)
        dirty.insert(page.id)
        writePage(page.id)
        save()
        trimLoaded()
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
        loadedOrder.removeAll { $0 == id }
        let url = pageURL(id)
        AppStorage.io.async { try? FileManager.default.removeItem(at: url) }
        if currentPageID == id {
            currentPageID = pages[min(i, pages.count - 1)].id
            ensureLoaded(currentPageID)
        }
        syncHook?.noteDeleted(pageID: id)
        writeIndexNow()
        flushDirtyToSync()
        return currentPageID
    }

    func switchPage(id: String) {
        guard pages.contains(where: { $0.id == id }) else { return }
        currentPageID = id
        ensureLoaded(id)
        writeIndexNow()
    }

    // MARK: - current page contents + view state

    func currentAnnotations() -> [PersistedAnnotation] {
        ensureLoaded(currentPageID)
        return currentPage?.annotations ?? []
    }

    /// Replaces the current page's annotations (used by the canvas save path).
    func updateCurrentAnnotations(_ items: [PersistedAnnotation]) {
        guard let i = pages.firstIndex(where: { $0.id == currentPageID }) else { return }
        pages[i].annotations = items
        pages[i].elementCount = items.count
        pages[i].updatedAt = Date()
        touchLoaded(currentPageID)
        dirty.insert(currentPageID)
        writePage(currentPageID)
        save()
    }

    func viewState() -> (pan: CGPoint, zoom: CGFloat) {
        guard let p = currentPage else { return (.zero, 1) }
        return (CGPoint(x: p.panX, y: p.panY), p.zoom)
    }

    func setViewState(pan: CGPoint, zoom: CGFloat) {
        guard let i = pages.firstIndex(where: { $0.id == currentPageID }) else { return }
        guard pages[i].panX != pan.x || pages[i].panY != pan.y || pages[i].zoom != zoom else { return }
        pages[i].panX = pan.x
        pages[i].panY = pan.y
        pages[i].zoom = zoom
        dirty.insert(currentPageID)
        save()
    }

    // MARK: - storage housekeeping

    /// Every blob id any page references. Used at launch to delete orphaned
    /// images left behind by deleted elements.
    func referencedFileIDs() -> Set<String> {
        var ids = Set<String>()
        for page in pages {
            let items: [PersistedAnnotation]
            if loadedOrder.contains(page.id) {
                items = page.annotations
            } else if let data = try? Data(contentsOf: pageURL(page.id)),
                      let decoded = try? JSONDecoder().decode([PersistedAnnotation].self, from: data) {
                items = decoded
            } else {
                items = []
            }
            for a in items {
                if let id = a.imageFileID { ids.insert(id) }
            }
        }
        return ids
    }

    /// Deletes stored images nothing references any more. Safe to run at
    /// launch, after the index and the current page are in place.
    func collectStorageGarbage() {
        let keep = referencedFileIDs()
        FileStore.shared.collectGarbage(keeping: keep)
    }

    // MARK: - sync sink (remote → local)

    /// Serialize one local page into its server row.
    private func remoteRow(for page: CanvasPage) -> RemotePage {
        // Other clients can't read this Mac's blob store, so the sync payload
        // carries the image bytes inline even though the local file never
        // does.
        let content = SyncPageContent(
            annotations: page.annotations.map { $0.inliningImage() },
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
            page.annotations = content.annotations.map { item in
                var copy = item
                copy.externalizeImage()
                return copy
            }
            page.elementCount = page.annotations.count
        }
        page.panX = content.panX
        page.panY = content.panY
        page.zoom = content.zoom
    }
}

// MARK: - PageSyncSink

extension PagesManager: PageSyncSink {
    /// Called from the sync queue. The page array lives on the main thread,
    /// so the snapshot is taken there — reading it across threads while the
    /// user draws is a data race.
    func snapshot(pagesForUpload ids: Set<String>) -> [RemotePage] {
        if Thread.isMainThread {
            return snapshotOnMain(ids)
        }
        return DispatchQueue.main.sync { self.snapshotOnMain(ids) }
    }

    private func snapshotOnMain(_ ids: Set<String>) -> [RemotePage] {
        for id in ids { ensureLoaded(id) }
        let rows = pages.filter { ids.contains($0.id) }.map(remoteRow(for:))
        trimLoaded()
        return rows
    }

    /// Reconcile remote rows into the local store (pull + realtime, main).
    func applyRemote(pages remote: [RemotePage]) {
        for r in remote {
            applyOne(r)
        }
        writeIndexNow()
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

        if let existing = pages.firstIndex(where: { $0.id == r.id }) {
            // Local already knows this page — apply only newer remote states.
            guard remoteUpdated >= pages[existing].updatedAt else { return }
            ensureLoaded(r.id)
            guard let idx = pages.firstIndex(where: { $0.id == r.id }) else { return }
            var page = pages[idx]
            page.name = r.name
            if let note = r.description, !note.isEmpty { page.note = note }
            page.updatedAt = remoteUpdated
            applyRemoteDrawing(to: &page, remote: r)
            pages[idx] = page
            writePage(page.id)
            if page.id == currentPageID, let canvas = (NSApp.delegate as? AppDelegate)?.activeCanvas {
                canvas.applyCurrentPage()
            }
        } else {
            var page = CanvasPage(id: r.id, name: r.name)
            if let note = r.description { page.note = note }
            page.updatedAt = remoteUpdated
            applyRemoteDrawing(to: &page, remote: r)
            pages.append(page)
            loadedOrder.append(page.id)
            writePage(page.id)
            trimLoaded()
        }
    }

    func removeRemote(id: String) {
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        let removingCurrent = pages[i].id == currentPageID
        pages.remove(at: i)
        loadedOrder.removeAll { $0 == id }
        let url = pageURL(id)
        AppStorage.io.async { try? FileManager.default.removeItem(at: url) }
        if removingCurrent {
            currentPageID = pages[0].id
            ensureLoaded(currentPageID)
            if let canvas = (NSApp.delegate as? AppDelegate)?.activeCanvas {
                canvas.applyCurrentPage()
            }
        }
    }
}
