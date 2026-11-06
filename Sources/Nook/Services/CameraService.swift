import AVFoundation
import AppKit
import Combine
import SwiftUI

/// Owns a single capture session for the mirror tab. Nothing is recorded
/// or uploaded — the preview stays on this Mac.
final class CameraService: ObservableObject {
    static let shared = CameraService()

    @Published private(set) var status: AVAuthorizationStatus
    @Published private(set) var running = false
    @Published private(set) var error: String?
    @Published private(set) var deviceName = "Camera"

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "nook.camera.session")
    private var configured = false

    private init() {
        status = AVCaptureDevice.authorizationStatus(for: .video)
    }

    var authorized: Bool { status == .authorized }

    func requestAccess() {
        status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.status = AVCaptureDevice.authorizationStatus(for: .video)
                    if granted {
                        self.error = nil
                        self.start()
                    } else {
                        self.error = "Camera access denied."
                    }
                }
            }
        } else if status == .authorized {
            start()
        } else {
            error = "Camera access is off."
        }
    }

    func start() {
        status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            requestAccess()
            return
        }
        guard status == .authorized else {
            error = "Camera access is off."
            running = false
            return
        }
        if !configured { configure() }
        guard configured else { return }
        queue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.running = self.session.isRunning }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.running = false }
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(for: .video) else {
            error = "No camera found on this Mac."
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                deviceName = device.localizedName
                configured = true
                error = nil
            } else {
                error = "The camera is busy."
            }
        } catch {
            self.error = "Couldn't open the camera."
        }
    }
}

// MARK: - preview

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ view: CameraPreviewView, context: Context) {
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
        }
    }
}

final class CameraPreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }
}
