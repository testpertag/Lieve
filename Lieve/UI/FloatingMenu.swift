import UIKit
import AVKit

/// Menu flottante in UIKit. Le sue viste occupano solo lo spazio dei pulsanti:
/// nessun livello a tutto schermo sopra la WebView, quindi nessuna interferenza con i suoi gesti.
@MainActor
final class FloatingMenu: NSObject {
    enum Action: Int, CaseIterable {
        case back, forward, reload, address, pip, settings
    }

    var onAction: ((Action) -> Void)?

    private weak var host: UIView?
    private let bubble = FloatingMenu.makeBlur()
    private let bubbleButton = UIButton(type: .system)
    private let airPlayBubble = FloatingMenu.makeBlur()
    private let airPlayPicker = AVRoutePickerView()
    private let panel = FloatingMenu.makeBlur()
    private let panelPicker = AVRoutePickerView()
    private let stack = UIStackView()
    private var buttons: [Action: UIButton] = [:]
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var expanded = false
    private var showAirPlay = false
    private var anchor: CGPoint?           // centro della bolla, coordinate della vista host
    private var dragStart: CGPoint = .zero

    private let bubbleSize: CGFloat = 54
    private let buttonSize: CGFloat = 44
    private let spacing: CGFloat = 2
    private let padding: CGFloat = 6
    private let margin: CGFloat = 12
    private let itemCount: CGFloat = 8

    init(host: UIView) {
        self.host = host
        super.init()
        buildBubble()
        buildAirPlayBubble()
        buildPanel()
        host.addSubview(airPlayBubble)
        host.addSubview(panel)
        host.addSubview(bubble)
        for view in [bubble, panel] {
            view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
        }
        applyVisibility()
    }

    // MARK: - Stato

    func update(canGoBack: Bool, canGoForward: Bool, isLoading: Bool, videoPlaying: Bool) {
        buttons[.back]?.isEnabled = canGoBack
        buttons[.forward]?.isEnabled = canGoForward
        buttons[.reload]?.setImage(Self.symbol(isLoading ? "xmark" : "arrow.clockwise"), for: .normal)
        buttons[.reload]?.accessibilityLabel = isLoading ? "Interrompi" : "Ricarica"
        if videoPlaying != showAirPlay {
            showAirPlay = videoPlaying
            animate()
        }
    }

    // MARK: - Costruzione

