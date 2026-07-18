//
//  SplashView.swift
//  OrgSync
//
//  Branded launch transition shown immediately after the system launch screen.
//

import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            BlueprintGrid()
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 18) {
                Image("OrgSyncMark")
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
                    .frame(width: 176, height: 176)
                    .shadow(color: .black.opacity(0.24), radius: 18, y: 10)
                    .accessibilityHidden(true)

                VStack(spacing: 5) {
                    Text("OrgSync")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .accessibilityAddTraits(.isHeader)
                    Text("Your notes, in sync.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .foregroundStyle(.white)
            }
        }
    }
}

private struct BlueprintGrid: View {
    var body: some View {
        Canvas { context, size in
            var grid = Path()
            for x in stride(from: 0, through: size.width, by: 28) {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: 28) {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(.white.opacity(0.075)), lineWidth: 1)

            let circleSize = min(size.width, size.height) * 0.9
            let circle = CGRect(
                x: (size.width - circleSize) / 2,
                y: (size.height - circleSize) / 2,
                width: circleSize,
                height: circleSize
            )
            context.stroke(Path(ellipseIn: circle), with: .color(.white.opacity(0.1)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    SplashView()
}
