import SwiftUI

struct ContributionCell: View {
    let day: ContributionDay
    var size: CGFloat = 11

    var body: some View {
        Circle()
            .fill(day.intensityColor)
            .frame(width: size, height: size)
    }
}
