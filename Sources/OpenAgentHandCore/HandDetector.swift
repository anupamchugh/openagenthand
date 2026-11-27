import CoreGraphics
import CoreVideo
import ImageIO
import Vision

/// Finds up to `maximum` hands with Vision's hand-pose request (iOS 14+ API, so iOS 17 apps can use it).
public enum HandDetector {
    public static func hands(in image: CGImage, maximum: Int = 2) throws -> [HandJoints] {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = maximum
        try VNImageRequestHandler(cgImage: image).perform([request])
        let aspect = CGFloat(image.width) / CGFloat(image.height)
        return (request.results ?? []).map { HandJoints($0, aspect: aspect) }
    }

    public static func hands(in frame: CVPixelBuffer, orientation: CGImagePropertyOrientation, maximum: Int = 2) throws -> [HandJoints] {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = maximum
        try VNImageRequestHandler(cvPixelBuffer: frame, orientation: orientation).perform([request])
        let width = CGFloat(CVPixelBufferGetWidth(frame)), height = CGFloat(CVPixelBufferGetHeight(frame))
        // Portrait orientations swap the buffer's axes.
        let aspect = [.right, .left, .rightMirrored, .leftMirrored].contains(orientation) ? height / width : width / height
        return (request.results ?? []).map { HandJoints($0, aspect: aspect) }
    }
}
