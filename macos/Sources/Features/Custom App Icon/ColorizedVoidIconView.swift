import SwiftUI
import Cocoa

// For testing.
struct ColorizedVoidIconView: View {
    var body: some View {
        Image(nsImage: ColorizedVoidIcon(
            screenColors: [.purple, .blue],
            ghostColor: .yellow,
            frame: .aluminum
        ).makeImage(in: .main)!)
    }
}
