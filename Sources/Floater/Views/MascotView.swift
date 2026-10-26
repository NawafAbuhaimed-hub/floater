import FloaterCore
import SwiftUI

// MARK: - The character

/// Baby Groot as pixel art on a fixed 20x20 grid.
///
/// Every mood is data, not drawing code: one shared base sprite (`base`) plus a
/// short list of patches that overwrite only the cells that mood changes
/// (eyes, brows, mouth, sprout tips, one prop). Cells are filled as plain
/// rectangles, never scaled from an image, and every rectangle is snapped to a
/// whole number of device pixels so edges stay hard.
///
/// 20pt (pill) = 1pt per cell. 30pt (header) = 1.5pt per cell, exactly 3 device
/// pixels on a 2x display.
///
/// Motion is deliberately tiny: the head dips one cell every half second or so,
/// and now and then the eyes blink. Moods that should look frozen or asleep do
/// neither, and Reduce Motion turns both off.
struct MascotView: View {
    let mood: MascotMood
    let size: CGFloat

    @State private var dipped = false
    @State private var blinking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    init(mood: MascotMood, size: CGFloat) {
        self.mood = mood
        self.size = size
    }

    var body: some View {
        let recipe = MascotSprite.recipe(for: mood, compact: size < 28)
        let grid = MascotSprite.grid(
            for: recipe,
            blink: blinking && recipe.blinks,
            dipped: dipped && recipe.bobs
        )
        let palette = MascotSprite.palette(dark: colorScheme == .dark)
        let scale = displayScale
        Canvas { context, canvasSize in
            MascotSprite.draw(grid, palette: palette, in: &context, side: canvasSize.width, scale: scale)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mood.name)
        .task(id: "\(mood.rawValue)-\(reduceMotion)") {
            await animate(recipe)
        }
    }

    /// One slow loop. Static moods return straight away and never wake up again.
    private func animate(_ recipe: MascotSprite.Recipe) async {
        dipped = false
        blinking = false
        guard !reduceMotion, recipe.bobs || recipe.blinks else { return }
        var step = 0
        while !Task.isCancelled {
            if recipe.bobs {
                try? await Task.sleep(nanoseconds: 550_000_000)
                dipped.toggle()
                step += 1
                if recipe.blinks && step % 9 == 0 {
                    blinking = true
                    try? await Task.sleep(nanoseconds: 140_000_000)
                    blinking = false
                }
            } else {
                try? await Task.sleep(nanoseconds: 4_600_000_000)
                blinking = true
                try? await Task.sleep(nanoseconds: 140_000_000)
                blinking = false
            }
        }
    }
}

// MARK: - Sprite data

/// Palette characters
///
/// Body:   `o` outline (silhouette only)   `b` bark   `l` bark light   `d` bark dark
///         `g` moss   `v` wilted moss   `e` eye   `w` white   `x` face line (brows, mouth, cracks)
///         `m` body plate dark   `n` body plate light
/// Props:  `r` red   `u` blue   `c` cyan   `y` straw / gold   `Y` lightning   `f` flame   `F` flame core
///         `k` black metal   `s` steel   `t` clay   `q` clay shade   `p` pink
/// Patch-only: `.` leave the cell alone, `-` clear the cell. In the base, `.` is transparent.
enum MascotSprite {
    static let n = 20

    // MARK: Base: the sprite every mood starts from (also plain "chilling" Groot)

