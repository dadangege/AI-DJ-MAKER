import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum QRCodeRenderer {
    static func image(from string: String, size: CGFloat = 220) -> NSImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else {
            return NSImage(size: NSSize(width: size, height: size))
        }

        let scale = size / output.extent.width
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: transformed)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }
}
