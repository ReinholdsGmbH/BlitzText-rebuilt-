#!/usr/bin/env swift
// iOS-Variante des BlitzText-Icons: randlos, iOS rundet die Ecken selbst ab.
// Erzeugt PNG @ 1024x1024 für App/Assets.xcassets/AppIcon.appiconset.
import SwiftUI
import AppKit

@MainActor
struct IconRenderer {
    static func render(to outputURL: URL) {
        let size: CGFloat = 1024
        let view = IconView().frame(width: size, height: size)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write("rendering failed\n".data(using: .utf8)!)
            exit(1)
        }
        try? png.write(to: outputURL)
        print("wrote \(outputURL.path)")
    }
}

struct IconView: View {
    var body: some View {
        ZStack {
            // Randlos: iOS legt die Eckenmaske selbst an
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.78, blue: 0.18),
                            Color(red: 1.00, green: 0.45, blue: 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Blitz mit weicher Schattenwirkung
            Image(systemName: "bolt.fill")
                .resizable()
                .scaledToFit()
                .padding(220)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 14)
        }
    }
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: make-icon.swift <output.png>")
    exit(2)
}
let url = URL(fileURLWithPath: args[1])
Task { @MainActor in
    IconRenderer.render(to: url)
    exit(0)
}
RunLoop.main.run()
