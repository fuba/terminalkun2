import SwiftUI
import Network
import TerminalCore
import TerminalTransport
import TerminalRenderer
import CoreText

@MainActor
final class AppStore: ObservableObject {
    @Published var configuration = AppConfiguration() { didSet { if loaded { persist(); applyAppearance() } } }
    @Published var sessions: [TerminalSession] = []
    @Published var selectedID: UUID?
    @Published var sheet: SheetRoute?
    @Published var error: String?
    @Published var authentication: AuthenticationPrompt?
    @Published var hostPrompt: HostPrompt?
    @Published var clipboard: ClipboardPrompt?
    @Published var pendingFiles: [URL] = []
    @Published var shareURLs: [URL] = []
    @Published var showShare = false
    let support: URL
    let documents: URL
    let logs: URL
    private var loaded = false
    private var modifiedAt: Date?
    private var configTimer: Timer?
    private let monitor = NWPathMonitor()
    private var lastNetworkAvailable = true
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var authQueue: [(ConnectionProfile, CheckedContinuation<SSHCredentials, Error>)] = []
    var selected: TerminalSession? { sessions.first { $0.id == selectedID } }
    var sortedProfiles: [ConnectionProfile] {
        configuration.profiles.sorted { a, b in a.favorite == b.favorite ? a.name.localizedStandardCompare(b.name) == .orderedAscending : a.favorite }
    }
    init() {
        let fm = FileManager.default
        support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TerminalKun2")
        documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        logs = support.appendingPathComponent("Logs")
        do {
            try fm.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.createDirectory(at: logs, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.createDirectory(at: documents, withIntermediateDirectories: true)
            if fm.fileExists(atPath: configURL.path) { configuration = try JSONDecoder().decode(AppConfiguration.self, from: Data(contentsOf: configURL)); modifiedAt = modificationDate() }
        } catch { self.error = "設定を読み込めませんでした。元のファイルは保持しています。\n" + error.localizedDescription }
        loaded = true
        registerFont()
        for record in configuration.sessions {
            sessions.append(TerminalSession(record: record, store: self))
        }
        selectedID = configuration.selectedSession ?? sessions.first?.id
        configTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.reloadConfiguration() } }
        monitor.pathUpdateHandler = { [weak self] path in Task { @MainActor in
            guard let self else { return }
            let available = path.status == .satisfied
            if available && !self.lastNetworkAvailable { self.sessions.filter { $0.state == .waiting }.forEach { $0.retryNow() } }
            self.lastNetworkAvailable = available
        } }
        monitor.start(queue: DispatchQueue(label: "dev.fuba.terminalkun2.network"))
        diagnostic("launch \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "")")
        applyAppearance()
    }
    var configURL: URL { support.appendingPathComponent("config.json") }
    func persist() {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: configURL, options: [.atomic, .completeFileProtection])
            modifiedAt = modificationDate()
        } catch { self.error = error.localizedDescription }
    }
    func snapshot() {
        configuration.sessions = sessions.map { SessionRecord(id: $0.id, profileID: $0.profileID, title: $0.title, draft: $0.draft.text) }
        configuration.selectedSession = selectedID
    }
    private func modificationDate() -> Date? { (try? FileManager.default.attributesOfItem(atPath: configURL.path)[.modificationDate]) as? Date }
    private func reloadConfiguration() {
        guard let date = modificationDate(), date != modifiedAt else { return }
        do {
            let config = try JSONDecoder().decode(AppConfiguration.self, from: Data(contentsOf: configURL))
            modifiedAt = date; configuration = config; error = nil
        } catch { modifiedAt = date; self.error = "設定ファイルが不正です。直前の設定を継続します。\n" + error.localizedDescription }
    }
    private func applyAppearance() {
        UIApplication.shared.isIdleTimerDisabled = configuration.appearance.keepScreenAwake
        for session in sessions { session.applyAppearance(configuration.appearance) }
    }
    func registerFont() {
        let url = support.appendingPathComponent("terminal-font")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
    func select(_ id: UUID) { selected?.terminal.resignFirstResponder(); selectedID = id; snapshot() }
    func newLocal() {
        let session = TerminalSession(record: .init(profileID: nil, title: "ローカル"), store: self)
        sessions.append(session); selectedID = session.id; session.startLocal(); snapshot(); sheet = nil
    }
    func connect(_ profile: ConnectionProfile, existing: TerminalSession? = nil) {
        let session = existing ?? TerminalSession(record: .init(profileID: profile.id, title: profile.name), store: self)
        if existing == nil { sessions.append(session) }
        selectedID = session.id; sheet = nil; snapshot(); session.connect(profile)
    }
    func close(_ session: TerminalSession) {
        session.stop(); sessions.removeAll { $0.id == session.id }
        if selectedID == session.id { selectedID = sessions.last?.id }; snapshot()
    }
    func nextTab(_ offset: Int) {
        guard !sessions.isEmpty else { return }
        let index = sessions.firstIndex { $0.id == selectedID } ?? 0
        select(sessions[(index + offset + sessions.count) % sessions.count].id)
    }
    func removeProfile(_ id: UUID) { configuration.profiles.removeAll { $0.id == id } }
    func authenticate(_ profile: ConnectionProfile) async throws -> SSHCredentials {
        if let id = profile.keyID, let data = try SecureStore.get(id.uuidString), let pem = String(data: data, encoding: .utf8), (try? KeyMaterial.authentication(pem: pem, passphrase: "", user: profile.user)) != nil {
            return SSHCredentials(privateKey: pem)
        }
        return try await withCheckedThrowingContinuation { continuation in
            authQueue.append((profile, continuation)); presentNextAuthentication()
        }
    }
    private func presentNextAuthentication() {
        guard authentication == nil, let next = authQueue.first else { return }
        authentication = AuthenticationPrompt(profile: next.0)
    }
    func finishAuthentication(password: String?, passphrase: String = "") {
        guard !authQueue.isEmpty else { return }
        let (profile, continuation) = authQueue.removeFirst(); authentication = nil
        if let password {
            do {
                let pem = try profile.keyID.flatMap { try SecureStore.get($0.uuidString) }.flatMap { String(data: $0, encoding: .utf8) }
                continuation.resume(returning: SSHCredentials(password: password, privateKey: pem, passphrase: passphrase))
            } catch { continuation.resume(throwing: error) }
        } else { continuation.resume(throwing: CancellationError()) }
        presentNextAuthentication()
    }
    func verifyHost(profile: ConnectionProfile, key: String) async throws {
        let account = "host:\(profile.host.lowercased()):\(profile.port)"
        if let data = try SecureStore.get(account) {
            if String(decoding: data, as: UTF8.self) == key { return }
            throw AppError.message("ホスト鍵が変わっています。接続を停止しました。\n\(profile.address)\n\(HostTrust.fingerprint(key))\n管理者に確認し、設定のホスト鍵一覧から旧鍵を削除してください。")
        }
        guard hostPrompt == nil else { throw AppError.message("別のホスト鍵確認が進行中です。") }
        let accepted: Bool = await withCheckedContinuation { continuation in hostPrompt = HostPrompt(profile: profile, key: key, continuation: continuation) }
        guard accepted else { throw SSHFailure.hostKeyRejected }
        try SecureStore.set(Data(key.utf8), account: account)
    }
    func acceptHost(_ accept: Bool) { let prompt = hostPrompt; hostPrompt = nil; prompt?.continuation.resume(returning: accept) }
    func importSSHConfig(_ url: URL, remember: Bool = true) throws {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let result = try SSHConfig.parse(String(contentsOf: url, encoding: .utf8))
        for var profile in result.profiles {
            if let i = configuration.profiles.firstIndex(where: { $0.name == profile.name }) {
                let old = configuration.profiles[i]; profile.id = old.id; profile.favorite = old.favorite; profile.keyID = old.keyID
                configuration.profiles[i] = profile
            } else { configuration.profiles.append(profile) }
        }
        if remember { configuration.sshConfigBookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) }
        if !result.warnings.isEmpty { error = result.warnings.joined(separator: "\n") }
    }
    func syncSSHConfig() {
        guard let data = configuration.sshConfigBookmark else { return }
        do { var stale = false; let url = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale); try importSSHConfig(url, remember: stale) }
        catch { self.error = "SSH config を同期できませんでした。\n" + error.localizedDescription }
    }
    func sceneChanged(_ phase: ScenePhase) {
        if phase == .background {
            snapshot(); sessions.forEach { $0.resetInput() }
            if sessions.contains(where: { $0.state == .connected }), backgroundTask == .invalid {
                backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish SSH writes") { [weak self] in Task { @MainActor in self?.endBackgroundTask() } }
            }
        } else if phase == .active {
            endBackgroundTask(); syncSSHConfig(); sessions.filter { $0.state == .waiting }.forEach { $0.retryNow() }
        }
    }
    private func endBackgroundTask() { if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid } }
    func open(_ url: URL) {
        if ["ssh", "terminalkun2"].contains(url.scheme?.lowercased() ?? ""), let host = url.host {
            let profile = configuration.profiles.first { $0.host == host && $0.user == (url.user ?? "") && $0.port == (url.port ?? 22) }
            if let profile { connect(profile) }
            else { sheet = .edit(ConnectionProfile(name: host, host: host, user: url.user ?? "", port: url.port ?? 22)) }
        } else if url.isFileURL { pendingFiles.append(url) }
    }
    func diagnostic(_ text: String) {
        let url = logs.appendingPathComponent("app.log")
        let data = Data("\(Date().formatted(.iso8601)) \(text)\n".utf8)
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 2 * 1024 * 1024 { try? Data().write(to: url) }
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        if let handle = try? FileHandle(forWritingTo: url) { defer { try? handle.close() }; _ = try? handle.seekToEnd(); try? handle.write(contentsOf: data) }
    }
}

enum SheetRoute: Identifiable {
    case connections, settings, edit(ConnectionProfile), keys, dictionary, voice, help
    var id: String { switch self { case .connections: return "connections"; case .settings: return "settings"; case .edit(let p): return p.id.uuidString; case .keys: return "keys"; case .dictionary: return "dictionary"; case .voice: return "voice"; case .help: return "help" } }
}
struct AuthenticationPrompt: Identifiable { let id = UUID(); let profile: ConnectionProfile }
struct HostPrompt: Identifiable { let id = UUID(); let profile: ConnectionProfile; let key: String; let continuation: CheckedContinuation<Bool, Never> }
struct ClipboardPrompt: Identifiable { let id = UUID(); let text: String }