    /// 20 rows of 20 cells, written as four groups of five so a miscount shows.
    static let base: [String] = [
        "....o ....o o.... o....",   // 0  tendril tips
        "...og o..og bo..o bo...",   // 1
        "..obb o.obg bbo.o bbo..",   // 2
        "..obb bdbbb bbbdb bbo..",   // 3  tendrils merge into the head
        "..obb bbbbb bbbbb bbo..",   // 4
        "..obl lbbbb bbbbl bbo..",   // 5  brow row
        "..obb eebbb bbbee bbo..",   // 6  eyes
        "..obe weebb bbewe ebo..",   // 7  white highlight, upper left
        "..obe eeebb bbeee ebo..",   // 8
        "..obb eebbb bbbee bbo..",   // 9
        "..odb bbbbb bbbbb bdo..",   // 10
        "..obb bbbbx xbbbb bbo..",   // 11 tiny flat mouth
        "...od ddddd ddddd do...",   // 12 chin
        "..... .ommm mmmo. .....",   // 13 neck
        "....o gmmmm mmmmg o....",   // 14 shoulders, moss
        "...om mnnmm mmnnm mo...",   // 15 arms and chest plates
        "...om mmnnm mnnmm mo...",   // 16
        "....o mnnmm mmnnm o....",   // 17
        "..... ommnm mnmmo .....",   // 18 legs
        "..... ooooo ooooo .....",   // 19 feet
    ]

    // MARK: Patches

    /// A small block of cells laid over the grid at (row, col).
    struct Patch {
        let row: Int
        let col: Int
        let lines: [String]

        init(_ row: Int, _ col: Int, _ lines: String...) {
            self.row = row
            self.col = col
            self.lines = lines.map { $0.filter { $0 != " " } }
        }
    }

    struct Recipe {
        /// Drawn before the base, so only cells the base leaves empty show.
        var behind: [Patch] = []
        var patches: [Patch] = []
        /// Slides some rows sideways, for a lean or a slump.
        var shear: (rows: ClosedRange<Int>, dx: Int)?
        var bobs = false
        var blinks = false
    }

    /// Eyes shut flat, swapped in for a blink.
    private static let blinkPatches: [Patch] = [
        Patch(6, 4, "bbbb", "bbbb", "xxxx", "bbbb"),
        Patch(6, 12, "bbbb", "bbbb", "xxxx", "bbbb"),
    ]

    /// Eyes shut in a soft "u", for sleep.
    private static let sleepEyes: [Patch] = [
        Patch(6, 4, "bbbb", "bbbb", "xbbx", "bxxb"),
        Patch(6, 12, "bbbb", "bbbb", "xbbx", "bxxb"),
    ]

    /// Happy "^" eyes.
    private static let happyEyes: [Patch] = [
        Patch(6, 4, "bbbb", "beeb", "ebbe", "bbbb"),
        Patch(6, 12, "bbbb", "beeb", "ebbe", "bbbb"),
    ]

    /// Over-ear headphones: band across the hair line, a cup on each side.
    private static let headphones: [Patch] = [
        Patch(3, 1, String(repeating: "k", count: 18)),
        Patch(4, 1, "k"), Patch(5, 1, "k"),
        Patch(4, 18, "k"), Patch(5, 18, "k"),
        Patch(6, 0, "kr", "kr", "kr", "kr"),
        Patch(6, 18, "rk", "rk", "rk", "rk"),
    ]

    private static func dashes(_ count: Int) -> String { String(repeating: "-", count: count) }
    private static func run(_ ch: Character, _ count: Int) -> String { String(repeating: String(ch), count: count) }

