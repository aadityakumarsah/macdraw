import AppKit
import Combine

/// Version of a syncable page as stored on Supabase (`"Page"`).
struct RemotePage: Codable {
    var id: String
    var workspaceId: String
    var parentId: String?
    var name: String
    var description: String?
    var icon: String?
    var orderIndex: Int
    var contentJson: String
    var createdBy: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var version: Int
}

/// A raw websocket message coming back from the Supabase Realtime server.
private struct RealtimeEnvelope: Decodable {
    var event: String
    var payload: RealtimePayload
}

private struct RealtimePayload: Decodable {
    var status: String?
    var ids: [String]?
    var data: RealtimeData?
    var response: [String: String]?
}

private struct RealtimeData: Decodable {
    var table: String?
    var type: String?
    var record: RemotePage?
    var old_record: RemotePage?
}

/// Minimal Supabase client for the Mac app: password auth, PostgREST for
/// CRUD, and a Supabase-Realtime websocket channel for live cross-app sync.
/// Pulls feed the local store, pushes stream out of `PagesManager`, and
/// realtime reconciles both directions by stable page id.
final class SyncService: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    static let shared = SyncService()

    enum Phase: Equatable {
        case idle
        case signingIn
        case ready
        case error(String)
    }

    enum Connection: Equatable {
        case offline
        case connecting
        case connected
        case reconnecting
        case closed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var connection: Connection = .offline
    @Published private(set) var configuredAccount: String
    @Published private(set) var workspaceID: String?

    var isOnline: Bool {
        UserDefaults.standard.object(forKey: "macdraw.sync.online") as? Bool ?? true
    }

    // Test-account defaults; overridable via the eponymous UserDefaults keys.
    private static let projectURL = URL(string: "https://fabdvbwvuohznuhlsgqj.supabase.co")!
    private static let publishableKey =
        UserDefaults.standard.string(forKey: "macdraw.supabase.publishableKey")
        ?? "sb_publishable_N4gaQKtPRNi85x5V8kQl0Q_gjLit033"
    private static let defaultEmail = "demo@macdraw.app"
    private static let defaultPassword = "macdraw-demo-1234"

    private var accessToken: String?
    private var refreshToken: String?
    private var socket: URLSessionWebSocketTask?
    private var heartbeatTimer: Timer?
    private var reconnectAttempt = 0
    private var pushTask: DispatchWorkItem?
    /// Pages whose local content changed and await a server push.
    private var dirtyPageIDs = Set<String>()

    private let queue = DispatchQueue(label: "macdraw.sync", qos: .userInitiated)

    /// Hook into PagesManager so the manager can enqueue pushes on save and
    /// receive inserts/deletes from realtime.
    var pageSink: PageSyncSink?

    /// Cached snapshot of the signed-in user id (JWT `sub`).
    private(set) var currentRemoteUserID: String = ""
    var currentWorkspaceID: String { workspaceID ?? "" }

    override private init() {
        configuredAccount = UserDefaults.standard.string(forKey: "macdraw.sync.email") ?? Self.defaultEmail
        super.init()
    }

    /// App launch: try to sign in with the shared test account so the Mac
    /// starts in sync without any user action. Never blocks normal use.
    func start() {
        guard accessToken == nil else { return }
        phase = .signingIn
        queue.async { [weak self] in
            self?.signInBlocking()
        }
    }

    private func signInBlocking() {
        let email = UserDefaults.standard.string(forKey: "macdraw.sync.email") ?? Self.defaultEmail
        let password = UserDefaults.standard.string(forKey: "macdraw.sync.password") ?? Self.defaultPassword
        var req = URLRequest(url: Self.projectURL
            .appendingPathComponent("auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")]))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(Self.publishableKey, forHTTPHeaderField: "apikey")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "password": password])

        do {
            let (data, resp) = try sendSync(req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw SyncError.sync("auth failed (\((resp as? HTTPURLResponse)?.statusCode ?? -1))")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String,
                  let refresh = json["refresh_token"] as? String else {
                throw SyncError.sync("auth response malformed")
            }
            DispatchQueue.main.async { [weak self] in
                self?.accessToken = token
                self?.refreshToken = refresh
                self?.configuredAccount = email
                self?.phase = .ready
                self?.queue.async {
                    self?.bootstrap()
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.phase = .error("Couldn't sign in (\(email)). Offline sync is unaffected.")
                self?.connection = .offline
            }
        }
    }

    /// Ensure the user's default workspace exists (mirrors the web logic).
    private func bootstrap() {
        guard let token = accessToken else { return }
        do {
            let uid = try userID(token: token)
            currentRemoteUserID = uid
            if let ws = try fetchDefaultWorkspace(token: token, uid: uid) {
                DispatchQueue.main.async {
                    self.workspaceID = ws
                    self.startRealtime(workspace: ws)
                    self.pull(workspace: ws)
                }
                return
            }
            // No workspace yet — create one and self-join.
            let wsID = "workspace_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""))"
            let now = SyncService.rfc3339(Date())
            let email = UserDefaults.standard.string(forKey: "macdraw.sync.email") ?? Self.defaultEmail
            // Profile row must exist before the membership insert (FK on
            // userId). Wait to set defaultWorkspaceId until the workspace exists.
            _ = try postJSON(token: token, path: "/rest/v1/UserProfile?on_conflict=id",
                             headers: ["Prefer": "resolution=merge-duplicates,return=minimal"],
                             body: ["id": uid, "email": email,
                                    "name": email.components(separatedBy: "@").first ?? "",
                                    "updatedAt": now])
            _ = try postJSON(token: token, path: "/rest/v1/Workspace",
                             headers: ["Prefer": "return=minimal"],
                             body: ["id": wsID, "name": "Aaditya's Team", "createdBy": uid,
                                    "createdAt": now, "updatedAt": now])
            _ = try postJSON(token: token, path: "/rest/v1/WorkspaceMember",
                             headers: ["Prefer": "return=minimal"],
                             body: ["id": "member_\(UUID().uuidString)",
                                    "workspaceId": wsID, "userId": uid, "role": "owner",
                                    "createdAt": now])
            _ = try patchJSON(token: token, path: "/rest/v1/UserProfile?id=eq.\(uid)",
                              body: ["defaultWorkspaceId": wsID])
            DispatchQueue.main.async {
                self.workspaceID = wsID
                self.startRealtime(workspace: wsID)
            }
        } catch {
            DispatchQueue.main.async {
                if case .error = self.phase {} else {
                    self.phase = .error("Workspace bootstrap failed: \(error)")
                }
            }
        }
    }

    // MARK: - REST

    private struct AuthSource {
        let uid: String
    }

    private func userID(token: String) throws -> String {
        // Verify the JWT signature-less header as the profile "id".
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let header = try? JSONSerialization.jsonObject(
                  with: Data(base64url: String(parts[1])) ?? Data()) as? [String: Any],
              let sub = header["sub"] as? String else {
            throw SyncError.sync("jwt malformed")
        }
        return sub
    }

    private func fetchDefaultWorkspace(token: String, uid: String) throws -> String? {
        let (data, _) = try getJSON(token: token, path: "/rest/v1/UserProfile?select=defaultWorkspaceId&id=eq.\(uid)")
        if let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let first = list.first, let ws = first["defaultWorkspaceId"] as? String {
            return ws
        }
        return nil
    }

    /// Pull: fetch all non-deleted pages for the workspace and reconcile them
    /// into the local store.
    func pull(workspace: String) {
        guard let token = accessToken, isOnline else { return }
        connection = .connecting
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let path = "/rest/v1/Page?workspaceId=eq.\(workspace)&deletedAt=is.null&order=orderIndex.asc"
                let (data, _) = try self.getJSON(token: token, path: path)
                let remote = try JSONDecoder().decode([RemotePage].self, from: data)
                DispatchQueue.main.async {
                    self.pageSink?.applyRemote(pages: remote)
                    self.connection = self.socket == nil ? .closed : .connecting
                }
            } catch {
                DispatchQueue.main.async {
                    self.connection = .reconnecting
                }
            }
        }
    }

    /// Local pages pending a soft-delete on the server.
    private var deletedPending = Set<String>()

    /// Called from PagesManager.save() (main thread, debounced) so every edit
    /// ultimately lands on Supabase without hammering the API.
    func noteDirty(pageIDs: Set<String>) {
        guard isOnline else { return }
        guard let workspace = workspaceID, accessToken != nil else { return }
        dirtyPageIDs.formUnion(pageIDs)
        scheduleFlush()
    }

    func noteDeleted(pageID: String) {
        guard isOnline else { return }
        guard let workspace = workspaceID, accessToken != nil else { return }
        deletedPending.insert(pageID)
        scheduleFlush()
    }

    private func scheduleFlush() {
        pushTask?.cancel()
        pushTask = DispatchWorkItem { [weak self] in self?.flushPending() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: pushTask!)
    }

    private func flushPending() {
        guard let token = accessToken, let workspace = workspaceID else { return }
        queue.async { [weak self] in
            guard let self else { return }
            // Tombstone rows for locally-deleted pages.
            if !self.deletedPending.isEmpty {
                let deleted = self.deletedPending
                self.deletedPending = []
                for id in deleted {
                    do {
                        let body: [String: Any] = [
                            "deletedAt": SyncService.rfc3339(Date()),
                            "updatedAt": SyncService.rfc3339(Date()),
                        ]
                        _ = try self.patchJSON(token: token,
                                               path: "/rest/v1/Page?id=eq.\(id)&workspaceId=eq.\(workspace)",
                                               body: body)
                    } catch {
                        self.deletedPending.insert(id)
                    }
                }
            }
            let pending = self.dirtyPageIDs
            self.dirtyPageIDs = []
            let snapshot = self.pageSink?.snapshot(pagesForUpload: pending) ?? []
            do {
                for row in snapshot {
                    do {
                        _ = try self.upsertPage(token: token, workspace: workspace, remote: row)
                    } catch {
                        throw error
                    }
                }
            } catch {
                self.dirtyPageIDs.formUnion(pending)
                DispatchQueue.main.async {
                    self.connection = .reconnecting
                }
            }
        }
    }

    private func upsertPage(token: String, workspace: String, remote: RemotePage) throws -> Data {
        var body: [String: Any] = [
            "id": remote.id,
            "workspaceId": workspace,
            "parentId": NSNull(),
            "name": remote.name,
            "description": remote.description ?? NSNull(),
            "icon": remote.icon ?? NSNull(),
            "orderIndex": remote.orderIndex,
            "contentJson": remote.contentJson,
            "createdBy": remote.createdBy,
            "createdAt": remote.createdAt,
            "updatedAt": remote.updatedAt,
            "version": remote.version,
        ]
        if let del = remote.deletedAt { body["deletedAt"] = del } else { body["deletedAt"] = NSNull() }
        return try postJSON(token: token, path: "/rest/v1/Page",
                            headers: ["Prefer": "resolution=merge-duplicates,return=minimal", "on_conflict": "id"],
                            body: body)
    }

    // MARK: - HTTP plumbing

    /// Blocking request — only ever called from the sync background queue.
    private func sendSync(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        var result: Result<(Data, HTTPURLResponse), Error>?
        let sema = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, resp, err in
            if let err {
                result = .failure(err)
            } else if let data, let resp = resp as? HTTPURLResponse {
                result = .success((data, resp))
            } else {
                result = .failure(SyncError.sync("no response"))
            }
            sema.signal()
        }.resume()
        sema.wait()
        guard let result else { throw SyncError.sync("request cancelled") }
        return try result.get()
    }

    private func getJSON(token: String, path: String) throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: Self.projectURL) else {
            throw SyncError.sync("bad path \(path)")
        }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.publishableKey, forHTTPHeaderField: "apikey")
        let (data, resp) = try sendSync(req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SyncError.sync("GET \(path) -> \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return (data, http)
    }

    private func postJSON(token: String, path: String, headers: [String: String] = [:], body: [String: Any]) throws -> Data {
        guard let url = URL(string: path, relativeTo: Self.projectURL) else {
            throw SyncError.sync("bad path \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.publishableKey, forHTTPHeaderField: "apikey")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try sendSync(req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SyncError.sync("POST \(path) -> \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return data
    }

    private func patchJSON(token: String, path: String, body: [String: Any]) throws -> Data {
        guard let url = URL(string: path, relativeTo: Self.projectURL) else {
            throw SyncError.sync("bad path \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.publishableKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try sendSync(req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SyncError.sync("PATCH \(path) -> \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return data
    }

    // MARK: - Realtime (Supabase websocket protocol)

    private var realtimeURL: URL? {
        guard let token = accessToken else { return nil }
        var components = URLComponents(url: Self.projectURL.appendingPathComponent("realtime/v1/websocket"),
                                       resolvingAgainstBaseURL: false)
        components?.scheme = "wss"
        components?.queryItems = [
            URLQueryItem(name: "apikey", value: Self.publishableKey),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "vsn", value: "1.0.0"),
        ]
        return components?.url
    }

    private func startRealtime(workspace: String) {
        guard isOnline else { return }
        guard let url = realtimeURL, socket == nil else { return }
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        socket = task
        task.resume()
        connection = .connecting
        joinWorkspace(workspace)
        startHeartbeat()
    }

    /// phx_join for the public schema; filters realtime to OUR workspace.
    private func joinWorkspace(_ workspace: String) {
        guard socket != nil else { return }
        let payload: [String: Any] = [
            "config": [
                "broadcast": ["ack": false],
                "presence": ["key": ""],
                "postgres_changes": [
                    ["event": "*", "schema": "public", "table": "Page",
                     "filter": "workspaceId=eq.\(workspace)"],
                ],
            ],
        ]
        send(message: ["topic": "realtime:public", "event": "phx_join",
                       "payload": payload, "ref": "1"])
    }

    func send(message: [String: Any]) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: message),
              let str = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(str)) { _ in }
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            self?.send(message: ["topic": "phoenix", "event": "heartbeat",
                                 "payload": [String: Any](), "ref": "hb"])
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async { self.connection = .connected }
        receive()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.connection = .reconnecting
            self.socket = nil
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = nil
            self.scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard isOnline else { return }
        reconnectAttempt += 1
        let delay = min(30, 2 * reconnectAttempt)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(delay)) { [weak self] in
            guard let self, self.isOnline, let ws = self.workspaceID else { return }
            self.startRealtime(workspace: ws)
        }
    }

    private func receive() {
        guard let socket else { return }
        socket.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let text)):
                self.handleMessage(text)
                self.receive()
            case .failure:
                DispatchQueue.main.async {
                    self.connection = .reconnecting
                }
            default:
                self.receive()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(RealtimeEnvelope.self, from: data) else { return }
        guard envelope.event == "postgres_changes", let payload = envelope.payload.data else { return }

        let table = payload.table ?? ""
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if table == "Page" {
                self.reconcileRealtime(type: payload.type, record: payload.record, old: payload.old_record)
            }
        }
    }

    private func reconcileRealtime(type: String?, record: RemotePage?, old: RemotePage?) {
        guard isOnline else { return }
        if type == "INSERT", let page = record {
            pageSink?.applyRemote(pages: [page])
        } else if type == "UPDATE", let page = record {
            pageSink?.applyRemote(pages: [page])
        } else if type == "DELETE", let page = old {
            pageSink?.removeRemote(id: page.id)
        }
    }

    // MARK: - toggling

    func setOnline(_ online: Bool) {
        UserDefaults.standard.set(online, forKey: "macdraw.sync.online")
        if online {
            if accessToken == nil { start() } else if let ws = workspaceID { startRealtime(workspace: ws); pull(workspace: ws) }
        } else {
            socket?.cancel(with: .goingAway, reason: nil)
            socket = nil
            heartbeatTimer?.invalidate()
            heartbeatTimer = nil
            connection = .offline
        }
    }

    static func rfc3339(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}

