import AppKit
import Vision

struct RecognizedLine {
    let text: String
    /// Retângulo em coordenadas da imagem (pixels, origem embaixo à esquerda).
    let rect: CGRect
}

struct RecognitionResult {
    let lines: [RecognizedLine]
    let barcodes: [String]

    var plainText: String {
        lines.map(\.text).joined(separator: "\n")
    }

    var isEmpty: Bool { lines.isEmpty && barcodes.isEmpty }
}

enum TextRecognizer {

    static func recognize(in image: CGImage) -> RecognitionResult {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.recognitionLanguages = ["pt-BR", "en-US"]

        let barcodeRequest = VNDetectBarcodesRequest()

        do {
            try handler.perform([textRequest, barcodeRequest])
        } catch {
            NSLog("Shotr: OCR falhou — \(error.localizedDescription)")
            return RecognitionResult(lines: [], barcodes: [])
        }

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        let lines: [RecognizedLine] = (textRequest.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            let rect = CGRect(x: box.minX * width, y: box.minY * height,
                              width: box.width * width, height: box.height * height)
            return RecognizedLine(text: candidate.string, rect: rect)
        }
        .sorted { $0.rect.maxY > $1.rect.maxY }

        let barcodes = (barcodeRequest.results ?? []).compactMap { $0.payloadStringValue }

        return RecognitionResult(lines: lines, barcodes: barcodes)
    }
}
