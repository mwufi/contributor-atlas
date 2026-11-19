import SwiftUI
import Charts
import AtlasCore

struct CalendarHeatmap: View {
    let data: Analytics
    @Binding var year: Int
    let years: [Int]
    let selected: Day?
    let select: (Day) -> Void
    @State private var hovered: Day?
    private var first: Day { Day(year: year, month: 1, day: 1) }
    private var start: Day { first.adding(-first.weekday) }
    private var count: Int { (Day(year: year, month: 12, day: 31).date.timeIntervalSince(start.date) / 86400).rounded(.down).intValue + 1 }
    private var weeks: Int { (count + 6) / 7 }
    private var yearCounts: [Day: Int] { data.daily.filter { $0.key.year == year } }
    private var maximum: Int { max(1, yearCounts.values.max() ?? 1) }
    private func fill(_ day: Day) -> Color {
        guard day.year == year, day >= data.start, day <= data.end else { return Color.primary.opacity(0.025) }
        let n = data.daily[day, default: 0]
        return n == 0 ? Color.primary.opacity(0.065) : Color.atlasGreen.opacity(0.22 + 0.78 * sqrt(Double(n) / Double(maximum)))
    }
    var body: some View {
        Panel(title: "Contribution calendar", detail: "Click a day to explore its commits") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(compact(yearCounts.values.reduce(0, +))) commits · \(yearCounts.count) active days in \(String(year))").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Picker("Year", selection: $year) { ForEach(years, id: \.self) { Text(String($0)).tag($0) } }.labelsHidden().frame(width: 90)
                }
                GeometryReader { geo in
                    let gap: CGFloat = 3
                    let size = min(17, (geo.size.width - 34 - CGFloat(weeks - 1) * gap) / CGFloat(weeks))
                    HStack(alignment: .top, spacing: 7) {
                        VStack(spacing: gap) {
                            Color.clear.frame(height: 16)
                            ForEach(0..<7) { i in Text(i % 2 == 0 ? weekdays[i] : "").font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 27, height: size) }
                        }.frame(width: 27)
                        HStack(alignment: .top, spacing: gap) {
                            ForEach(0..<weeks, id: \.self) { week in
                                VStack(spacing: gap) {
                                    let day = start.adding(week * 7)
                                    Text(day.day <= 7 && day.year == year ? monthName(day.month) : "")
                                        .font(.system(size: 9)).foregroundStyle(.secondary).fixedSize().frame(width: size, height: 16, alignment: .leading)
                                    ForEach(0..<7) { weekday in
                                        let day = start.adding(week * 7 + weekday)
                                        Button { select(day) } label: {
                                            RoundedRectangle(cornerRadius: 2.5).fill(fill(day))
                                                .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(selected == day ? Color.atlasAccent : .clear, lineWidth: 2))
                                                .frame(width: size, height: size)
                                        }.buttonStyle(.plain)
                                            .disabled(day.year != year || day < data.start || day > data.end)
                                            .help("\(day.id): \(data.daily[day, default: 0]) commits")
                                            .accessibilityLabel("\(day.id), \(data.daily[day, default: 0]) commits")
                                            .onHover { hovered = $0 ? day : nil }
                                    }
                                }
                            }
                        }
                    }
                }.frame(height: 160)
                HStack(spacing: 5) {
                    Text(hovered.map { "\($0.id) · \(data.daily[$0, default: 0]) commits" } ?? "\(data.start.id) – \(data.end.id)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Text("Less").font(.system(size: 10)).foregroundStyle(.secondary)
                    ForEach(0..<5) { i in RoundedRectangle(cornerRadius: 2).fill(i == 0 ? Color.primary.opacity(0.065) : Color.atlasGreen.opacity(Double(i) / 4)).frame(width: 11, height: 11) }
                    Text("More").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }
    func monthName(_ month: Int) -> String { ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][month - 1] }
}
private extension Double { var intValue: Int { Int(self) } }

