import SwiftUI
import AVKit

/// Pulsante AirPlay di sistema (AVRoutePickerView): apre il selettore nativo
/// di dispositivi AirPlay / Bluetooth. Nessuna logica di streaming propria.
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.tintColor = .label
        picker.activeTintColor = .systemBlue
        picker.backgroundColor = .clear
        return picker
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
