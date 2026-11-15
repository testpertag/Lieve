import SwiftUI
import WebKit

struct BrowserView: View {
    let tab: BrowserTab
    @State private var showAddress = false
    @State private var showSettings = false
    @State private var toast: String?

    var body: some View {
        WebViewContainer(webView: tab.webView)
            .ignoresSafeArea(.container, edges: .bottom)
            .overlay(alignment: .top) { LoadingBar(tab: tab) }
            .overlay {
                FloatingMenu(tab: tab, showAddress: $showAddress, showSettings: $showSettings, toast: $toast)
            }
            .overlay(alignment: .top) { ToastView(message: $toast) }
            .sheet(isPresented: $showAddress) { AddressSheet(tab: tab) }
            .sheet(isPresented: $showSettings) { SettingsSheet(tab: tab) }
    }
}

/// UIKit WKWebView incorporata così com'è: updateUIView è vuoto,
/// quindi i ridisegni SwiftUI non toccano mai la WebView.
struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Vista separata: solo lei si aggiorna quando cambia il progresso.
private struct LoadingBar: View {
    let tab: BrowserTab
    var body: some View {
        ProgressView(value: tab.progress)
            .progressViewStyle(.linear)
            .tint(.red)
            .frame(height: 2)
            .opacity(tab.isLoading ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: tab.isLoading)
            .allowsHitTesting(false)
    }
}

private struct ToastView: View {
    @Binding var message: String?
    var body: some View {
        if let message {
            Text(message)
                .font(.footnote)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { self.message = nil }
                }
        }
    }
}
