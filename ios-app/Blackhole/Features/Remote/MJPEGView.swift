import SwiftUI
import UIKit

/// Zeigt einen MJPEG-Stream (multipart/x-mixed-replace) an – so liefert der
/// Companion Agent Bildschirm und Webcam. MJPEG ist bewusst gewählt, weil es
/// ohne zusätzliche Video-Bibliothek direkt mit URLSession dekodierbar ist.
struct MJPEGView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .black
        context.coordinator.start(url: url, into: view)
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }
    static func dismantleUIView(_ uiView: UIImageView, coordinator: Coordinator) {
        coordinator.stop()
    }

    /// Parst den fortlaufenden multipart-Stream und setzt jeden JPEG-Frame.
    final class Coordinator: NSObject, URLSessionDataDelegate {
        private var session: URLSession?
        private var buffer = Data()
        private weak var target: UIImageView?

        // JPEG-Marker
        private let soi = Data([0xFF, 0xD8])   // Start of Image
        private let eoi = Data([0xFF, 0xD9])   // End of Image

        func start(url: URL, into view: UIImageView) {
            target = view
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 0   // Dauerstream
            session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            session?.dataTask(with: url).resume()
        }

        func stop() {
            session?.invalidateAndCancel()
            session = nil
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            buffer.append(data)
            // Alle vollständigen JPEG-Frames im Puffer herausziehen.
            while let start = buffer.range(of: soi),
                  let end = buffer.range(of: eoi, in: start.upperBound..<buffer.endIndex) {
                let frame = buffer.subdata(in: start.lowerBound..<end.upperBound)
                buffer.removeSubrange(buffer.startIndex..<end.upperBound)
                if let image = UIImage(data: frame) {
                    DispatchQueue.main.async { [weak self] in self?.target?.image = image }
                }
            }
            // Puffer nicht unbegrenzt wachsen lassen.
            if buffer.count > 5_000_000 { buffer.removeAll(keepingCapacity: true) }
        }
    }
}

private extension Data {
    func range(of data: Data, in range: Range<Index>) -> Range<Index>? {
        self.range(of: data, options: [], in: range)
    }
}
