import RoomPlan
import SwiftUI
import UIKit

/// UIKit wrapper around RoomPlan's `RoomCaptureView` for SwiftUI.
/// Only present when `RoomCaptureSession.isSupported` (LiDAR). Camera scan is the primary path.
struct RoomCaptureRepresentable: UIViewControllerRepresentable {
    var onComplete: (CapturedRoom) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> RoomCaptureViewController {
        let vc = RoomCaptureViewController()
        vc.onComplete = onComplete
        vc.onCancel = onCancel
        return vc
    }

    func updateUIViewController(_ uiViewController: RoomCaptureViewController, context: Context) {}
}

final class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate {
    var onComplete: ((CapturedRoom) -> Void)?
    var onCancel: (() -> Void)?

    private var captureView: RoomCaptureView?
    private var isSessionRunning = false
    private var finalResults: CapturedRoom?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Never construct RoomCaptureView on non-LiDAR devices — it can crash.
        guard RoomCaptureSession.isSupported else {
            let label = UILabel()
            label.text = "Detailed scan requires LiDAR.\nUse Scan with camera instead."
            label.textColor = .white
            label.textAlignment = .center
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
            ])
            let close = UIButton(type: .system)
            close.setTitle("Close", for: .normal)
            close.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
            close.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(close)
            NSLayoutConstraint.activate([
                close.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 16),
                close.centerXAnchor.constraint(equalTo: view.centerXAnchor)
            ])
            return
        }

        let capture = RoomCaptureView(frame: view.bounds)
        capture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        capture.delegate = self
        view.addSubview(capture)
        captureView = capture

        let bar = UIToolbar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        let cancel = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        let done = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        bar.items = [cancel, flex, done]
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard RoomCaptureSession.isSupported else { return }
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    private func startSession() {
        guard !isSessionRunning, let captureView else { return }
        let config = RoomCaptureSession.Configuration()
        captureView.captureSession.run(configuration: config)
        isSessionRunning = true
    }

    private func stopSession() {
        guard isSessionRunning, let captureView else { return }
        captureView.captureSession.stop()
        isSessionRunning = false
    }

    @objc private func cancelTapped() {
        stopSession()
        onCancel?()
    }

    @objc private func doneTapped() {
        stopSession()
        if let room = finalResults {
            onComplete?(room)
        } else {
            onCancel?()
        }
    }

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        finalResults = processedResult
    }
}
