import AppKit

enum ToolKind: String, CaseIterable {
    case select
    case arrow
    case rectangle
    case ellipse
    case line
    case pen
    case text
    case highlight
    case blur
    case pixelate
    case redact
    case counter
    case crop

    var title: String {
        switch self {
        case .select: return "Selecionar"
        case .arrow: return "Seta"
        case .rectangle: return "Retângulo"
        case .ellipse: return "Elipse"
        case .line: return "Linha"
        case .pen: return "Lápis"
        case .text: return "Texto"
        case .highlight: return "Marca-texto"
        case .blur: return "Desfoque"
        case .pixelate: return "Pixelar"
        case .redact: return "Tarja"
        case .counter: return "Numerador"
        case .crop: return "Recortar"
        }
    }

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .blur: return "drop.fill"
        case .pixelate: return "square.grid.3x3.fill"
        case .redact: return "rectangle.fill"
        case .counter: return "1.circle.fill"
        case .crop: return "crop"
        }
    }

    var usesDrag: Bool { self != .text && self != .counter && self != .select }
}

/// Anotação em coordenadas da imagem (pixels, origem embaixo à esquerda).
final class Annotation {
    let kind: ToolKind
    var start: CGPoint
    var end: CGPoint
    var color: NSColor
    var lineWidth: CGFloat
    var text: String
    var points: [CGPoint]
    var number: Int
    var fontSize: CGFloat

    init(kind: ToolKind,
         start: CGPoint,
         end: CGPoint,
         color: NSColor,
         lineWidth: CGFloat,
         text: String = "",
         points: [CGPoint] = [],
         number: Int = 0,
         fontSize: CGFloat = 28) {
        self.kind = kind
        self.start = start
        self.end = end
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.points = points
        self.number = number
        self.fontSize = fontSize
    }

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    var boundingBox: CGRect {
        switch kind {
        case .pen:
            guard let first = points.first else { return rect }
            var box = CGRect(origin: first, size: .zero)
            points.forEach { box = box.union(CGRect(origin: $0, size: .zero)) }
            return box.insetBy(dx: -lineWidth, dy: -lineWidth)
        case .text:
            let size = attributedText.size()
            return CGRect(x: start.x, y: start.y - size.height, width: size.width, height: size.height)
        case .counter:
            let radius = counterRadius
            return CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2)
        default:
            return rect.insetBy(dx: -lineWidth, dy: -lineWidth)
        }
    }

    var counterRadius: CGFloat { max(14, lineWidth * 6) }

    var attributedText: NSAttributedString {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = CGSize(width: 0, height: -1)
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color,
            .shadow: shadow
        ])
    }

    func copyMoved(by delta: CGVector) -> Annotation {
        let copy = Annotation(kind: kind,
                              start: CGPoint(x: start.x + delta.dx, y: start.y + delta.dy),
                              end: CGPoint(x: end.x + delta.dx, y: end.y + delta.dy),
                              color: color, lineWidth: lineWidth, text: text,
                              points: points.map { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) },
                              number: number, fontSize: fontSize)
        return copy
    }

    func contains(_ point: CGPoint) -> Bool {
        boundingBox.insetBy(dx: -6, dy: -6).contains(point)
    }
}
