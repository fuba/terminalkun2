// MIT License
import SwiftUI
import AVFoundation
import Combine
import TerminalCore
import TerminalTransport

struct QRKeyImportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var collector = QRTransferCollector()
    @State private var packet: QRTransfer?
    @State private var payload: QRKeyPayload?
    @State private var transferPhrase = ""
    @State private var keyPhrase = ""
    @State private var name = ""
    @State private var publicKey = ""
    @State private var busy = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    @State private var started = ProcessInfo.processInfo.systemUptime
    @State private var generation = UUID()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                if packet == nil {
                    VStack(spacing: 16) {
                        QRScannerView { receive($0) }.id(generation).frame(maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 16))
                        Text(collector.total == 0 ? "送信側の秘密鍵転送 QR を読み取る" : "\(collector.received) / \(collector.total) 枚 読み取り済み")
                            .accessibilityIdentifier("qrScanProgress")
                        if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                        Button("読み取りをやり直す") { clear() }
                    }.padding()
                } else {
                    Form {
                        if payload == nil {
                            Section("転送の復号") {
                                SecureField("転送用パスフレーズ（24文字）", text: $transferPhrase)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().accessibilityIdentifier("qrTransferPhrase")
                                Button("復号") { unlock() }.disabled(busy || transferPhrase.utf8.count != 24).accessibilityIdentifier("qrDecrypt")
                            }
                        } else {
                            Section {
                                TextField("鍵の名前", text: $name).accessibilityIdentifier("qrKeyName")
                                if publicKey.isEmpty {
                                    SecureField("元の鍵のパスフレーズ（ある場合）", text: $keyPhrase).privacySensitive()
                                    Button("鍵を確認") { inspectKey() }.disabled(busy)
                                } else {
                                    Text(publicKey.split(separator: " ").first.map(String.init) ?? "").textSelection(.enabled)
                                    Text(HostTrust.fingerprint(publicKey)).font(.system(.body, design: .monospaced)).textSelection(.enabled).accessibilityIdentifier("qrKeyFingerprint")
                                    Button("この iPhone に保存") { save() }.disabled(busy || name.isEmpty || name.utf8.count > 128).accessibilityIdentifier("qrSaveKey")
                                }
                            }
                            Section { Text("秘密鍵はこの端末だけの Keychain に保存します。パスフレーズは保存しません。").foregroundStyle(.secondary) }
                        }
                        if busy { ProgressView() }
                        if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                        Button("QR を読み直す") { clear() }.disabled(busy)
                    }
                }
            }
            .navigationTitle("QR から秘密鍵を取り込む").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { clear(); dismiss() } } }
        }
        .onDisappear { clear() }
        .onChange(of: scenePhase) { _, value in if value != .active { clear() } }
        .onReceive(timer) { _ in
            if ProcessInfo.processInfo.systemUptime - started > 300 || (packet.map { Date() > $0.expiresAt.addingTimeInterval(60) } ?? false) {
                clear(); error = "有効期限が切れました。送信側で QR を再生成してください。"
            }
        }
    }

    private func receive(_ text: String) {
        guard packet == nil, scenePhase == .active else { return }
        do {
            packet = try collector.append(text)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func unlock() {
        guard let packet, !busy else { return }
        busy = true; error = nil
        let phrase = transferPhrase, token = generation
        operation = Task { @MainActor in
            do {
                let value = try await Task.detached(priority: .userInitiated) { try packet.open(passphrase: phrase) }.value
                guard !Task.isCancelled, token == generation else { return }
                try packet.validateTime()
                payload = value; name = value.name; transferPhrase = ""; busy = false
                inspectKey()
            } catch {
                guard !Task.isCancelled, token == generation else { return }
                self.error = error.localizedDescription; busy = false
            }
        }
    }
    private func inspectKey() {
        guard let payload, !busy else { return }
        guard let pem = String(data: payload.key, encoding: .utf8),
              (payload.format == "openssh") == pem.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----") else {
            error = "秘密鍵の実際の内容と形式が一致しません。"; return
        }
        busy = true; error = nil
        let phrase = keyPhrase, token = generation
        operation = Task { @MainActor in
            do {
                let key = try await Task.detached(priority: .userInitiated) { try KeyMaterial.publicKey(pem: pem, passphrase: phrase, name: "") }.value
                guard !Task.isCancelled, token == generation else { return }
                publicKey = key; keyPhrase = ""; busy = false
            } catch {
                guard !Task.isCancelled, token == generation else { return }
                self.error = error.localizedDescription; busy = false
            }
        }
    }
    private func save() {
        do {
            guard let payload, let packet, !publicKey.isEmpty, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw AppError.message("鍵と名前を確認してください。") }
            try packet.validateTime()
            let fingerprint = HostTrust.fingerprint(publicKey)
            guard !store.configuration.keys.contains(where: { HostTrust.fingerprint($0.publicKey) == fingerprint }) else { throw AppError.message("この鍵はすでに保存されています。") }
            let key = SavedKey(name: name, publicKey: publicKey.split(separator: " ").prefix(2).joined(separator: " ") + " " + name)
            try SecureStore.set(payload.key, account: key.id.uuidString)
            store.configuration.keys.append(key)
            clear(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func clear() {
        generation = UUID(); operation?.cancel(); operation = nil
        collector = QRTransferCollector(); packet = nil; payload = nil
        transferPhrase = ""; keyPhrase = ""; publicKey = ""; name = ""; error = nil; busy = false
        started = ProcessInfo.processInfo.systemUptime
    }
}

private struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    func makeUIViewController(context: Context) -> QRScannerController { QRScannerController(onCode: onCode) }
    func updateUIViewController(_ controller: QRScannerController, context: Context) { controller.onCode = onCode }
    static func dismantleUIViewController(_ controller: QRScannerController, coordinator: ()) { controller.stop() }
}

private final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: (String) -> Void
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.fuba.terminalkun2.qr-camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private let message = UILabel()
    private var configured = false
    private var visible = false
    private var observers: [NSObjectProtocol] = []
    init(onCode: @escaping (String) -> Void) { self.onCode = onCode; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        message.textColor = .white; message.numberOfLines = 0; message.textAlignment = .center
        message.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(message)
        NSLayoutConstraint.activate([message.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), message.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), message.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.stop() })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.start() })
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); visible = true; start() }
    override func viewWillDisappear(_ animated: Bool) { visible = false; stop(); super.viewWillDisappear(animated) }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews(); preview?.frame = view.bounds
        let angle: CGFloat
        switch view.window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: angle = 0
        case .landscapeRight: angle = 180
        case .portraitUpsideDown: angle = 270
        default: angle = 90
        }
        if let connection = preview?.connection, connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
    }
    private func start() {
        guard visible, UIApplication.shared.applicationState == .active else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in DispatchQueue.main.async { self?.start() } }
        case .authorized:
            guard !configured else { queue.async { self.session.startRunning() }; return }
            configured = true
            queue.async {
                do {
                    guard let camera = AVCaptureDevice.default(for: .video) else { throw AppError.message("この端末ではカメラを利用できません。") }
                    let input = try AVCaptureDeviceInput(device: camera), output = AVCaptureMetadataOutput()
                    self.session.beginConfiguration()
                    guard self.session.canAddInput(input), self.session.canAddOutput(output) else { self.session.commitConfiguration(); throw AppError.message("QR カメラを開始できませんでした。") }
                    self.session.addInput(input); self.session.addOutput(output)
                    output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        let preview = AVCaptureVideoPreviewLayer(session: self.session); preview.videoGravity = .resizeAspectFill
                        self.view.layer.insertSublayer(preview, at: 0); self.preview = preview; self.view.setNeedsLayout()
                    }
                    self.session.startRunning()
                } catch { DispatchQueue.main.async { self.message.text = error.localizedDescription } }
            }
        default:
            message.text = "設定 → terminalkun2 でカメラへのアクセスを許可してください。"
            let button = UIButton(type: .system); button.setTitle("設定を開く", for: .normal)
            button.addAction(UIAction { _ in UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }, for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(button)
            NSLayoutConstraint.activate([button.centerXAnchor.constraint(equalTo: view.centerXAnchor), button.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 16)])
        }
    }
    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard visible, UIApplication.shared.applicationState == .active else { return }
        for case let object as AVMetadataMachineReadableCodeObject in metadataObjects { if let value = object.stringValue { onCode(value) } }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
