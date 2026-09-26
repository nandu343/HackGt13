import RoomPlan
import SwiftUI
import UIKit

/// UIKit wrapper around RoomPlan's `RoomCaptureView` for SwiftUI.
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

    private var captureView: RoomCaptureView!
    private var isSessionRunning = false
    private var finalResults: CapturedRoom?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        captureView = RoomCaptureView(frame: view.bounds)
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        captureView.delegate = self
        view.addSubview(captureView)

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
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    private func startSession() {
        guard !isSessionRunning else { return }
        let config = RoomCaptureSession.Configuration()
        captureView.captureSession.run(configuration: config)
        isSessionRunning = true
    }

    private func stopSession() {
        guard isSessionRunning else { return }
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
