// HCG System Tester — Xcode application target entry point.
// All application code lives in the HCGSystemTesterUI package product (../Sources),
// so the Xcode build and the SwiftPM build (`swift run HCGSystemTester`) are identical.
import SwiftUI
import HCGSystemTesterUI

@main
@MainActor
enum AppMain {
    static func main() {
        HCGSystemTesterApplication.main()
    }
}