struct DailyChart: View {
    let data: Analytics
    var compactMode = false
    private var days: [Day] {
        // Long repositories use weekly bins to keep the timeline responsive.
        stride(from: 0, through: data.calendarDays - 1, by: data.calendarDays > 730 ? 7 : 1).map { data.start.adding($0) }
    }
    var body: some View {
        Chart(days) { day in
            let n = data.calendarDays > 730 ? (0..<7).reduce(0) { $0 + data.daily[day.adding($1), default: 0] } : data.daily[day, default: 0]
            AreaMark(x: .value("Date", day.date), y: .value("Commits", n))
                .foregroundStyle(LinearGradient(colors: [.atlasAccent.opacity(0.18), .atlasAccent.opacity(0.01)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Date", day.date), y: .value("Commits", n))
                .foregroundStyle(Color.atlasAccent).lineStyle(StrokeStyle(lineWidth: compactMode ? 1.4 : 1.8))
        }
        .chartXScale(domain: data.start.date...max(data.start.adding(1).date, data.end.date))
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: compactMode ? 3 : 6)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: false) } }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in AxisGridLine().foregroundStyle(Color.atlasLine); AxisValueLabel() } }
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        .frame(height: compactMode ? 60 : 160)
        .accessibilityLabel("\(data.calendarDays > 730 ? "Weekly" : "Daily") commit timeline, \(data.commits.count) commits")
    }
}

struct HourChart: View {
    let hours: [Int]
    let selected: Int?
    let select: (Int) -> Void
    var body: some View {
        GeometryReader { geo in
            let maxCount = max(1, hours.max() ?? 1)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<24) { hour in
                    Button { select(hour) } label: {
                        VStack(spacing: 6) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(selected == hour ? Color.atlasAccent : Color.atlasAccent.opacity(hour == hours.indices.max(by: { hours[$0] < hours[$1] }) ? 0.85 : 0.35))
                                .frame(height: max(2, (geo.size.height - 24) * CGFloat(hours[hour]) / CGFloat(maxCount)))
                            Text(hour % 6 == 0 || hour == 23 ? String(format: "%02d", hour) : " ").font(.system(size: 9)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).help("\(hourLabel(hour)) · \(hours[hour]) commits")
                        .accessibilityLabel("\(hourLabel(hour)), \(hours[hour]) commits; filter hour")
                }
            }
        }.frame(height: 160)
    }
}

struct WeekHourHeatmap: View {
    let values: [Int]
    let select: (Int, Int) -> Void
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Color.clear.frame(width: 30, height: 14)
                ForEach(0..<24) { h in Text(h % 3 == 0 ? hourLabel(h) : "").font(.system(size: 9)).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
            }
            ForEach(0..<7) { day in
                HStack(spacing: 4) {
                    Text(weekdays[day]).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                    ForEach(0..<24) { h in
                        let n = values[day * 24 + h]
                        Button { select(day, h) } label: {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(n == 0 ? Color.primary.opacity(0.05) : Color.atlasAccent.opacity(0.15 + 0.85 * sqrt(Double(n) / Double(max(1, values.max() ?? 1)))))
                                .frame(maxWidth: .infinity).frame(height: 21)
                        }.buttonStyle(.plain).help("\(weekdays[day]) \(hourLabel(h)): \(n) commits")
                            .accessibilityLabel("\(weekdays[day]) \(hourLabel(h)), \(n) commits; filter")
                    }
                }
            }
        }
    }
}

struct Sparkline: View {
    let daily: [Day: Int]
    let start: Day
    let end: Day
    var body: some View {
        let span = max(1, Int(end.date.timeIntervalSince(start.date) / 86400) + 1)
        let step = max(1, span / 40)
        let days = stride(from: 0, to: span, by: step).map { start.adding($0) }
        Chart(days) { day in
            BarMark(x: .value("Day", day.date), y: .value("Commits", (0..<step).reduce(0) { $0 + daily[day.adding($1), default: 0] }))
                .foregroundStyle(Color.atlasAccent.opacity(0.45)).cornerRadius(1)
        }.chartXAxis(.hidden).chartYAxis(.hidden).frame(width: 130, height: 30)
    }
}
