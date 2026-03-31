import SwiftUI

struct ContributionCell: View {
    let day: ContributionDay
    var size: CGFloat = 11

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(day.intensityColor)
            .frame(width: size, height: size)
    }
}
