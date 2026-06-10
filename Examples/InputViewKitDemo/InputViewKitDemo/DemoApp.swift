import SwiftUI

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                CalculatorScreen()
                    .tabItem { Label("Calculator", systemImage: "plus.forwardslash.minus") }
                FormScreen()
                    .tabItem { Label("Form", systemImage: "list.bullet.rectangle") }
                ThemeScreen()
                    .tabItem { Label("Theme", systemImage: "paintpalette") }
            }
        }
    }
}
