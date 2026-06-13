import AppKit
import SwiftUI

@available(macOS 14.0, *)
struct IconView: View {
    var body: some View {
        ZStack {
            // 背景：macOS 风格圆角渐变
            RoundedRectangle(cornerRadius: 224, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.55, blue: 0.95),
                        Color(red: 0.10, green: 0.35, blue: 0.75)
                    ],
                    startPoint: .top, endPoint: .bottom
                ))

            // 数据库圆柱（堆叠 3 层）
            VStack(spacing: -28) {
                ForEach(0..<3, id: \.self) { _ in
                    Ellipse()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 460, height: 110)
                        .overlay(
                            Ellipse().stroke(Color.white, lineWidth: 4)
                        )
                }
            }
            .offset(y: -10)

            // 藤蔓 ——  绿色波浪线条 + 叶片
            VineShape()
                .stroke(
                    LinearGradient(
                        colors: [Color.green.opacity(0.95),
                                 Color(red: 0.10, green: 0.55, blue: 0.20)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 900, height: 900)

            // 几片叶子
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: "leaf.fill")
                    .font(.system(size: 110))
                    .foregroundStyle(LinearGradient(
                        colors: [Color.green, Color.green.opacity(0.7)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .rotationEffect(.degrees([0, 35, -25, 60, -40][i]))
                    .offset(x: [-360, 320, -300, 340, -160][i],
                            y: [-200, -260, 120, 80, 320][i])
            }
        }
        .frame(width: 1024, height: 1024)
    }
}

struct VineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        // S 形藤蔓，左下到右上
        p.move(to: CGPoint(x: w * 0.05, y: h * 0.85))
        p.addCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.50),
            control1: CGPoint(x: w * 0.20, y: h * 0.95),
            control2: CGPoint(x: w * 0.30, y: h * 0.55)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.95, y: h * 0.15),
            control1: CGPoint(x: w * 0.70, y: h * 0.45),
            control2: CGPoint(x: w * 0.80, y: h * 0.05)
        )
        return p
    }
}

if #available(macOS 14.0, *) {
    MainActor.assumeIsolated {
        let view = IconView()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        if let nsImage = renderer.nsImage,
           let tiff = nsImage.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
            print("Wrote \(CommandLine.arguments[1])")
        } else {
            print("Failed to render"); exit(1)
        }
    }
} else {
    print("Requires macOS 14"); exit(1)
}
