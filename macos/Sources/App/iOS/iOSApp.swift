import SwiftUI
import VoidKit

@main
struct Void_iOSApp: App {
    @StateObject private var void_app: Void.App

    init() {
        if void_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != VOID_SUCCESS {
            preconditionFailure("Initialize void backend failed")
        }
        _void_app = StateObject(wrappedValue: Void.App())
    }

    var body: some Scene {
        WindowGroup {
            iOS_VoidTerminal()
                .environmentObject(void_app)
        }
    }
}

struct iOS_VoidTerminal: View {
    @EnvironmentObject private var void_app: Void.App

    var body: some View {
        ZStack {
            // Make sure that our background color extends to all parts of the screen
            Color(void_app.config.backgroundColor).ignoresSafeArea()

            Void.Terminal()
        }
    }
}

struct iOS_VoidInitView: View {
    @EnvironmentObject private var void_app: Void.App

    var body: some View {
        VStack {
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 96)
            Text("Void")
            Text("State: \(void_app.readiness.rawValue)")
        }
        .padding()
    }
}
