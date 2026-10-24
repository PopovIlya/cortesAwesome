import CortesCore
import SwiftUI

/// Hand-drawn 16×16 portraits of the parliament, one character per pixel. "." is transparent.
enum PixelArt {
    static let size = 16

    static func sprite(_ voice: Voice) -> [String] {
        switch voice {
        case .cautious: return [   // tinfoil hat, eyes darting sideways, a bead of sweat
            ".......KK.......",
            "......KHHK......",
            ".....KHhHHK.....",
            "....KHHhHHHK....",
            "...KHHHHhHHHK...",
            "..KKKKKKKKKKKK..",
            "...KSSSSSSSSKD..",
            "...KSWESSWESK...",
            "...KSWESSWESK...",
            "...KSSSsSSSSK...",
            "...KSSSsSSSSK...",
            "...KSSKsKsSSK...",
            "...KSSSSSSSSK...",
            "....KSSSSSSK....",
            ".....KKKKKK.....",
            "....KBBBBBBK....",
        ]
        case .bold: return [       // heroic quiff, square jaw, a grin and a cape
            "................",
            "....KKKKKKK.....",
            "...KHHHHHHHK.Y..",
            "..KHHHHHHHHHK...",
            "..KHHKSSSHHHK...",
            "..KHSSSSSSSHK...",
            "..KSSKKSSKKSK...",
            "..KSSWESSWESK...",
            "..KSSSSsSSSSK...",
            "..KSSSSsSSSSK...",
            "..KSKWWWWWKSK...",
            "..KSSKKKKKSSK...",
            "...KSSSSSSSK....",
            "....KKSSSKK.....",
            "..RRRKKKKKRRR...",
            ".RRRRBBBBBRRRR..",
        ]
        case .accountant: return [ // green eyeshade, round glasses, a tie
            "................",
            "................",
            "....KKKKKKKK....",
            "...KGGGGGGGGK...",
            "..KGGGGGGGGGGK..",
            "...KHSSSSSSHK...",
            "...KSSSSSSSSK...",
            "...KOOOSSOOOK...",
            "...KOEOKKOEOK...",
            "...KOOOSSOOOK...",
            "...KSSSsSSSSK...",
            "...KSSKKKKSSK...",
            "....KSSSSSSK....",
            ".....KKKKKK.....",
            "....KWWTWWWK....",
            "...KWWWTTWWWK...",
        ]
        case .diplomat: return [   // happy shut eyes, blush, a heart on the sweater
            "................",
            ".....KKKKKK.....",
            "...KKHHHHHHKK...",
            "..KHHHHHHHHHHK..",
            "..KHSSSSSSSSHK..",
            "..KHSSSSSSSSHK..",
            "..KSSKSSSSKSSK..",
            "..KSKSKSSKSKSK..",
            "..KSPPSSSSPPSK..",
            "..KSSKSSSSKSSK..",
            "..KSSSKKKKSSSK..",
            "...KSSSSSSSSK...",
            "....KKSSSSKK....",
            "...LLKKKKKKLL...",
            "..LLLRRLRRLLLL..",
            "..LLLLRRRLLLLL..",
        ]
        case .cynic: return [      // messy hair, heavy lids, eye bags, stubble, coffee
            "................",
            "....K.KKK.K.....",
            "...KHKHHHKHK....",
            "..KHHHHHHHHHK...",
            "..KHHSSSSSHHK...",
            "..KHSSSSSSSHK...",
            "..KSKKKSKKKSK...",
            "..KSWEWSWEWSK...",
            "..KSbbbSbbbSK...",
            "..KSSSSsSSSSK...",
            "..KGSSSSSSSGK...",
            "..KGGKKKKKGGK...",
            "...KGGGGGGGK....",
            "....KKKKKKK..w..",
            "...KCCCCCCCK.MM.",
            "..KCCCCCCCCCKMM.",
        ]
        case .mystic: return [     // hood, closed eyes, a third eye, stars on the robe
            "......KKKK......",
            "....KKHHHHKK....",
            "...KHHHHHHHHK...",
            "..KHHHKYYKHHHK..",
            "..KHHSKYYKSHHK..",
            "..KHSSSKKSSSHK..",
            "..KHSSSSSSSSHK..",
            "..KHSKKSSKKSHK..",
            "..KHSSSSSSSSHK..",
            "..KHSSSsSSSSHK..",
            "..KHSSKKKKSSHK..",
            "..KHHSSSSSSHHK..",
            "..KHHHKKKKHHHK..",
            ".KHHHHHHHHHHHHK.",
            ".KHHhHHHHHHhHHK.",
            "KHHHHHHHHHHHHHHK",
        ]
        case .hedonist: return [   // curls, sunglasses, a grin, a loud shirt, a drink with a straw
            "................",
            "...KKKKKKKKK....",
            "..KHHHHHHHHHK...",
            "..KHHHHHHHHHK...",
            "..KHSSSSSSSHK...",
            "..KSSSSSSSSSK...",
            "..KOOOOSOOOOK...",
            "..KOOWOKOOWOK...",
            "..KSSSSsSSSSK...",
            "..KSSSSsSSSSK...",
            "..KSKWWWWWKSK...",
            "..KSSKKKKKSSK...",
            "...KSSSSSSSK.R..",
            "....KKKKKKK..R..",
            "..KPPPPPPPK.KGK.",
            ".KPPYPPPYPPKKGK.",
        ]
        }
    }