    /// `compact` is true at pill size, where a prop that cannot read is left
    /// out entirely rather than turning into stray pixels.
    static func recipe(for mood: MascotMood, compact: Bool) -> Recipe {
        var r = Recipe()
        switch mood {

        case .gearUp:
            // Iron Man: arc reactor glowing on the chest, sunk into a dark
            // housing: a solid white 2x2 core, a ring of cyan, black around it.
            // Raised brows, open grin.
            r.patches = [
                Patch(4, 5, "xx"), Patch(4, 13, "xx"),
                Patch(11, 8, "xxxx"), Patch(12, 9, "xx"),
                // dark housing (octagon, 6x6)
                Patch(13, 9, "kk"),
                Patch(18, 9, "kk"),
                Patch(14, 8, "k"), Patch(14, 11, "k"),
                Patch(15, 7, "k"), Patch(16, 7, "k"),
                Patch(15, 12, "k"), Patch(16, 12, "k"),
                Patch(17, 8, "k"), Patch(17, 11, "k"),
                // cyan ring and white core
                Patch(14, 9, "cc"),
                Patch(15, 8, "cwwc", "cwwc"),
                Patch(17, 9, "cc"),
            ]
            r.bobs = true
            r.blinks = true

        case .lockedIn:
            // Iron Man: faceplate down over the face (wood stays visible around it),
            // two angled glowing slits for eyes.
            r.patches = [
                Patch(6, 4,
                      "kkkkkkkkkkkk",
                      "ccrrrrrrrrcc",
                      "rrccrrrrccrr",
                      "rrrrrkkrrrrr",
                      "yyyyyyyyyyyy",
                      "yyyykkkkyyyy",
                      "yyyyyyyyyyyy"),
            ]

        case .finalStretch:
            // The one mood with no prop: wide white eyes with pin-prick pupils,
            // brows high, and a plain dark open mouth straining.
            r.patches = [
                Patch(6, 4, ".ww.", "wwww", "wwew", ".ww."),
                Patch(6, 12, ".ww.", "wwww", "weww", ".ww."),
                Patch(4, 4, "xxxx"), Patch(4, 12, "xxxx"),
                Patch(10, 8, "eeee", "eeee", "eeee"),
                Patch(13, 9, "ee"),
            ]
            r.bobs = true

        case .victory:
            // Luffy: straw hat with a red band (it replaces the tendrils, a sprout
            // tuft pokes out of the top). Happy "^ ^" eyes, big open shout, confetti.
            r.patches = [
                Patch(0, 0,
                      dashes(6) + "oyyggyyo" + dashes(6),
                      dashes(5) + "oyyyyyyyyo" + dashes(5),
                      dashes(5) + "orrrrrrrro" + dashes(5),
                      "-o" + run("y", 16) + "o-",
                      "-" + run("o", 18) + "-"),
                Patch(10, 8, "eeee", "eeee", "erre"),
                Patch(7, 0, "r"), Patch(10, 1, "u"), Patch(8, 19, "Y"), Patch(11, 18, "c"),
            ] + happyEyes
            r.bobs = true

        case .onFire:
            // The sprout burns as a flame. Angry brows, a smug grin.
            r.patches = [
                Patch(0, 0,
                      dashes(9) + "ff" + dashes(9),
                      dashes(7) + "ffFFff" + dashes(7),
                      dashes(6) + "ffFFFFff" + dashes(6),
                      "...oo" + "ffFFFFFFff" + "oo..."),
                Patch(4, 4, "x"), Patch(5, 5, "xx"), Patch(6, 7, "x"),
                Patch(4, 15, "x"), Patch(5, 13, "xx"), Patch(6, 12, "x"),
                Patch(10, 7, "x"), Patch(10, 12, "x"), Patch(11, 8, "xxxx"),
            ]
            r.bobs = true
            r.blinks = true

        case .legend:
            // Captain America: a small round shield held at his side, off the
            // chest (dropped at pill size, where it would be a red dot).
            // Lidded left eye, one brow up, smirk.
            r.patches = [
                Patch(6, 4, "xxxx"),
                Patch(4, 13, "xx"),
                Patch(11, 8, "x"), Patch(10, 11, "x"),
            ]
            if !compact {
                r.patches.append(
                    Patch(13, 13,
                          "..rrr..",
                          ".rwwwr.",
                          "rwuuuwr",
                          "rwuwuwr",
                          "rwuuuwr",
                          ".rwwwr.",
                          "..rrr..")
                )
            }

        case .paused:
            // Star-Lord: headphones on, head tipped mid-dance, singing "o",
            // eyes glancing off to one side, one brow up.
            r.patches = headphones + [
                Patch(7, 5, "e"), Patch(7, 6, "w"), Patch(7, 13, "e"), Patch(7, 14, "w"),
                Patch(5, 5, "xx"), Patch(4, 13, "xx"),
                Patch(10, 9, "xx"),
            ]
            r.shear = (0...5, 1)
            r.blinks = true

        case .nagging:
            // Nick Fury: black eyepatch with a strap over the left eye, the other
            // eye heavy-lidded and unimpressed, flat mouth.
            r.patches = [
                Patch(5, 3, ".kkk.", "kkkkk", "kkkkk", "kkkkk", ".kkk."),
                Patch(5, 8, "k"), Patch(4, 9, "k"), Patch(3, 10, "k"), Patch(2, 11, "k"),
                Patch(6, 12, "xxxx", "xxxx"),
                Patch(8, 12, "w"),
                Patch(5, 12, "xxxx"),
                Patch(11, 8, "xxxx"),
            ]

        case .stuck:
            // Cracked bark on forehead, cheek and chest; the sprout folds over and
            // goes limp; worried brows, a frown.
            r.patches = [
                Patch(0, 9, "--"),
                Patch(1, 8, "-oov"), Patch(1, 12, "v"), Patch(2, 13, "v"),
                Patch(3, 11, "x"), Patch(4, 11, "xx"), Patch(5, 12, "x"),
                Patch(10, 4, "xx"), Patch(11, 5, "x"), Patch(12, 6, "x"),
                Patch(15, 8, "x"), Patch(16, 8, "x"), Patch(16, 9, "x"),
                Patch(5, 4, "xx"), Patch(4, 6, "xx"),
                Patch(5, 14, "xx"), Patch(4, 12, "xx"),
                Patch(12, 8, "x"), Patch(12, 11, "x"),
            ]
            r.blinks = true

        case .sleepy:
            // Baby Groot curled low in a clay pot, headphones on, eyes shut,
            // a small yawn.
            r.patches = [
                Patch(13, 0,
                      "---o" + run("t", 12) + "o---",
                      "---o" + run("t", 10) + "qq" + "o---",
                      "----o" + run("t", 8) + "qq" + "o----",
                      "-----o" + run("t", 6) + "qq" + "o-----",
                      "-----o" + run("t", 6) + "qq" + "o-----",
                      "------o" + "ttttqq" + "o------",
                      dashes(6) + "oooooooo" + dashes(6)),
                Patch(10, 9, "xx"),
            ] + sleepEyes + headphones

        case .bored:
            // Zoro's slump: heavy lids, a flat mouth pushed to one side, head
            // slumped over, and one tendril flopped over and drooping.
            r.patches = [
                Patch(6, 4, "xxxx", "xxxx"), Patch(6, 12, "xxxx", "xxxx"),
                Patch(8, 5, "w"), Patch(8, 13, "w"),
                Patch(11, 8, "x"), Patch(11, 10, "b"),
                // right tendril bends over and hangs
                Patch(0, 15, "oo"),
                Patch(1, 15, "bgg"),
                Patch(2, 18, "g"), Patch(3, 18, "g"),
            ]
            r.shear = (0...5, -1)

        case .chilling:
            // Plain Groot, moss on the shoulders, a small easy smile.
            r.patches = [Patch(10, 8, "x"), Patch(10, 11, "x")]
            r.bobs = true
            r.blinks = true
        }
        return r
    }

