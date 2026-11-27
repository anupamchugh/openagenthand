@preconcurrency import AVFoundation
import ImageIO
import OpenAgentHandCore

final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Failure: LocalizedError {
        case denied, unavailable

        var errorDescription: String? {
            switch self {
            case .denied: "Camera access is off. Enable it in Privacy & Security settings."
            case .unavailable: "No usable camera was found. You can still tap the agent buttons."
            }
        }
    }

    struct Frame: Sendable {
        let time: TimeInterval
        let hand: HandJoints?
    }

    let frames: AsyncStream<Frame>
    private let continuation: AsyncStream<Frame>.Continuation
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.openagenthand.camera", qos: .userInitiated)

    override init() {
        let stream = AsyncStream.makeStream(of: Frame.self, bufferingPolicy: .bufferingNewest(1))
        frames = stream.stream
        continuation = stream.continuation
        super.init()
    }

    func start() async throws -> String {
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw Failure.denied }
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { (started: CheckedContinuation<String, Error>) in
            queue.async {
                do {
                    let name = try self.configure()
                    self.session.startRunning()
                    guard self.session.isRunning else { throw Failure.unavailable }
                    started.resume(returning: name)
                } catch {
                    started.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        continuation.finish()
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configure() throws -> String {
        #if os(macOS)
        let builtIn = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified
        ).devices.first
        let device = builtIn ?? AVCaptureDevice.default(for: .video)
        #else
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        #endif
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else { throw Failure.unavailable }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        guard session.canAddInput(input), session.canAddOutput(output) else { throw Failure.unavailable }
        session.addInput(input)
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        return device.localizedName
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixels = sample.imageBuffer else { return }
        let time = ProcessInfo.processInfo.systemUptime
        #if os(macOS)
        let orientation = CGImagePropertyOrientation.up
        #else
        // The iPhone app presents its front camera in portrait.
        let orientation = CGImagePropertyOrientation.leftMirrored
        #endif
        let observations = (try? HandDetector.hands(in: pixels, orientation: orientation, maximum: 2)) ?? []
        let tracked = observations.filter(PinchRecognizer.canTrack)
        continuation.yield(Frame(time: time, hand: tracked.count == 1 ? tracked.first : nil))
    }
}
