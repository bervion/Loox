import SwiftUI
import CoreImage.CIFilterBuiltins

/// Renders a payload as a QR code with a soft, Telegram-style look: the data
/// modules are drawn as rounded blobs (isolated cells become dots, runs merge
/// into rounded pills) and the three finder patterns are rounded frames. Solid
/// black on a white tile — QR readers need dark-on-light regardless of theme, and
/// the vector drawing stays crisp at any size (including the Emergency Kit PDF).
struct QRCodeView: View {
    let payload: String
    private let matrix: [[Bool]]?

    init(payload: String) {
        self.payload = payload
        self.matrix = Self.makeMatrix(payload)
    }

    var body: some View {
        Canvas { ctx, size in
            guard let matrix, !matrix.isEmpty else { return }
            draw(matrix, in: ctx, size: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(Space.s4)
        .background(.white, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Drawing

    private func draw(_ matrix: [[Bool]], in ctx: GraphicsContext, size: CGSize) {
        let n = matrix.count
        let side = min(size.width, size.height)
        let cell = side / CGFloat(n)
        let ox = (size.width - side) / 2
        let oy = (size.height - side) / 2

        // The three 7×7 finder patterns (top-left, top-right, bottom-left).
        let finders = [(0, 0), (0, n - 7), (n - 7, 0)]
        func inFinder(_ r: Int, _ c: Int) -> Bool {
            finders.contains { r >= $0.0 && r < $0.0 + 7 && c >= $0.1 && c < $0.1 + 7 }
        }
        func dark(_ r: Int, _ c: Int) -> Bool {
            r >= 0 && r < n && c >= 0 && c < n && matrix[r][c]
        }

        // Data modules — one path, corners rounded only where there's no dark
        // neighbour, so adjacent modules merge into rounded shapes.
        var path = Path()
        let radius = cell * 0.5
        for r in 0..<n {
            for c in 0..<n where matrix[r][c] && !inFinder(r, c) {
                let rect = CGRect(x: ox + CGFloat(c) * cell, y: oy + CGFloat(r) * cell,
                                  width: cell, height: cell)
                addRoundedCell(&path, rect, radius,
                               tl: !dark(r - 1, c) && !dark(r, c - 1),
                               tr: !dark(r - 1, c) && !dark(r, c + 1),
                               br: !dark(r + 1, c) && !dark(r, c + 1),
                               bl: !dark(r + 1, c) && !dark(r, c - 1))
            }
        }
        ctx.fill(path, with: .color(.black))

        for (fr, fc) in finders {
            let rect = CGRect(x: ox + CGFloat(fc) * cell, y: oy + CGFloat(fr) * cell,
                              width: 7 * cell, height: 7 * cell)
            drawFinder(rect, cell: cell, in: ctx)
        }
    }

    /// Rounded finder: a rounded outer frame with a rounded solid centre.
    private func drawFinder(_ rect: CGRect, cell: CGFloat, in ctx: GraphicsContext) {
        ctx.fill(Path(roundedRect: rect, cornerRadius: cell * 2.2, style: .continuous),
                 with: .color(.black))
        ctx.fill(Path(roundedRect: rect.insetBy(dx: cell, dy: cell), cornerRadius: cell * 1.6, style: .continuous),
                 with: .color(.white))
        ctx.fill(Path(roundedRect: rect.insetBy(dx: 2 * cell, dy: 2 * cell), cornerRadius: cell, style: .continuous),
                 with: .color(.black))
    }

    /// Append a cell whose corners are individually rounded (`radius`) or square.
    private func addRoundedCell(_ path: inout Path, _ rect: CGRect, _ r: CGFloat,
                                tl: Bool, tr: Bool, br: Bool, bl: Bool) {
        let (x0, y0, x1, y1) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        path.move(to: CGPoint(x: x0 + (tl ? r : 0), y: y0))
        path.addLine(to: CGPoint(x: x1 - (tr ? r : 0), y: y0))
        if tr { path.addQuadCurve(to: CGPoint(x: x1, y: y0 + r), control: CGPoint(x: x1, y: y0)) }
        path.addLine(to: CGPoint(x: x1, y: y1 - (br ? r : 0)))
        if br { path.addQuadCurve(to: CGPoint(x: x1 - r, y: y1), control: CGPoint(x: x1, y: y1)) }
        path.addLine(to: CGPoint(x: x0 + (bl ? r : 0), y: y1))
        if bl { path.addQuadCurve(to: CGPoint(x: x0, y: y1 - r), control: CGPoint(x: x0, y: y1)) }
        path.addLine(to: CGPoint(x: x0, y: y0 + (tl ? r : 0)))
        if tl { path.addQuadCurve(to: CGPoint(x: x0 + r, y: y0), control: CGPoint(x: x0, y: y0)) }
        path.closeSubpath()
    }

    // MARK: QR matrix

    /// Generate the QR module grid (dark = true) via CoreImage, trimming the white
    /// quiet-zone border so `[0][0]` is the top-left finder's corner module.
    private static func makeMatrix(_ payload: String) -> [[Bool]]? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let w = Int(output.extent.width), h = Int(output.extent.height)
        guard w > 0, h > 0,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }

        // Read the native 1px-per-module image into a grayscale buffer (CGContext
        // owns the buffer; use its real bytesPerRow stride to index safely).
        guard let bmp = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        bmp.interpolationQuality = .none
        bmp.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let base = bmp.data else { return nil }
        let stride = bmp.bytesPerRow
        let ptr = base.bindMemory(to: UInt8.self, capacity: stride * h)

        var grid = (0..<h).map { y in (0..<w).map { x in ptr[y * stride + x] < 128 } }
        return trim(&grid)
    }

    /// Drop fully-empty border rows/columns (the quiet zone).
    private static func trim(_ grid: inout [[Bool]]) -> [[Bool]]? {
        let h = grid.count, w = grid.first?.count ?? 0
        guard h > 0, w > 0 else { return nil }
        var top = 0, bottom = h - 1, left = 0, right = w - 1
        func rowEmpty(_ r: Int) -> Bool { !grid[r].contains(true) }
        func colEmpty(_ c: Int) -> Bool { !(0..<h).contains { grid[$0][c] } }
        while top < bottom, rowEmpty(top) { top += 1 }
        while bottom > top, rowEmpty(bottom) { bottom -= 1 }
        while left < right, colEmpty(left) { left += 1 }
        while right > left, colEmpty(right) { right -= 1 }
        guard bottom >= top, right >= left else { return nil }
        return (top...bottom).map { Array(grid[$0][left...right]) }
    }
}
