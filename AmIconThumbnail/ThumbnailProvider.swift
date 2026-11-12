import AmigaIconKit
import CoreGraphics
import QuickLookThumbnailing

/// Finder thumbnails for Amiga `.info` icons, drawn pixel-sharp at an integer scale.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        do {
            let file = try IconFile.read(contentsOf: request.fileURL)
            guard let picture = IconRenderer.primaryPicture(of: file),
                  let image = ImageConversion.cgImage(from: picture) else {
                handler(nil, AmigaIconError.notAnIcon)
                return
            }
            let size = Self.thumbnailSize(imageWidth: picture.width, imageHeight: picture.height,
                                          maximumSize: request.maximumSize, scale: request.scale)
            let reply = QLThumbnailReply(contextSize: size) { context in
                context.interpolationQuality = .none
                context.draw(image, in: CGRect(origin: .zero, size: size))
                return true
            }
            handler(reply, nil)
        } catch {
            handler(nil, error)
        }
    }

    /// Size in points: the largest integer pixel multiple that fits (or a plain downscale if too big).
    static func thumbnailSize(imageWidth: Int, imageHeight: Int, maximumSize: CGSize, scale: CGFloat) -> CGSize {
        let w = CGFloat(max(1, imageWidth)), h = CGFloat(max(1, imageHeight))
        let fit = min(maximumSize.width * scale / w, maximumSize.height * scale / h)
        let factor = fit >= 1 ? floor(fit) : fit
        return CGSize(width: w * factor / scale, height: h * factor / scale)
    }
}
