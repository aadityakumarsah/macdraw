import AppKit
import CoreText

/// Registers the bundled excalidraw fonts (woff2) so they can be used for text.
struct FontInfo {
    let name: String
    let postscriptNames: [String]
}

enum Fonts {
    static let available: [FontInfo] = [
        FontInfo(name: "Virgil", postscriptNames: ["Virgil", "Virgil-Regular"]),
        FontInfo(name: "Excalifont", postscriptNames: ["Excalifont-Regular", "Excalifont"]),
        FontInfo(name: "Cascadia Code", postscriptNames: ["CascadiaCode-Regular", "Cascadia Code"]),
        FontInfo(name: "Nunito", postscriptNames: ["Nunito-Regular", "Nunito"]),
        FontInfo(name: "Comic Shanns", postscriptNames: ["ComicShanns", "ComicShanns-Regular"]),
        FontInfo(name: "Lilita One", postscriptNames: ["LilitaOne-Regular", "LilitaOne", "Lilita One", "Lilita"]),
        FontInfo(name: "Assistant", postscriptNames: ["Assistant-Regular", "Assistant"]),
        FontInfo(name: "System", postscriptNames: []),
    ]

    static func register() {
        for f in Resources.files(in: "Fonts", ext: "woff2") {
            CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
        }
    }

    static func nsFont(for family: String, size: CGFloat) -> NSFont {
        if let info = available.first(where: { $0.name == family }) {
            for ps in info.postscriptNames {
                if let f = NSFont(name: ps, size: size) {
                    return f
                }
            }
        }
        return NSFont.systemFont(ofSize: size)
    }
}
