//
//  BrandLogoView.swift
//  Kuruş / Cent — Marka işareti, sol üst başlık ve uygulama ikonu dışa aktarıcısı
//
//  Hedef: App
//

import SwiftUI

struct KurusMarkShape: View {
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.12, to: 0.62)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.96, blue: 0.98),
                            Color(red: 0.56, green: 0.56, blue: 0.60)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: size * 0.16, lineCap: .round)
                )
                .rotationEffect(.degrees(-15))

            Circle()
                .trim(from: 0.14, to: 0.58)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.19, green: 0.82, blue: 0.35),
                            Color(red: 0.12, green: 0.65, blue: 0.28)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: size * 0.16, lineCap: .round)
                )
                .rotationEffect(.degrees(165))
                .offset(x: size * 0.06, y: size * 0.06)
        }
        .frame(width: size, height: size)
    }
}

struct BrandHeaderView: View {
    var body: some View {
        HStack(spacing: 10) {
            KurusMarkShape(size: 20)

            // Türkçe cihazda "Kuruş", diğer dillerde "Cent"
            Text(AppLanguage.brandName)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .tracking(-0.7)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.98, blue: 0.99),
                            Color(red: 0.78, green: 0.78, blue: 0.82)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

struct KurusAppIconExporter: View {
    var body: some View {
        ZStack {
            Color(red: 0.047, green: 0.047, blue: 0.055)
            RadialGradient(
                colors: [Color.white.opacity(0.08), Color.clear],
                center: .top,
                startRadius: 50,
                endRadius: 700
            )
            KurusMarkShape(size: 520)
        }
        .frame(width: 1024, height: 1024)
    }
}

#Preview("Başlık") {
    BrandHeaderView()
        .padding(24)
        .background(Theme.background)
}

#Preview("Uygulama ikonu") {
    KurusAppIconExporter()
        .scaleEffect(0.3)
        .frame(width: 320, height: 320)
}
