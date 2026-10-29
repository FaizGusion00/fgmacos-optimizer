import SwiftUI

/// Helpers so the app runs on macOS 13 (Ventura) while keeping Sonoma+ polish when available.
extension View {
    @ViewBuilder
    func fgOnChange<V: Equatable>(of value: V, perform: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, newValue in perform(newValue) }
        } else {
            self.onChange(of: value, perform: perform)
        }
    }

    @ViewBuilder
    func fgSymbolBounce(value: some Equatable) -> some View {
        if #available(macOS 14.0, *) {
            self.symbolEffect(.bounce, value: value)
        } else {
            self
        }
    }

    @ViewBuilder
    func fgSymbolPulse(isActive: Bool) -> some View {
        if #available(macOS 14.0, *) {
            self.symbolEffect(.pulse, options: .repeating.speed(0.45), isActive: isActive)
        } else {
            self.opacity(isActive ? 1 : 0.85)
        }
    }

    @ViewBuilder
    func fgNumericTextTransition() -> some View {
        if #available(macOS 13.0, *) {
            self.contentTransition(.numericText())
        } else {
            self
        }
    }
}
