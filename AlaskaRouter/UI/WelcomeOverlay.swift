// One-time first-launch welcome card. Marker-Felt handwriting + a wobbly
// hand-drawn arrow pointing down to the bottom sheet. Tap anywhere to dismiss.
//
// Shown when UserDefaults["hasSeenWelcome"] is missing/false. Dismiss writes
// the flag so we never show it again.

import SwiftUI

struct WelcomeOverlay: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Full-screen tap-to-dismiss layer with a soft dim.
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 14) {
                Spacer()

                VStack(spacing: 6) {
                    Text("Hi! Made you a fresh trip to start with.\nTap below to add your first stop ↓")
                        .font(.custom("Marker Felt", size: 22))
                        .foregroundStyle(Color(red: 0.18, green: 0.12, blue: 0.08))
                        .multilineTextAlignment(.center)
                    Text("tap anywhere to dismiss")
                        .font(.custom("Marker Felt", size: 12))
                        .foregroundStyle(Color(red: 0.18, green: 0.12, blue: 0.08).opacity(0.55))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 1.0, green: 0.96, blue: 0.84))
                        .shadow(color: .black.opacity(0.20), radius: 12, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(red: 0.45, green: 0.30, blue: 0.15).opacity(0.35), lineWidth: 1.2)
                )
                .rotationEffect(.degrees(-1.2))
                .padding(.horizontal, 36)

                WobblyArrow()
                    .stroke(
                        Color(red: 0.18, green: 0.12, blue: 0.08),
                        style: StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 60, height: 110)
                    .shadow(color: .black.opacity(0.20), radius: 1, y: 1)
                    .padding(.bottom, 150)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

/// Slightly-imperfect down arrow drawn with quadratic curves to feel
/// hand-drawn rather than mechanical.
private struct WobblyArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let topX = rect.midX - 1
        let tipX = rect.midX + 2
        let tipY = rect.maxY - 4

        // Main shaft: top to tip, with a gentle S-wobble.
        p.move(to: CGPoint(x: topX, y: rect.minY + 4))
        p.addQuadCurve(
            to: CGPoint(x: rect.midX + 3, y: rect.midY - 6),
            control: CGPoint(x: rect.midX - 8, y: rect.minY + 26)
        )
        p.addQuadCurve(
            to: CGPoint(x: tipX, y: tipY),
            control: CGPoint(x: rect.midX + 9, y: rect.midY + 30)
        )

        // Left feather of the arrowhead.
        p.move(to: CGPoint(x: tipX, y: tipY))
        p.addQuadCurve(
            to: CGPoint(x: tipX - 18, y: tipY - 16),
            control: CGPoint(x: tipX - 12, y: tipY - 6)
        )

        // Right feather of the arrowhead.
        p.move(to: CGPoint(x: tipX, y: tipY))
        p.addQuadCurve(
            to: CGPoint(x: tipX + 14, y: tipY - 18),
            control: CGPoint(x: tipX + 11, y: tipY - 7)
        )
        return p
    }
}

enum WelcomeFlag {
    private static let key = "hasSeenWelcome"
    static var shouldShow: Bool { !UserDefaults.standard.bool(forKey: key) }
    static func markSeen() { UserDefaults.standard.set(true, forKey: key) }
}
