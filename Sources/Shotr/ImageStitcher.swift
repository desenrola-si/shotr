import AppKit

/// Costura capturas sucessivas de uma mesma área enquanto o conteúdo rola.
final class ImageStitcher {

    private struct Piece {
        let image: CGImage
        let sourceY: Int   // linha inicial dentro de `image` (topo = 0)
        let height: Int
    }

    private var pieces: [Piece] = []
    private var tail: [UInt8] = []          // faixa de referência em tons de cinza
    private var width = 0
    private var totalHeight = 0

    private let referenceHeight = 70
    private let columnStep = 4
    private let matchThreshold: Double = 14

    var capturedHeight: Int { totalHeight }
    var isEmpty: Bool { pieces.isEmpty }

    @discardableResult
    func append(_ image: CGImage) -> Bool {
        guard let gray = ImageStitcher.grayscale(image, columnStep: columnStep) else { return false }
        let sampledWidth = (image.width + columnStep - 1) / columnStep

        guard !pieces.isEmpty else {
            width = image.width
            pieces = [Piece(image: image, sourceY: 0, height: image.height)]
            totalHeight = image.height
            tail = ImageStitcher.tailRows(gray, width: sampledWidth, height: image.height, rows: referenceHeight)
            return true
        }

        guard image.width == width else { return false }
        let reference = tail
        let referenceRows = reference.count / sampledWidth
        guard referenceRows > 4, image.height > referenceRows else { return false }

        let comparedColumns = max(1, sampledWidth / 2)
        let samplesPerCompare = Double(referenceRows * comparedColumns)
        var bestOffset = -1
        var bestScore = Double.greatestFiniteMagnitude
        for offset in 0...(image.height - referenceRows) {
            var sum = 0.0
            var index = 0
            var aborted = false
            for row in 0..<referenceRows {
                let base = (offset + row) * sampledWidth
                for column in stride(from: 0, to: sampledWidth, by: 2) {
                    sum += abs(Double(gray[base + column]) - Double(reference[index + column]))
                }
                index += sampledWidth
                if sum / samplesPerCompare > bestScore {
                    aborted = true
                    break
                }
            }
            guard !aborted else { continue }
            let score = sum / samplesPerCompare
            if score < bestScore {
                bestScore = score
                bestOffset = offset
            }
            if bestScore < 0.5 { break }
        }

        guard bestOffset >= 0, bestScore <= matchThreshold else { return false }
        let newStart = bestOffset + referenceRows
        guard newStart < image.height else { return false }

        let newRows = image.height - newStart
        pieces.append(Piece(image: image, sourceY: newStart, height: newRows))
        totalHeight += newRows
        tail = ImageStitcher.tailRows(gray, width: sampledWidth, height: image.height, rows: referenceHeight)
        return true
    }

    func compose() -> CGImage? {
        guard !pieces.isEmpty, width > 0, totalHeight > 0 else { return nil }
        guard let context = CGContext(data: nil, width: width, height: totalHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var y = 0
        for piece in pieces {
            guard let cropped = piece.image.cropping(to: CGRect(x: 0, y: piece.sourceY,
                                                                width: width, height: piece.height)) else { continue }
            let bottom = totalHeight - (y + piece.height)
            context.draw(cropped, in: CGRect(x: 0, y: bottom, width: width, height: piece.height))
            y += piece.height
        }
        return context.makeImage()
    }

    // MARK: - Auxiliares

    private static func grayscale(_ image: CGImage, columnStep: Int) -> [UInt8]? {
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &buffer, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // O buffer do CGContext já vem com a linha 0 no topo; só reamostra as colunas.
        let sampledWidth = (width + columnStep - 1) / columnStep
        var sampled = [UInt8](repeating: 0, count: sampledWidth * height)
        for row in 0..<height {
            var target = row * sampledWidth
            var column = 0
            while column < width {
                sampled[target] = buffer[row * width + column]
                target += 1
                column += columnStep
            }
        }
        return sampled
    }

    private static func tailRows(_ gray: [UInt8], width: Int, height: Int, rows: Int) -> [UInt8] {
        let count = min(rows, height)
        let start = (height - count) * width
        return Array(gray[start..<(start + count * width)])
    }
}