    // MARK: Building the grid

    static func grid(for recipe: Recipe, blink: Bool, dipped: Bool) -> [[Character]] {
        var grid = [[Character]](repeating: [Character](repeating: ".", count: n), count: n)
        for patch in recipe.behind { apply(patch, to: &grid) }
        for (r, line) in base.enumerated() where r < n {
            let cells = Array(line.filter { $0 != " " }.padding(toLength: n, withPad: ".", startingAt: 0))
            for c in 0..<n where cells[c] != "." { grid[r][c] = cells[c] }
        }
        for patch in recipe.patches { apply(patch, to: &grid) }
        if blink {
            for patch in blinkPatches { apply(patch, to: &grid) }
        }
        if let shear = recipe.shear {
            shift(&grid, rows: shear.rows, dx: shear.dx, dy: 0)
        }
        if dipped {
            // The head sinks one cell; the body stays put.
            shift(&grid, rows: 0...12, dx: 0, dy: 1)
            // The sunken chin lands on row 13, which is the neck row. Anything a
            // mood draws on that row belongs to the body (the arc reactor's
            // housing top), so it goes back on top and never flickers.
            for patch in recipe.patches where patch.row == 13 { apply(patch, to: &grid) }
        }
        return grid
    }

    private static func apply(_ patch: Patch, to grid: inout [[Character]]) {
        for (i, line) in patch.lines.enumerated() {
            for (j, ch) in line.enumerated() {
                let r = patch.row + i
                let c = patch.col + j
                guard (0..<n).contains(r), (0..<n).contains(c), ch != "." else { continue }
                grid[r][c] = (ch == "-") ? "." : ch
            }
        }
    }

