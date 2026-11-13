import SwiftUI
import WidgetKit

// Shared with the app through the App Group; keys are written by lib/widget_sync.dart.
private let appGroupId = "group.dev.yarinlevi.dropit"

struct DropItEntry: TimelineEntry {
    let date: Date
    let signedIn: Bool
    let consumed: Int
    let goal: Int
    let fastEnabled: Bool
    let fastRunning: Bool
    let fastEndsAt: Date?
    let fastStartHour: Int
    let fastEndHour: Int
    let rtl: Bool
    let lblCalories: String
    let lblKcalLeft: String
    let lblKcalOver: String
    let lblFastTitle: String
    let lblFastLeft: String
    let lblFastDone: String
    let lblFastOff: String
    let lblFastWindow: String
    let lblSignedOut: String

    static func load(at date: Date = Date()) -> DropItEntry {
        let d = UserDefaults(suiteName: appGroupId)
        let endsRaw = d?.string(forKey: "fastEndsAt") ?? ""
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let ends = iso.date(from: endsRaw) ?? plain.date(from: endsRaw)
        func s(_ key: String, _ fallback: String) -> String {
            let v = d?.string(forKey: key) ?? ""
            return v.isEmpty ? fallback : v
        }
        return DropItEntry(
            date: date,
            signedIn: d?.bool(forKey: "signedIn") ?? false,
            consumed: d?.integer(forKey: "consumed") ?? 0,
            goal: d?.integer(forKey: "goal") ?? 0,
            fastEnabled: d?.bool(forKey: "fastEnabled") ?? false,
            fastRunning: d?.bool(forKey: "fastRunning") ?? false,
            fastEndsAt: ends,
            fastStartHour: d?.object(forKey: "fastStartHour") as? Int ?? -1,
            fastEndHour: d?.object(forKey: "fastEndHour") as? Int ?? -1,
            rtl: d?.bool(forKey: "rtl") ?? false,
            lblCalories: s("lblCalories", "Calories"),
            lblKcalLeft: s("lblKcalLeft", "kcal left"),
            lblKcalOver: s("lblKcalOver", "kcal over"),
            lblFastTitle: s("lblFastTitle", "Fasting"),
            lblFastLeft: s("lblFastLeft", "left"),
            lblFastDone: s("lblFastDone", "Fast complete"),
            lblFastOff: s("lblFastOff", "Fasting off"),
            lblFastWindow: s("lblFastWindow", "Fasting window"),
            lblSignedOut: s("lblSignedOut", "Open Drop It to sign in")
        )
    }
}

struct DropItProvider: TimelineProvider {
    func placeholder(in context: Context) -> DropItEntry { DropItEntry.load() }

    func getSnapshot(in context: Context, completion: @escaping (DropItEntry) -> Void) {
        completion(DropItEntry.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DropItEntry>) -> Void) {
        let entry = DropItEntry.load()
        // Refresh when the fast ends, otherwise let the app push updates (hourly fallback).
        var next = Date().addingTimeInterval(60 * 60)
        if let ends = entry.fastEndsAt, entry.fastRunning, ends > Date(), ends < next {
            next = ends
        }
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct DropItWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: DropItEntry

    private var remaining: Int { entry.goal - entry.consumed }
    private var over: Bool { entry.consumed > entry.goal && entry.goal > 0 }
    private var progress: Double {
        entry.goal > 0 ? min(Double(entry.consumed) / Double(entry.goal), 1) : 0
    }

    private func hourText(_ hour: Int) -> String {
        String(format: "%02d:00", hour % 24)
    }

    var body: some View {
        Group {
            if !entry.signedIn {
                Text(entry.lblSignedOut)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if family == .systemMedium {
                HStack(alignment: .center, spacing: 16) {
                    calories
                    Divider()
                    fasting
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    calories
                    fasting
                }
            }
        }
        .environment(\.layoutDirection, entry.rtl ? .rightToLeft : .leftToRight)
        .widgetBackground()
    }

    private var calories: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.lblCalories)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("\(entry.consumed)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(Color(.systemOrange))
                + Text(" / \(entry.goal)")
                .font(.footnote)
                .foregroundColor(Color(.secondaryLabel))
            ProgressView(value: progress)
                .tint(over ? Color(.systemRed) : Color(.systemOrange))
            Text("\(abs(remaining)) \(over ? entry.lblKcalOver : entry.lblKcalLeft)")
                .font(.caption2)
                .foregroundStyle(over ? Color(.systemRed) : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var fasting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.lblFastTitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            if !entry.fastEnabled {
                Text(entry.lblFastOff)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if entry.fastRunning, let ends = entry.fastEndsAt {
                if ends > Date() {
                    Text(timerInterval: Date()...ends, countsDown: true)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(.systemBlue))
                    Text(entry.lblFastLeft)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(entry.lblFastDone)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(.systemGreen))
                }
            } else {
                Text(entry.lblFastWindow)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if entry.fastStartHour >= 0 && entry.fastEndHour >= 0 {
                    Text("\(hourText(entry.fastStartHour)) – \(hourText(entry.fastEndHour))")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) { Color(.secondarySystemGroupedBackground) }
        } else {
            padding().background(Color(.secondarySystemGroupedBackground))
        }
    }
}

struct DropItWidget: Widget {
    let kind = "DropItWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DropItProvider()) { entry in
            DropItWidgetView(entry: entry)
        }
        .configurationDisplayName("Drop It")
        .description("Today's calories and your fasting timer.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct DropItWidgetBundle: WidgetBundle {
    var body: some Widget { DropItWidget() }
}
