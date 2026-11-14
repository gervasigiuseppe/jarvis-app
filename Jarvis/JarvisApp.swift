// Jarvis per iPhone: un guscio che apre a schermo intero la pagina di Jarvis sull'iMac.
import SwiftUI
import WebKit
import AVFoundation
import AppIntents

let INDIRIZZO = URL(string: "https://imac-xubuntu.tail2a81df.ts.net/")!

@main
struct JarvisApp: App {
    init() {
        // microfono e altoparlante insieme, voce forte dall'altoparlante
        let sessione = AVAudioSession.sharedInstance()
        try? sessione.setCategory(.playAndRecord, mode: .default,
                                  options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? sessione.setActive(true)
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
        impostazioni.applicationNameForUserAgent = "JarvisApp/1.0 Mobile/15E148 Safari/604.1"

        let pagina = WKWebView(frame: .zero, configuration: impostazioni)
        pagina.uiDelegate = context.coordinator
        pagina.navigationDelegate = context.coordinator
        pagina.isOpaque = false
        pagina.backgroundColor = .black
        pagina.scrollView.backgroundColor = .black
        pagina.scrollView.bounces = false
        pagina.allowsBackForwardNavigationGestures = false
        context.coordinator.pagina = pagina
        context.coordinator.carica()
        return pagina
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

final class Regista: NSObject, WKUIDelegate, WKNavigationDelegate {
    weak var pagina: WKWebView?
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

    // Se l'iMac non risponde: messaggio chiaro e nuovo tentativo ogni 5 secondi.
    private func nonRaggiungibile() {
        guard !tentativoInAttesa else { return }
        tentativoInAttesa = true
        let html = """
        <html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>
        <body style='background:#000;color:#ff9d3c;font-family:-apple-system;text-align:center;padding-top:38vh;font-size:20px'>
        Jarvis non risponde.<br><br>
        <span style='color:#999;font-size:15px'>Controlli che Tailscale sia acceso sul telefono<br>e che l'iMac sia acceso. Riprovo da solo.</span>
        </body></html>
        """
        pagina?.loadHTMLString(html, baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.carica() }
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