    /// Muted, painterly tones rather than bright game colors.
    static func palette(_ voice: Voice) -> [Character: Color] {
        var p: [Character: Color] = [
            "K": hex(0x1A1820), "E": hex(0x1A1820), "W": hex(0xEDE6D3),
            "S": hex(0xD8A07A), "s": hex(0xA9705A),
        ]
        switch voice {
        case .cautious:
            p["H"] = hex(0xC9CED6); p["h"] = hex(0x8D96A3); p["D"] = hex(0x7FB2E5); p["B"] = hex(0x4A5A7A)
        case .bold:
            p["H"] = hex(0xC8732F); p["Y"] = hex(0xF4E27A); p["R"] = hex(0xB0352B); p["B"] = hex(0xE7D9B8)
        case .accountant:
            p["H"] = hex(0x5A4636); p["G"] = hex(0x4E8A4C); p["O"] = hex(0x2B2B2B); p["T"] = hex(0x7A2E2E)
        case .diplomat:
            p["H"] = hex(0x8A5A44); p["P"] = hex(0xE58F8F); p["L"] = hex(0xA990C9); p["R"] = hex(0xD8455A)
        case .cynic:
            p["H"] = hex(0x3A3633); p["b"] = hex(0x9C7266); p["G"] = hex(0xA88B78)
            p["C"] = hex(0x6B6152); p["M"] = hex(0xE8E2D2); p["w"] = hex(0xB8B8B8)
        case .mystic:
            p["H"] = hex(0x2E2A5C); p["h"] = hex(0xE8D58A); p["Y"] = hex(0xF2C94C); p["S"] = hex(0xC9A28C)
        case .hedonist:
            p["H"] = hex(0x4A2E1F); p["O"] = hex(0x111111); p["P"] = hex(0xE0567A)
            p["Y"] = hex(0xF4E27A); p["R"] = hex(0xD8455A); p["G"] = hex(0x7FC8A9)
        }
        return p
    }

    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}

/// The portrait on a dithered background in the voice's color. Built as a 16×16 bitmap and scaled up
/// without smoothing, so pixels stay hard-edged with no seams between them.
/// Several voices split it into vertical strips: left half one face, right half the other.
struct PixelPortrait: View {
    let voices: [Voice]
    /// Points per art pixel.
    var pixel: CGFloat = 4

    init(voice: Voice, pixel: CGFloat = 4) { self.init(voices: [voice], pixel: pixel) }

    init(voices: [Voice], pixel: CGFloat = 4) {
        self.voices = voices
        self.pixel = pixel
    }

    var body: some View {
        Image(decorative: Self.bitmap(voices), scale: 1)
            .resizable()
            .interpolation(.none)
            .frame(width: CGFloat(PixelArt.size) * pixel, height: CGFloat(PixelArt.size) * pixel)
    }

    private static var cache: [[Voice]: CGImage] = [:]

    static func bitmap(_ voices: [Voice]) -> CGImage {
        if let cached = cache[voices] { return cached }
        let n = PixelArt.size
        let palettes = voices.map { PixelArt.palette($0).mapValues(rgba) }
        let sprites = voices.map { PixelArt.sprite($0).map(Array.init) }
        // Two-tone checker dither, darker towards the bottom, like an old printed card.
        let tints = voices.map { rgba($0.color) }
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let i = x * voices.count / n
                // Two voices: left half of one face, right half of the other. More: the middle of each face.
                let start = i * n / voices.count, width = (i + 1) * n / voices.count - start
                let sx = voices.count == 2 ? x : x - start + (n - width) / 2
                let dithered = y > n / 2 && (x + y) % 2 == 0
                let background = mix(tints[i], dithered || y > n * 3 / 4 ? 0.3 : 0.55)
                // A dark seam where one face hands over to the next.
                let seam = i > 0 && x * voices.count % n < voices.count
                let c = seam ? rgba(.black) : palettes[i][sprites[i][y][sx]] ?? background
                pixels.replaceSubrange((y * n + x) * 4..<(y * n + x) * 4 + 4, with: c)
            }
        }
        let context = CGContext(data: &pixels, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!
        cache[voices] = image
        return image
    }

    private static func rgba(_ color: Color) -> [UInt8] {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return [c.redComponent, c.greenComponent, c.blueComponent].map { UInt8(max(0, min(1, $0)) * 255) } + [255]
    }

    /// The voice color at the given strength over black: muted, painterly.
    private static func mix(_ c: [UInt8], _ strength: Double) -> [UInt8] {
        c.prefix(3).map { UInt8(Double($0) * strength) } + [255]
    }
}