    private static func makeBlur() -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        view.clipsToBounds = true
        view.layer.borderWidth = 0.5
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        return view
    }

    private static func symbol(_ name: String) -> UIImage? {
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
    }

    private func buildBubble() {
        bubble.layer.cornerRadius = bubbleSize / 2
        bubbleButton.setImage(UIImage(systemName: "square.grid.2x2.fill",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)),
                              for: .normal)
        bubbleButton.tintColor = .label
        bubbleButton.accessibilityLabel = "Menu"
        bubbleButton.addTarget(self, action: #selector(toggle), for: .touchUpInside)
        pin(bubbleButton, to: bubble.contentView)
    }

    private func buildAirPlayBubble() {
        airPlayBubble.layer.cornerRadius = buttonSize / 2
        configure(airPlayPicker)
        pin(airPlayPicker, to: airPlayBubble.contentView)
    }

    /// Vincoli espliciti: con l'autoresizing la vista cresceva insieme al contenitore
    /// partendo da dimensione zero, raddoppiando (pulsante più grande della bolla).
    private func pin(_ view: UIView, to container: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    private func configure(_ picker: AVRoutePickerView) {
        picker.prioritizesVideoDevices = true
        picker.tintColor = .label
        picker.activeTintColor = .systemBlue
        picker.accessibilityLabel = "AirPlay"
    }

    private func buildPanel() {
        stack.spacing = spacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: panel.contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: panel.contentView.centerYAnchor),
        ])

        let items: [(Action, String, String)] = [
            (.back, "chevron.backward", "Indietro"),
            (.forward, "chevron.forward", "Avanti"),
            (.reload, "arrow.clockwise", "Ricarica"),
            (.address, "magnifyingglass", "Indirizzo"),
            (.pip, "pip.enter", "Picture in Picture"),
        ]
        for (action, symbol, label) in items { stack.addArrangedSubview(makeButton(action, symbol, label)) }

        configure(panelPicker)
        sized(panelPicker)
        stack.addArrangedSubview(panelPicker)

        stack.addArrangedSubview(makeButton(.settings, "gearshape", "Impostazioni"))

        let close = UIButton(type: .system)
        close.setImage(Self.symbol("minus"), for: .normal)
        close.tintColor = .label
        close.accessibilityLabel = "Chiudi menu"
        close.addTarget(self, action: #selector(toggle), for: .touchUpInside)
        sized(close)
        stack.addArrangedSubview(close)
    }

    private func makeButton(_ action: Action, _ symbol: String, _ label: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(Self.symbol(symbol), for: .normal)
        button.tintColor = .label
        button.accessibilityLabel = label
        button.tag = action.rawValue
        button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
        sized(button)
        buttons[action] = button
        return button
    }

    private func sized(_ view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: buttonSize),
            view.heightAnchor.constraint(equalToConstant: buttonSize),
        ])
    }

    // MARK: - Azioni

    @objc private func tapped(_ sender: UIButton) {
        guard let action = Action(rawValue: sender.tag) else { return }
        onAction?(action)
    }

    @objc private func toggle() {
        expanded.toggle()
        haptic.impactOccurred()
        animate()
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        guard let host else { return }
        switch gesture.state {
        case .began:
            dragStart = bubble.center
        case .changed:
            let t = gesture.translation(in: host)
            anchor = CGPoint(x: dragStart.x + t.x, y: dragStart.y + t.y)
            layout()
        case .ended, .cancelled:
            let area = usableArea(in: host)
            let current = anchor ?? bubble.center
            let x = current.x < host.bounds.midX ? area.minX + bubbleSize / 2 : area.maxX - bubbleSize / 2
            anchor = CGPoint(x: x, y: current.y)
            animate()
        default:
            break
        }
    }

    // MARK: - Geometria

    private func animate() {
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.layout()
            self.applyVisibility()
        }
    }

    private func applyVisibility() {
        bubble.alpha = expanded ? 0 : 0.95
        bubble.isUserInteractionEnabled = !expanded
        panel.alpha = expanded ? 1 : 0
        panel.isUserInteractionEnabled = expanded
        let air = showAirPlay && !expanded
        airPlayBubble.alpha = air ? 1 : 0
        airPlayBubble.isUserInteractionEnabled = air
    }

    private func usableArea(in host: UIView) -> CGRect {
        host.bounds.inset(by: host.safeAreaInsets).insetBy(dx: margin, dy: margin)
    }

    private func clamp(_ p: CGPoint, size: CGSize, topExtra: CGFloat, in area: CGRect) -> CGPoint {
        let minX = area.minX + size.width / 2, maxX = area.maxX - size.width / 2
        let minY = area.minY + topExtra + size.height / 2, maxY = area.maxY - size.height / 2
        return CGPoint(x: min(max(p.x, minX), max(minX, maxX)), y: min(max(p.y, minY), max(minY, maxY)))
    }

    /// Chiamato dal controller a ogni layout (rotazione, safe area) e durante il trascinamento.
    func layout() {
        guard let host, host.bounds.width > 0 else { return }
        let area = usableArea(in: host)
        let horizontal = host.bounds.height < 450
        stack.axis = horizontal ? .horizontal : .vertical

        let long = itemCount * buttonSize + (itemCount - 1) * spacing + padding * 2
        let short = buttonSize + padding * 2
        let panelSize = horizontal ? CGSize(width: long, height: short) : CGSize(width: short, height: long)

        let start = anchor ?? CGPoint(x: area.maxX - bubbleSize / 2, y: area.minY + area.height * 0.72)
        let topExtra: CGFloat = showAirPlay && !expanded ? buttonSize + 8 : 0
        let center = clamp(start, size: CGSize(width: bubbleSize, height: bubbleSize), topExtra: topExtra, in: area)

        bubble.bounds = CGRect(x: 0, y: 0, width: bubbleSize, height: bubbleSize)
        bubble.center = center
        airPlayBubble.bounds = CGRect(x: 0, y: 0, width: buttonSize, height: buttonSize)
        airPlayBubble.center = CGPoint(x: center.x, y: center.y - bubbleSize / 2 - 8 - buttonSize / 2)

        panel.layer.cornerRadius = short / 2
        panel.bounds = CGRect(origin: .zero, size: panelSize)
        panel.center = clamp(center, size: panelSize, topExtra: 0, in: area)
    }
}