    private static func shift(_ grid: inout [[Character]], rows: ClosedRange<Int>, dx: Int, dy: Int) {
        let old = grid
        for r in rows { for c in 0..<n { grid[r][c] = "." } }
        for r in rows {
            for c in 0..<n where old[r][c] != "." {
                let nr = r + dy
                let nc = c + dx
                if (0..<n).contains(nr), (0..<n).contains(nc) { grid[nr][nc] = old[r][c] }
            }
        }
    }

    // MARK: Colour

    static func palette(dark: Bool) -> [Character: Color] {
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        var p: [Character: Color] = [:]
        // The silhouette outline is brightened on dark panels so he stays separate.
        p["o"] = dark ? rgb(0.58, 0.38, 0.18) : rgb(0.36, 0.22, 0.09)
        p["b"] = rgb(0.80, 0.48, 0.19)
        p["l"] = rgb(0.89, 0.60, 0.27)
        p["d"] = rgb(0.68, 0.37, 0.14)
        p["g"] = rgb(0.55, 0.62, 0.16)
        p["v"] = rgb(0.52, 0.50, 0.30)
        p["e"] = rgb(0.14, 0.10, 0.08)
        p["w"] = rgb(0.94, 0.96, 0.96)
        p["x"] = rgb(0.24, 0.14, 0.07)
        p["m"] = rgb(0.40, 0.24, 0.10)
        p["n"] = rgb(0.72, 0.41, 0.16)
        p["r"] = Theme.color(for: .overdue)
        p["u"] = Theme.color(for: .inProgress)
        p["c"] = rgb(0.40, 0.90, 1.00)
        p["y"] = rgb(0.96, 0.80, 0.28)
        p["Y"] = rgb(1.00, 0.95, 0.35)
        p["f"] = Theme.streak
        p["F"] = rgb(1.00, 0.85, 0.30)
        p["k"] = dark ? rgb(0.20, 0.20, 0.24) : rgb(0.10, 0.10, 0.12)
        p["s"] = rgb(0.65, 0.68, 0.72)
        p["t"] = rgb(0.80, 0.40, 0.24)
        p["q"] = rgb(0.60, 0.28, 0.17)
        p["p"] = rgb(0.95, 0.45, 0.65)
        return p
    }

    // MARK: Drawing

    /// Fills one rectangle per cell (merged per colour into a single path).
    /// The cell size is a whole number of device pixels and the sprite is
    /// centred on a pixel boundary, so nothing lands on a fraction of a pixel.
    static func draw(
        _ grid: [[Character]],
        palette: [Character: Color],
        in context: inout GraphicsContext,
        side: CGFloat,
        scale: CGFloat
    ) {
        let s = max(scale, 1)
        let cellPixels = max(1, (side * s / CGFloat(n)).rounded(.down))
        let cell = cellPixels / s
        let origin = ((side * s - cellPixels * CGFloat(n)) / 2).rounded(.down) / s

        var paths: [Character: Path] = [:]
        for (r, row) in grid.enumerated() {
            for (c, ch) in row.enumerated() where ch != "." {
                paths[ch, default: Path()].addRect(
                    CGRect(
                        x: origin + CGFloat(c) * cell,
                        y: origin + CGFloat(r) * cell,
                        width: cell,
                        height: cell
                    )
                )
            }
        }
        for (ch, path) in paths {
            guard let colour = palette[ch] else { continue }
            context.fill(path, with: .color(colour), style: FillStyle(antialiased: false))
        }
    }
}

