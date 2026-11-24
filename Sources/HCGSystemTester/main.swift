// SwiftPM entry point: `swift run HCGSystemTester` launches the native macOS app.
#if os(macOS)
import AppKit
import HCGSystemTesterUI

// When launched from a terminal (not from an .app bundle) make sure the app gets a Dock icon and focus.
NSApplication.shared.setActivationPolicy(.regular)
HCGSystemTesterApplication.main()
#else
print("HCG System Tester's interface requires macOS. The core engine and tests build on this platform.")
#endif
