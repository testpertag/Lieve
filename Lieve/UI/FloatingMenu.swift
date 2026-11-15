import SwiftUI

/// Pulsante flottante trascinabile che si espande in una barra di comandi.
/// Si aggancia al bordo sinistro o destro; in orizzontale la barra diventa orizzontale.
struct FloatingMenu: View {
    let tab: BrowserTab
    @Binding var showAddress: Bool
    @Binding var showSettings: Bool
    @Binding var toast: String?
    private var media: MediaState { MediaState.shared }

    @State private var expanded = false
    @State private var anchor: CGPoint?
    @State private var dragOffset: CGSize = .zero

    private let bubble: CGFloat = 54
    private let button: CGFloat = 44
    private let spacing: CGFloat = 2
    private let padding: CGFloat = 6
    private let margin: CGFloat = 12
    private let itemCount: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let horizontal = geo.size.height < 450
            let size = expanded ? panelSize(horizontal: horizontal) : CGSize(width: bubble, height: bubble)
            let extraTop: CGFloat = (!expanded && media.videoPlaying) ? button + 8 : 0
            let center = clamp(anchor ?? defaultAnchor(in: geo.size), size: size, extraTop: extraTop, in: geo.size)

            Group {
                if expanded { panel(horizontal: horizontal) } else { bubbleView }
            }
            .position(x: center.x + dragOffset.width, y: center.y + dragOffset.height)
            .gesture(dragGesture(from: center, in: geo.size))
        }
        .sensoryFeedback(.impact(weight: .light), trigger: expanded)
    }

    // MARK: - Viste

    private var bubbleView: some View {
        bubbleButton
            .overlay(alignment: .top) {
                if media.videoPlaying {
                    RoutePicker()
                        .frame(width: button, height: button)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.15)))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                        .offset(y: -(button + 8))
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("AirPlay")
                }
            }
            .animation(.spring(duration: 0.3), value: media.videoPlaying)
    }

    private var bubbleButton: some View {
        Button(action: toggle) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: bubble, height: bubble)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.15)))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .opacity(0.9)
        .accessibilityLabel("Menu")
    }

    private func panel(horizontal: Bool) -> some View {
        let layout = horizontal
            ? AnyLayout(HStackLayout(spacing: spacing))
            : AnyLayout(VStackLayout(spacing: spacing))
        return layout {
            MenuButton("chevron.backward", "Indietro", enabled: tab.canGoBack) { tab.goBack() }
            MenuButton("chevron.forward", "Avanti", enabled: tab.canGoForward) { tab.goForward() }
            MenuButton(tab.isLoading ? "xmark" : "arrow.clockwise",
                       tab.isLoading ? "Interrompi" : "Ricarica") { tab.reloadOrStop() }
            MenuButton("magnifyingglass", "Indirizzo") { showAddress = true }
            MenuButton("gearshape", "Impostazioni") { showSettings = true }
            MenuButton("pip.enter", "Picture in Picture") { togglePiP() }
            RoutePicker()
                .frame(width: button, height: button)
                .accessibilityLabel("AirPlay")
            MenuButton("minus", "Chiudi menu", action: toggle)
        }
        .padding(padding)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    // MARK: - Azioni

    private func toggle() {
        withAnimation(.spring(duration: 0.3)) { expanded.toggle() }
    }

    private func togglePiP() {
        tab.togglePictureInPicture { result in
            let message: String?
            switch result {
            case .entered, .exited, .skip: message = nil
            case .noVideo: message = "Nessun video nella pagina"
            case .unsupported: message = "Il sito non consente il PiP qui: prova da schermo intero"
            case .failed: message = "Picture-in-Picture non disponibile"
            }
            if let message { withAnimation { toast = message } }
        }
    }

    // MARK: - Geometria

    private func panelSize(horizontal: Bool) -> CGSize {
        let long = itemCount * button + (itemCount - 1) * spacing + padding * 2
        let short = button + padding * 2
        return horizontal ? CGSize(width: long, height: short) : CGSize(width: short, height: long)
    }

    private func defaultAnchor(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width - margin - bubble / 2, y: size.height * 0.7)
    }

    private func clamp(_ p: CGPoint, size: CGSize, extraTop: CGFloat, in bounds: CGSize) -> CGPoint {
        let minX = margin + size.width / 2, maxX = bounds.width - margin - size.width / 2
        let minY = margin + extraTop + size.height / 2, maxY = bounds.height - margin - size.height / 2
        return CGPoint(x: min(max(p.x, minX), max(minX, maxX)),
                       y: min(max(p.y, minY), max(minY, maxY)))
    }

    private func dragGesture(from center: CGPoint, in bounds: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                let y = center.y + value.translation.height
                let droppedX = center.x + value.translation.width
                let x = droppedX < bounds.width / 2 ? margin + bubble / 2 : bounds.width - margin - bubble / 2
                withAnimation(.spring(duration: 0.35)) {
                    anchor = CGPoint(x: x, y: y)
                    dragOffset = .zero
                }
            }
    }
}

private struct MenuButton: View {
    let symbol: String
    let label: String
    let enabled: Bool
    let action: () -> Void

    init(_ symbol: String, _ label: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
