import SwiftUI

// MARK: - iOS version compatibility shims

extension View {
    /// Applies `.glassEffect(.regular, in:)` on iOS 26+.
    /// Falls back to no effect on earlier OS versions.
    @ViewBuilder
    func regularGlassEffect(in shape: some Shape) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
        }
    }
}
