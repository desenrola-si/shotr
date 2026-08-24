import AppKit

enum ImageOutput {

    static func data(from image: CGImage, format: ImageFormat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: image.width, height: image.height)
        var properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
        if format == .jpeg {
            properties[.compressionFactor] = Preferences.shared.jpegQuality
        }
        return rep.representation(using: format.utType, properties: properties)
    }

    @discardableResult
    static func save(_ image: CGImage, format: ImageFormat = Preferences.shared.format) -> URL? {
        let directory = Preferences.shared.saveDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory.appendingPathComponent(Preferences.shared.makeFilename())
            .appendingPathExtension(format.fileExtension)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(Preferences.shared.makeFilename()) (\(counter))")
                .appendingPathExtension(format.fileExtension)
            counter += 1
        }
        guard let data = data(from: image, format: format) else { return nil }
        do {
            try data.write(to: url)
            return url
        } catch {
            NSLog("Shotr: falha ao salvar — \(error.localizedDescription)")
            return nil
        }
    }

    static func saveWithPanel(_ image: CGImage, suggestedName: String? = nil) {
        let panel = NSSavePanel()
        let format = Preferences.shared.format
        panel.nameFieldStringValue = (suggestedName ?? Preferences.shared.makeFilename()) + "." + format.fileExtension
        panel.directoryURL = Preferences.shared.saveDirectory
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let chosen = ImageFormat.allCases.first { $0.fileExtension == url.pathExtension.lowercased() } ?? format
        guard let data = data(from: image, format: chosen) else { return }
        try? data.write(to: url)
    }

    static func copyToPasteboard(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        pasteboard.writeObjects([nsImage])
        if let png = data(from: image, format: .png) {
            pasteboard.setData(png, forType: .png)
        }
    }

    static func copyToPasteboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func imageFromPasteboard() -> CGImage? {
        guard let items = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
              let image = items.first else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func playShutter() {
        guard Preferences.shared.playShutterSound else { return }
        NSSound(named: "Grab")?.play()
    }
}