enum SyncError: Error {
    case sync(String)
}

extension SyncService: SyncSource {}

/// What SyncService needs from the page store: remote rows in, local-store
/// snapshots out. Implemented by PagesManager.
protocol PageSyncSink: AnyObject {
    /// Build RemotePage rows for a set of local (dirty) page ids.
    func snapshot(pagesForUpload ids: Set<String>) -> [RemotePage]
    /// Insert/update local pages from remote rows (realtime or pull).
    func applyRemote(pages: [RemotePage])
    /// Remove a local page by stable remote id.
    func removeRemote(id: String)
}

/// What the page store needs from the sync service: dirty notifications go up,
/// server facts come back down. Implemented by SyncService.
protocol SyncSource: AnyObject {
    /// Mark pages as changed since the last flush (debounced push happens here).
    func noteDirty(pageIDs: Set<String>)
    /// Mark a page as deleted locally so its remote row gets soft-deleted.
    func noteDeleted(pageID: String)
    /// The current workspace id, for building server rows.
    var currentWorkspaceID: String { get }
    /// The signed-in user's Supabase id, for `createdBy`.
    var currentRemoteUserID: String { get }
}

extension Data {
    fileprivate init?(base64url: String) {
        var s = base64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if s.count % 4 != 0 { s += String(repeating: "=", count: 4 - s.count % 4) }
        self.init(base64Encoded: s)
    }
}