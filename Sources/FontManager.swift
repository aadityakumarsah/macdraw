import AppKit
import CoreText
import SwiftUI

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
        FontInfo(name: "Comic Neue", postscriptNames: ["ComicNeue-Regular", "Comic Neue"]),
        FontInfo(name: "Caveat", postscriptNames: ["Caveat-Regular", "Caveat"]),
        FontInfo(name: "EB Garamond", postscriptNames: ["EBGaramond-Regular", "EB Garamond"]),
        FontInfo(name: "Architects Daughter", postscriptNames: ["ArchitectsDaughter-Regular", "Architects Daughter"]),
        FontInfo(name: "Kalam", postscriptNames: ["Kalam-Regular", "Kalam"]),
        FontInfo(name: "Patrick Hand", postscriptNames: ["PatrickHand-Regular", "Patrick Hand"]),
        FontInfo(name: "Indie Flower", postscriptNames: ["IndieFlower-Regular", "Indie Flower"]),
        FontInfo(name: "Gochi Hand", postscriptNames: ["GochiHand-Regular", "Gochi Hand"]),
        FontInfo(name: "Pangolin", postscriptNames: ["Pangolin-Regular", "Pangolin"]),
        FontInfo(name: "System", postscriptNames: []),
    ]

    static func register() {
        let exts = ["woff2", "ttf", "otf"]
        for ext in exts {
            for f in Resources.files(in: "Fonts", ext: ext) {
                CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
            }
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

    static func font(for family: String, size: CGFloat) -> SwiftUI.Font {
        SwiftUI.Font(nsFont(for: family, size: size) as CTFont)
    }
}