// MARK: - Speech bubble

/// A rounded speech bubble with a small tail on its leading edge.
struct MascotBubbleShape: Shape {
    var tail: CGFloat = 6
    var corner: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        var path = Path(
            roundedRect: CGRect(x: rect.minX + tail, y: rect.minY, width: rect.width - tail, height: rect.height),
            cornerRadius: corner,
            style: .continuous
        )
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + tail + 1, y: rect.midY - 5))
        path.addLine(to: CGPoint(x: rect.minX + tail + 1, y: rect.midY + 5))
        path.closeSubpath()
        return path
    }
}

/// What he says, in the app's glass styling. It never takes clicks.
struct MascotBubble: View {
    let text: String

    /// Horizontal padding inside the bubble (tail side + far side).
    static let inset: CGFloat = 16 + 10
    /// Below this much room for text, a line wraps to ragged scraps or gets cut.
    static let minTextWidth: CGFloat = 90

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 5)
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .background(
                ZStack {
                    MascotBubbleShape().fill(.regularMaterial)
                    MascotBubbleShape().fill(Color.primary.opacity(0.09))
                }
            )
            .allowsHitTesting(false)
    }
}

/// Wraps the content that sits right beside the mascot. While he speaks, that
/// content fades out and his bubble fades in on top of the same space, so the
/// bubble never reaches into the task list or outside the window.
struct MascotBubbleHost<Content: View>: View {
    let line: String
    let speaking: Bool
    /// How far the bubble's tail reaches back toward him.
    var reach: CGFloat = 8
    /// Room to the trailing side (controls the caller fades out while this is
    /// in use). When the content is too narrow to show a readable line, the
    /// bubble stretches over this much extra width. Zero means never stretch.
    var bleed: CGFloat = 0
    /// Told whenever the bubble starts or stops needing that extra room, so the
    /// caller can fade its controls out of the way.
    var onTight: ((Bool) -> Void)?
    @ViewBuilder var content: () -> Content

    @State private var width: CGFloat = .greatestFiniteMagnitude

    private var tight: Bool {
        bleed > 0 && width + reach - MascotBubble.inset < MascotBubble.minTextWidth
    }

    var body: some View {
        content()
            .background(
                GeometryReader { geo in
                    Color.clear.onChange(of: geo.size.width, initial: true) { _, new in width = new }
                }
            )
            .opacity(speaking ? 0 : 1)
            .overlay(alignment: .leading) {
                MascotBubble(text: line)
                    .padding(.leading, -reach)
                    .padding(.trailing, tight ? -bleed : 0)
                    .opacity(speaking ? 1 : 0)
                    .scaleEffect(speaking ? 1 : 0.94, anchor: .leading)
            }
            .animation(.easeInOut(duration: 0.18), value: speaking)
            .onChange(of: tight, initial: true) { _, now in onTight?(now) }
    }
}

/// Shows the bubble while the pointer is on him. Hover only: a tap gesture here
/// would swallow the mouse-down and stop the panel being dragged by him.
private struct MascotSpeechTrigger: ViewModifier {
    @Binding var speaking: Bool

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { speaking = $0 }
    }
}

extension View {
    /// Drives `speaking` from hover on this view.
    func mascotSpeech(_ speaking: Binding<Bool>) -> some View {
        modifier(MascotSpeechTrigger(speaking: speaking))
    }
}
