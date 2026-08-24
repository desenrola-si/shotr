import AppKit
import CoreImage

/// Desenha imagem + anotações no espaço de pixels da imagem (origem embaixo à esquerda).
enum AnnotationRenderer {

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func draw(image: CGImage, annotations: [Annotation], in context: CGContext, rect: CGRect) {
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        context.restoreGState()

        let scaleX = rect.width / CGFloat(image.width)
        let scaleY = rect.height / CGFloat(image.height)

        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: scaleX, y: scaleY)
        for annotation in annotations {
            draw(annotation, base: image, in: context)
        }
        context.restoreGState()
    }

    static func render(image: CGImage, annotations: [Annotation]) -> CGImage? {
        let width = image.width
        let height = image.height
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        draw(image: image, annotations: annotations, in: context,
             rect: CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    // MARK: - Uma anotação

    static func draw(_ annotation: Annotation, base: CGImage, in context: CGContext) {
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(annotation.color.cgColor)
        context.setFillColor(annotation.color.cgColor)
        context.setLineWidth(annotation.lineWidth)

        switch annotation.kind {
        case .rectangle:
            context.stroke(annotation.rect)
        case .ellipse:
            context.strokeEllipse(in: annotation.rect)
        case .line:
            context.beginPath()
            context.move(to: annotation.start)
            context.addLine(to: annotation.end)
            context.strokePath()
        case .arrow:
            drawArrow(annotation, in: context)
        case .pen:
            guard annotation.points.count > 1 else { break }
            context.beginPath()
            context.move(to: annotation.points[0])
            for point in annotation.points.dropFirst() { context.addLine(to: point) }
            context.strokePath()
        case .highlight:
            context.setFillColor(annotation.color.withAlphaComponent(0.35).cgColor)
            context.setBlendMode(.multiply)
            context.fill(annotation.rect)
        case .redact:
            context.setFillColor(NSColor.black.cgColor)
            context.fill(annotation.rect)
        case .blur, .pixelate:
            drawFiltered(annotation, base: base, in: context)
        case .text:
            drawText(annotation, in: context)
        case .counter:
            drawCounter(annotation, in: context)
        case .select, .crop:
            break
        }
        context.restoreGState()
    }

    private static func drawArrow(_ annotation: Annotation, in context: CGContext) {
        let start = annotation.start
        let end = annotation.end
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(annotation.lineWidth * 4.5, 14)
        let headAngle: CGFloat = .pi / 7

        let shaftEnd = CGPoint(x: end.x - cos(angle) * headLength * 0.7,
                               y: end.y - sin(angle) * headLength * 0.7)
        context.beginPath()
        context.move(to: start)
        context.addLine(to: shaftEnd)
        context.strokePath()

        context.beginPath()
        context.move(to: end)
        context.addLine(to: CGPoint(x: end.x - cos(angle - headAngle) * headLength,
                                    y: end.y - sin(angle - headAngle) * headLength))
        context.addLine(to: CGPoint(x: end.x - cos(angle + headAngle) * headLength,
                                    y: end.y - sin(angle + headAngle) * headLength))
        context.closePath()
        context.fillPath()
    }

    private static func drawFiltered(_ annotation: Annotation, base: CGImage, in context: CGContext) {
        let rect = annotation.rect.integral
        guard rect.width > 2, rect.height > 2 else { return }
        // Converte de coordenadas bottom-left para o espaço top-left do CGImage.
        let imageHeight = CGFloat(base.height)
        let cropRect = CGRect(x: rect.minX, y: imageHeight - rect.maxY, width: rect.width, height: rect.height)
        guard let piece = base.cropping(to: cropRect) else { return }

        let input = CIImage(cgImage: piece)
        let output: CIImage?
        if annotation.kind == .blur {
            let radius = max(6, min(rect.width, rect.height) / 12)
            output = input
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: input.extent)
        } else {
            let scale = max(6, min(rect.width, rect.height) / 14)
            output = input.applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: scale,
                kCIInputCenterKey: CIVector(x: input.extent.midX, y: input.extent.midY)
            ]).cropped(to: input.extent)
        }
        guard let output, let filtered = ciContext.createCGImage(output, from: input.extent) else { return }
        context.saveGState()
        context.draw(filtered, in: rect)
        context.restoreGState()
    }

    private static func drawText(_ annotation: Annotation, in context: CGContext) {
        guard !annotation.text.isEmpty else { return }
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let size = annotation.attributedText.size()
        annotation.attributedText.draw(at: CGPoint(x: annotation.start.x, y: annotation.start.y - size.height))
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawCounter(_ annotation: Annotation, in context: CGContext) {
        let radius = annotation.counterRadius
        let circle = CGRect(x: annotation.start.x - radius, y: annotation.start.y - radius,
                            width: radius * 2, height: radius * 2)
        context.setFillColor(annotation.color.cgColor)
        context.fillEllipse(in: circle)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(max(2, annotation.lineWidth / 2))
        context.strokeEllipse(in: circle)

        let label = NSAttributedString(string: "\(annotation.number)", attributes: [
            .font: NSFont.systemFont(ofSize: radius * 1.1, weight: .bold),
            .foregroundColor: NSColor.white
        ])
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let size = label.size()
        label.draw(at: CGPoint(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}
