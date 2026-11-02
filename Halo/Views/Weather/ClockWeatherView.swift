import SwiftUI

/// Expanded content when nothing is playing: the time and, when it's known, the weather.
struct ClockWeatherView: View {
    let weather: WeatherService

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if let report = weather.report(at: context.date) {
                    WeatherSummaryView(report: report)
                        .transition(.opacity)
                }
            }
            .foregroundStyle(.white)
            .frame(maxHeight: .infinity)
            .animation(.easeOut(duration: 0.25), value: weather.latest)
        }
        // Opening the island is what makes the weather worth refreshing.
        .task { weather.refreshIfNeeded() }
    }
}

private struct WeatherSummaryView: View {
    let report: WeatherReport
    @AppStorage(PreferenceKey.temperatureUnit) private var unit = TemperatureUnit.system

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: report.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 30))
            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: unit.text(celsius: report.temperature))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                HStack(spacing: 6) {
                    range("arrow.down", report.minimum)
                    range("arrow.up", report.maximum)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(report.condition.title))
                .accessibilityValue(Text(verbatim: unit.text(celsius: report.temperature)))
                // The license of the data asks for a link wherever they are displayed.
                Link(destination: OpenMeteoClient.websiteURL) {
                    Text(verbatim: "Open-Meteo")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .monospacedDigit()
        }
    }

    private func range(_ symbol: String, _ value: Double) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text(verbatim: unit.text(celsius: value))
        }
    }
}
