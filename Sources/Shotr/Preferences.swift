import AppKit

enum ImageFormat: String, CaseIterable {
    case png, jpeg, tiff

    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }

    var utType: NSBitmapImageRep.FileType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        }
    }

    var title: String { rawValue.uppercased() }
}

enum AfterCapture: String, CaseIterable {
    case openEditor
    case copyOnly
    case saveOnly

    var title: String {
        switch self {
        case .openEditor: return "Abrir editor"
        case .copyOnly: return "Copiar para a área de transferência"
        case .saveOnly: return "Salvar no disco"
        }
    }
}

final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let saveDirectory = "saveDirectory"
        static let format = "imageFormat"
        static let jpegQuality = "jpegQuality"
        static let afterCapture = "afterCapture"
        static let alsoCopy = "alsoCopyToClipboard"
        static let alsoSave = "alsoSaveToDisk"
        static let playSound = "playShutterSound"
        static let filenameTemplate = "filenameTemplate"
        static let launchAtStartup = "launchAtStartup"
        static let lastArea = "lastCaptureArea"
        static let scrollingInterval = "scrollingInterval"
    }

    private init() {
        defaults.register(defaults: [
            Key.format: ImageFormat.png.rawValue,
            Key.jpegQuality: 0.9,
            Key.afterCapture: AfterCapture.openEditor.rawValue,
            Key.alsoCopy: true,
            Key.alsoSave: false,
            Key.playSound: true,
            Key.filenameTemplate: "Shotr {date} {time}",
            Key.scrollingInterval: 0.35
        ])
    }

    var saveDirectory: URL {
        get {
            if let path = defaults.string(forKey: Key.saveDirectory) {
                return URL(fileURLWithPath: path)
            }
            return FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
        }
        set { defaults.set(newValue.path, forKey: Key.saveDirectory) }
    }

    var format: ImageFormat {
        get { ImageFormat(rawValue: defaults.string(forKey: Key.format) ?? "") ?? .png }
        set { defaults.set(newValue.rawValue, forKey: Key.format) }
    }

    var jpegQuality: Double {
        get { defaults.double(forKey: Key.jpegQuality) }
        set { defaults.set(newValue, forKey: Key.jpegQuality) }
    }

    var afterCapture: AfterCapture {
        get { AfterCapture(rawValue: defaults.string(forKey: Key.afterCapture) ?? "") ?? .openEditor }
        set { defaults.set(newValue.rawValue, forKey: Key.afterCapture) }
    }

    var alsoCopyToClipboard: Bool {
        get { defaults.bool(forKey: Key.alsoCopy) }
        set { defaults.set(newValue, forKey: Key.alsoCopy) }
    }

    var alsoSaveToDisk: Bool {
        get { defaults.bool(forKey: Key.alsoSave) }
        set { defaults.set(newValue, forKey: Key.alsoSave) }
    }

    var playShutterSound: Bool {
        get { defaults.bool(forKey: Key.playSound) }
        set { defaults.set(newValue, forKey: Key.playSound) }
    }

    var filenameTemplate: String {
        get { defaults.string(forKey: Key.filenameTemplate) ?? "Shotr {date} {time}" }
        set { defaults.set(newValue, forKey: Key.filenameTemplate) }
    }

    var scrollingInterval: Double {
        get { max(0.15, defaults.double(forKey: Key.scrollingInterval)) }
        set { defaults.set(newValue, forKey: Key.scrollingInterval) }
    }

    var lastArea: CGRect? {
        get {
            guard let dict = defaults.dictionary(forKey: Key.lastArea) as? [String: CGFloat],
                  let x = dict["x"], let y = dict["y"], let w = dict["w"], let h = dict["h"],
                  w > 1, h > 1 else { return nil }
            return CGRect(x: x, y: y, width: w, height: h)
        }
        set {
            guard let rect = newValue else { return }
            defaults.set(["x": rect.origin.x, "y": rect.origin.y,
                          "w": rect.size.width, "h": rect.size.height], forKey: Key.lastArea)
        }
    }

    func makeFilename() -> String {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH.mm.ss"
        return filenameTemplate
            .replacingOccurrences(of: "{date}", with: dateFormatter.string(from: now))
            .replacingOccurrences(of: "{time}", with: timeFormatter.string(from: now))
            .replacingOccurrences(of: "/", with: "-")
    }
}
