import SwiftUI

// The Keel mark's proportions, shared by the popover and the menu bar so the two never drift.
// Heights are measured upward from the bottom of the inner disc.
struct MarkGeometry {
  // The limit line never goes above this share of the disc, so a little air always shows over it.
  static let maxLineFraction = 0.92

  let side: CGFloat
  let level: Double
  let limit: Int?

  var outer: CGFloat { side / 2 }
  var ringWidth: CGFloat { side * 0.1 }
  var inner: CGFloat { outer - ringWidth - side * 0.07 }
  var gap: CGFloat { side * 0.08 }

  // nil without a limit: the ring is whole and the level can fill the disc.
  var lineHeight: CGFloat? {
    limit.map { 2 * inner * CGFloat(min(Double($0) / 100, Self.maxLineFraction)) }
  }

  // The level stops just under the line, the way the battery stops at the limit.
  var fillHeight: CGFloat {
    let charge = 2 * inner * CGFloat(min(max(level, 0), 1))
    guard let lineHeight else { return charge }
    return min(charge, lineHeight - gap / 2)
  }
}

// The Keel mark, live: the ring is cut by the limit line and the level fills to the battery's
// charge, in the state's colour. The menu bar draws the same mark in one colour.
struct LiveMark: View {
  let level: Double
  let limit: Int?
  let color: Color

  var body: some View {
    Canvas { context, size in
      let mark = MarkGeometry(side: min(size.width, size.height), level: level, limit: limit)
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      // SwiftUI's y grows downward, so heights go up from the disc's bottom edge.
      let discBottom = center.y + mark.inner
      let ring = Path(ellipseIn: CGRect(x: center.x - mark.outer + mark.ringWidth / 2,
                                        y: center.y - mark.outer + mark.ringWidth / 2,
                                        width: 2 * mark.outer - mark.ringWidth,
                                        height: 2 * mark.outer - mark.ringWidth))
      var ringContext = context
      if let lineHeight = mark.lineHeight {
        var keep = Path(CGRect(origin: .zero, size: size))
        keep.addRect(CGRect(x: 0, y: discBottom - lineHeight - mark.gap / 2, width: size.width, height: mark.gap))
        ringContext.clip(to: keep, style: FillStyle(eoFill: true))
      }
      ringContext.stroke(ring, with: .style(.primary), lineWidth: mark.ringWidth)
      var fill = context
      fill.clip(to: Path(ellipseIn: CGRect(x: center.x - mark.inner, y: center.y - mark.inner,
                                           width: 2 * mark.inner, height: 2 * mark.inner)))
      let top = discBottom - mark.fillHeight
      fill.fill(Path(CGRect(x: 0, y: top, width: size.width, height: size.height - top)), with: .color(color))
    }
    .frame(width: 54, height: 54)
    .accessibilityHidden(true)
  }
}
