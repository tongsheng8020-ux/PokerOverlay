import UIKit

/// 把决策画成 16:9 的浮窗画面。
enum OverlayRenderer {
    static let canvas = CGSize(width: 640, height: 360)

    static func image(for decision: Decision?, mode: String) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        return UIGraphicsImageRenderer(size: canvas, format: fmt).image { ctx in
            let c = ctx.cgContext
            let rect = CGRect(origin: .zero, size: canvas)

            let colors = [UIColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 1).cgColor,
                          UIColor(red: 0.10, green: 0.13, blue: 0.20, alpha: 1).cgColor]
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors as CFArray, locations: [0, 1]) {
                c.drawLinearGradient(g, start: CGPoint(x: 0, y: 0),
                                     end: CGPoint(x: canvas.width, y: canvas.height), options: [])
            }

            let modeText = mode == "short" ? "短牌" : (mode == "team" ? "伙牌" : "长牌")
            draw(modeText, at: CGPoint(x: 26, y: 22), size: 22, color: UIColor(white: 0.55, alpha: 1), bold: true)

            guard let d = decision, let action = d.action, !action.isEmpty else {
                draw("等待识别…", at: CGPoint(x: 26, y: 120), size: 54, color: .white, bold: true)
                draw("打开直播后自动刷新", at: CGPoint(x: 28, y: 196), size: 24,
                     color: UIColor(white: 0.6, alpha: 1), bold: false)
                return
            }

            let actionColor: UIColor
            switch action {
            case "RAISE", "BET": actionColor = UIColor(red: 0.25, green: 0.85, blue: 0.5, alpha: 1)
            case "FOLD": actionColor = UIColor(red: 1, green: 0.36, blue: 0.36, alpha: 1)
            default: actionColor = UIColor(red: 0.35, green: 0.65, blue: 1, alpha: 1)
            }

            draw(action, at: CGPoint(x: 24, y: 56), size: 96, color: actionColor, bold: true)

            let size = d.size
            if !size.isEmpty {
                draw(size, at: CGPoint(x: 24, y: 172), size: 34,
                     color: UIColor(red: 1, green: 0.78, blue: 0.4, alpha: 1), bold: true)
            }

            let reason = d.reason
            if !reason.isEmpty {
                let para = NSMutableParagraphStyle()
                para.lineBreakMode = .byWordWrapping
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 22, weight: .regular),
                    .foregroundColor: UIColor(white: 0.78, alpha: 1),
                    .paragraphStyle: para
                ]
                let box = CGRect(x: 24, y: 220, width: canvas.width - 48, height: 74)
                (reason as NSString).draw(with: box, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                          attributes: attrs, context: nil)
            }

            let conf = CGFloat(max(0, min(100, d.confidence))) / 100
            let barRect = CGRect(x: 26, y: 318, width: 300, height: 8)
            let track = UIBezierPath(roundedRect: barRect, cornerRadius: 4)
            UIColor(white: 0.2, alpha: 1).setFill()
            track.fill()
            if conf > 0 {
                let fill = UIBezierPath(roundedRect: CGRect(x: 26, y: 318, width: 300 * conf, height: 8),
                                        cornerRadius: 4)
                UIColor(red: 0.35, green: 0.65, blue: 1, alpha: 1).setFill()
                fill.fill()
            }
            draw("置信度 \(d.confidence) · \(d.latency)ms", at: CGPoint(x: 340, y: 306), size: 18,
                 color: UIColor(white: 0.5, alpha: 1), bold: false)
        }
    }

    private static func draw(_ text: String, at point: CGPoint, size: CGFloat,
                             color: UIColor, bold: Bool) {
        let font = bold ? UIFont.systemFont(ofSize: size, weight: .heavy)
                        : UIFont.systemFont(ofSize: size, weight: .regular)
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }
}
