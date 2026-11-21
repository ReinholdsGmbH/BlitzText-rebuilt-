import AVFAudio
import Speech
import UIKit
import WebKit

/// Diktat direkt in der Tastatur, ohne in die App zu wechseln und ohne laufende Session.
///
/// Eine Tastaturerweiterung darf selbst nicht aufnehmen (audiomxd: "is an extension and doesn't
/// have entitlements to record audio"). Eine unsichtbare Web-Ansicht fragt das Mikrofon deshalb
/// über `getUserMedia` an; WebKits Medienprozess nimmt unter der Mikrofonfreigabe der App auf
/// und reicht die Samples an Swift weiter. Erkannt wird mit Apples Spracherkennung auf dem Gerät.
/// Das Mikrofon ist nur während des Diktats offen. Apple dokumentiert diesen Weg nicht; er kann
/// mit einem iOS-Update wegfallen. Dann bleibt der Weg über die App-Session.
/// Technik nach Hex (anomalyco/hex #1999, MIT), dort auf iOS 27.2 geprüft.
@MainActor
final class KeyboardDictation {
    enum State: Equatable {
        case idle, starting, recording, transcribing
    }

    var onState: ((State) -> Void)?
    var onText: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onState?(state) } }
    }

    /// Länger nimmt die Tastatur nicht auf: Die Samples liegen bis zum Ende im Speicher der
    /// Erweiterung, und deren Grenze liegt bei rund 170 MB.
    static let maximumSeconds: Double = 240
    /// Kommt in dieser Zeit kein Ton, ist der Start gescheitert.
    private static let startTimeout: TimeInterval = 5

    private weak var host: UIView?
    private var capture: WebCapture?
    private var samples = Data()
    private var sampleRate: Double = 48_000
    private var startWatchdog: Timer?
    private var transcription: Task<Void, Never>?

    init(host: UIView) {
        self.host = host
    }

    /// Web-Ansicht vorab laden, damit der erste Tipp ohne Ladezeit aufnimmt.
    func prepare() {
        guard capture == nil, let host else { return }
        capture = makeCapture(in: host)
    }

    func start() {
        guard state == .idle, let host else { return }
        samples = Data()
        let capture = capture ?? makeCapture(in: host)
        self.capture = capture
        state = .starting
        capture.start()
        startWatchdog = Timer.scheduledTimer(withTimeInterval: Self.startTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state == .starting else { return }
                self.capture?.stop()
                self.fail("Mikrofon startet nicht")
            }
        }
    }

    /// Aufnahme beenden und das Gesagte erkennen lassen.
    func stop() {
        guard state == .starting || state == .recording else { return }
        capture?.stop()
        finishRecording()
    }

    /// Aufnahme oder Erkennung verwerfen, etwa wenn die Tastatur verschwindet.
    func cancel() {
        startWatchdog?.invalidate()
        capture?.stop()
        transcription?.cancel()
        transcription = nil
        samples = Data()
        state = .idle
    }

    private func makeCapture(in host: UIView) -> WebCapture {
        let capture = WebCapture(host: host)
        capture.onEvent = { [weak self] event in self?.handle(event) }
        return capture
    }

    private func handle(_ event: WebCapture.Event) {
        switch event {
        case .started(let rate):
            startWatchdog?.invalidate()
            sampleRate = rate
            if state == .starting { state = .recording }
        case .samples(let data):
            guard state == .recording || state == .starting else { return }
            samples.append(data)
            if Double(samples.count) / 2 / sampleRate >= Self.maximumSeconds { stop() }
        case .failed(let message):
            capture?.stop()
            fail(Self.describe(message))
        case .processTerminated:
            capture?.tearDown()
            capture = nil
            if state == .recording { finishRecording() } else if state == .starting { fail("Aufnahme abgebrochen") }
        }
    }

    private func finishRecording() {
        startWatchdog?.invalidate()
        let pcm = samples
        let rate = sampleRate
        samples = Data()
        // Unter einer halben Sekunde ist nichts gesagt worden.
        guard Double(pcm.count) / 2 / rate >= 0.5 else {
            state = .idle
            return
        }
        state = .transcribing
        transcription = Task { [weak self] in
            do {
                let text = try await KeyboardSpeech.transcribe(pcm: pcm, sampleRate: rate)
                guard !Task.isCancelled, let self else { return }
                self.state = .idle
                self.onText?(text)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.fail((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func fail(_ message: String) {
        startWatchdog?.invalidate()
        samples = Data()
        state = .idle
        onFailure?(message)
    }

    /// Fehler aus der Web-Ansicht in Klartext.
    private static func describe(_ message: String) -> String {
        if message.contains("NotAllowedError") { return "Mikrofon für BlitzText nicht freigegeben" }
        if message.contains("NotFoundError") { return "Kein Mikrofon gefunden" }
        return "Aufnahme gescheitert: \(message)"
    }
}

// MARK: - Erkennung

private enum KeyboardSpeech {
    enum Failure: LocalizedError {
        case noLocale, empty

        var errorDescription: String? {
            switch self {
            case .noLocale: "Deutsche Spracherkennung fehlt auf diesem iPhone"
            case .empty: "Nichts verstanden"
            }
        }
    }

    static func transcribe(pcm: Data, sampleRate: Double) async throws -> String {
        let url = try writeWAV(pcm, sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await apple(url)
    }

    private static func apple(_ url: URL) async throws -> String {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "de-DE")) else {
            throw Failure.noLocale
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        // Beim ersten Mal lädt iOS das Sprachmodell; danach ist es installiert.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let collector = Task {
            var parts: [String] = []
            for try await result in transcriber.results {
                parts.append(String(result.text.characters))
            }
            return parts
        }
        let file = try AVAudioFile(forReading: url)
        let analyzer = try await SpeechAnalyzer(
            inputAudioFile: file, modules: [transcriber],
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse),
            finishAfterFile: true)
        let parts = try await collector.value
        // Der Analyzer muss leben, bis alle Ergebnisse da sind.
        withExtendedLifetime(analyzer) {}
        let text = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        guard !text.isEmpty else { throw Failure.empty }
        return text
    }

    /// 16-Bit-PCM, mono, in eine temporäre WAV-Datei.
    private static func writeWAV(_ pcm: Data, sampleRate: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("diktat-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
        let frames = AVAudioFrameCount(pcm.count / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
              let channel = buffer.int16ChannelData?[0] else {
            throw CocoaError(.fileWriteUnknown)
        }
        pcm.withUnsafeBytes { raw in
            channel.update(from: raw.bindMemory(to: Int16.self).baseAddress!, count: Int(frames))
        }
        buffer.frameLength = frames
        try file.write(from: buffer)
        return url
    }
}

// MARK: - Aufnahme über WebKit

@MainActor
private final class WebCapture: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    enum Event {
        case started(sampleRate: Double)
        case samples(Data)
        case failed(String)
        case processTerminated
    }

    var onEvent: ((Event) -> Void)?
    private let webView: WKWebView
    private var isLoaded = false
    private var startWhenLoaded = false

    init(host: UIView) {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 2, height: 2), configuration: configuration)
        super.init()
        configuration.userContentController.add(WeakHandler(self), name: "blitz")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isUserInteractionEnabled = false
        webView.alpha = 0.02
        host.addSubview(webView)
        webView.loadHTMLString(Self.page, baseURL: URL(string: "https://keyboard.blitztext.local/"))
    }

    func start() {
        guard isLoaded else {
            startWhenLoaded = true
            return
        }
        webView.evaluateJavaScript("blitzStart()")
    }

    func stop() {
        startWhenLoaded = false
        webView.evaluateJavaScript("blitzStop()")
    }

    func tearDown() {
        onEvent = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "blitz")
        webView.removeFromSuperview()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        if startWhenLoaded {
            startWhenLoaded = false
            start()
        }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        decisionHandler(type == .microphone ? .grant : .deny)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isLoaded = false
        onEvent?(.processTerminated)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "started":
            onEvent?(.started(sampleRate: (body["rate"] as? Double) ?? 48_000))
        case "pcm":
            if let encoded = body["data"] as? String, let data = Data(base64Encoded: encoded) { onEvent?(.samples(data)) }
        case "error":
            onEvent?(.failed((body["message"] as? String) ?? "unbekannt"))
        default:
            break
        }
    }

    /// Mikrofon ohne Echo- und Rauschfilter, Samples als 16-Bit-PCM in Base64 an Swift.
    private static let page = """
    <!doctype html><meta charset="utf-8"><script>
    let ctx, stream, source, node, running = false, revive = null;
    const post = (m) => webkit.messageHandlers.blitz.postMessage(m);
    async function blitzStart() {
      if (running) return;
      running = true;
      try {
        stream = await navigator.mediaDevices.getUserMedia({ audio: {
          channelCount: 1, echoCancellation: false, noiseSuppression: false, autoGainControl: false } });
        if (!running) { stream.getTracks().forEach((t) => t.stop()); return; }
        ctx = new AudioContext();
        await ctx.resume();
        source = ctx.createMediaStreamSource(stream);
        node = ctx.createScriptProcessor(4096, 1, 1);
        node.onaudioprocess = (event) => {
          if (!running) return;
          const input = event.inputBuffer.getChannelData(0);
          const pcm = new Int16Array(input.length);
          for (let i = 0; i < input.length; i++) {
            const s = Math.max(-1, Math.min(1, input[i]));
            pcm[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
          }
          const bytes = new Uint8Array(pcm.buffer);
          let binary = "";
          for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
          post({ type: "pcm", data: btoa(binary) });
        };
        source.connect(node);
        node.connect(ctx.destination);
        // iOS kann den Kontext für anderen Ton anhalten, ohne ihn fortzusetzen.
        revive = setInterval(() => {
          if (running && ctx && ctx.state !== "running" && ctx.state !== "closed") ctx.resume().catch(() => {});
        }, 250);
        post({ type: "started", rate: ctx.sampleRate });
      } catch (error) {
        running = false;
        if (stream) stream.getTracks().forEach((t) => t.stop());
        stream = null;
        post({ type: "error", message: (error && (error.name + ": " + error.message)) || String(error) });
      }
    }
    async function blitzStop() {
      running = false;
      if (revive) { clearInterval(revive); revive = null; }
      try { node && node.disconnect(); source && source.disconnect(); } catch (e) {}
      if (stream) stream.getTracks().forEach((t) => t.stop());
      if (ctx) { try { await ctx.close(); } catch (e) {} }
      ctx = stream = source = node = null;
    }
    </script>
    """
}

private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
