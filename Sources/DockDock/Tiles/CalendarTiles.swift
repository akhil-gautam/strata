import AppKit
import AVFoundation
import Contacts
import CoreAudio
import EventKit
import SwiftUI

/// Calendar, Reminders, Quick Contacts, Mail and Notes tiles.
@MainActor
enum CalendarTiles {
    static let specs: [TileSpec] = calendar + reminders + contacts + mail + notes

    private static let openCalendar = TileMenuItem.action("Open Calendar") { CalendarApp.calendar.open() }
    private static let openReminders = TileMenuItem.action("Open Reminders") { CalendarApp.reminders.open() }
    private static let meetingMenu: [TileMenuItem] = [
        .action("Join Meeting") { CalendarSchedule.join(CalendarSchedule.nextMeeting(now: Date())) },
        openCalendar
    ]
    private static let mailMenu: [TileMenuItem] = [
        .action("New Message") { CalendarMail.compose() },
        .action("Open Mail") { CalendarApp.mail.open() }
    ]

    private static let calendar: [TileSpec] = [
        TileSpec(id: "calendar-today", title: "Today", category: .calendar, menu: [openCalendar]) {
            AnyView(CalendarTodayTile())
        },
        TileSpec(id: "next-event", title: "Next Event", category: .calendar, menu: [openCalendar]) {
            AnyView(CalendarNextEventTile())
        },
        TileSpec(id: "next-3-events", title: "Next 3 Events", category: .calendar, menu: [openCalendar]) {
            AnyView(CalendarNextThreeTile())
        },
        TileSpec(id: "today-agenda", title: "Today Agenda", category: .calendar, menu: [openCalendar]) {
            AnyView(CalendarTodayAgendaTile())
        },
        TileSpec(id: "week", title: "Week", category: .calendar, menu: [openCalendar]) {
            AnyView(CalendarWeekTile())
        },
        TileSpec(id: "7-days", title: "7 Days", category: .calendar, menu: [openCalendar]) {
            AnyView(CalendarSevenDaysTile())
        },
        TileSpec(id: "month-progress", title: "Month Progress", category: .calendar) {
            AnyView(CalendarDotProgressTile(span: .month))
        },
        TileSpec(id: "day-progress", title: "Day Progress", category: .calendar) {
            AnyView(CalendarDotProgressTile(span: .day))
        },
        TileSpec(id: "year-progress", title: "Year Progress", category: .calendar) {
            AnyView(CalendarDotProgressTile(span: .year))
        },
        TileSpec(id: "next-meeting", title: "Next Meeting", category: .calendar, menu: meetingMenu) {
            AnyView(CalendarNextMeetingTile())
        },
        TileSpec(id: "meeting-center", title: "Meeting Center", category: .calendar, menu: meetingMenu) {
            AnyView(CalendarMeetingCenterTile())
        }
    ]

    private static let reminders: [TileSpec] = [
        TileSpec(
            id: "next-reminder",
            title: "Next Reminder",
            category: .reminders,
            menu: [
                .action("Mark as Completed") {
                    if let next = CalendarReminderSchedule.next() {
                        RemindersInfo.shared.complete(id: next.id)
                    }
                },
                openReminders
            ]
        ) {
            AnyView(CalendarNextReminderTile())
        },
        TileSpec(id: "due-today", title: "Due Today", category: .reminders, menu: [openReminders]) {
            AnyView(CalendarDueTodayTile())
        },
        TileSpec(id: "reminders-agenda", title: "Reminders Agenda", category: .reminders, menu: [openReminders]) {
            AnyView(CalendarRemindersAgendaTile())
        }
    ]

    private static let contacts: [TileSpec] = [
        TileSpec(
            id: "quick-contacts",
            title: "Quick Contacts",
            category: .contacts,
            menu: [.customize("Choose Contacts…")],
            settings: TileSettings(
                symbol: "person.2.fill",
                badge: { "\(CalendarContactsStore.shared.people.count)" },
                content: { AnyView(CalendarContactsPicker()) }
            )
        ) {
            AnyView(CalendarQuickContactsTile())
        }
    ]

    private static let mail: [TileSpec] = [
        TileSpec(id: "mail-unread", title: "Mail Unread", category: .mail, menu: mailMenu) {
            AnyView(CalendarMailUnreadTile())
        },
        TileSpec(id: "latest-mail", title: "Latest Mail", category: .mail, menu: mailMenu) {
            AnyView(CalendarLatestMailTile())
        }
    ]

    private static let notes: [TileSpec] = [
        TileSpec(
            id: "bookmarks",
            title: "Bookmarks",
            category: .notes,
            menu: [.customize("Edit Bookmarks…")],
            settings: TileSettings(
                symbol: "bookmark.fill",
                badge: { "\(BookmarkStore.shared.bookmarks.count)" },
                content: { AnyView(CalendarBookmarksEditor()) }
            )
        ) {
            AnyView(CalendarBookmarksTile())
        },
        TileSpec(
            id: "notes",
            title: "Notes",
            category: .notes,
            menu: [.customize("Edit Note…")],
            settings: TileSettings(symbol: "note.text", badge: nil, content: { AnyView(CalendarNoteEditor()) })
        ) {
            AnyView(CalendarNotesTile())
        }
    ]
}

// MARK: - Shared helpers

private enum CalendarApp: String {
    case calendar = "com.apple.iCal"
    case reminders = "com.apple.reminders"
    case mail = "com.apple.mail"

    @MainActor
    func open() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// The Privacy & Security panes the tiles send the user to.
private enum CalendarPrivacyPane: String {
    case calendars = "Privacy_Calendars"
    case reminders = "Privacy_Reminders"
    case contacts = "Privacy_Contacts"
    case camera = "Privacy_Camera"
    case automation = "Privacy_Automation"

    @MainActor
    func open() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)") else { return }
        NSWorkspace.shared.open(url)
    }
}

private enum CalendarFormat {
    /// "13:30" on a 24-hour clock, "1:30" on a 12-hour one.
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func range(_ start: Date, _ end: Date) -> String {
        "\(time(start)) – \(time(end))"
    }

    /// "Today", "Tomorrow", "Wed" within the week, otherwise "Jun 25".
    static func day(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        if days > 0, days < 7 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "8m", "1h 20m", "2d".
    static func span(_ interval: TimeInterval) -> String {
        let minutes = max(Int((interval / 60).rounded(.up)), 0)
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 24 * 60 {
            let rest = minutes % 60
            return rest == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(rest)m"
        }
        return "\(minutes / (24 * 60))d"
    }
}

private extension Color {
    @MainActor init(calendarColor: CGColor?) {
        if let calendarColor {
            self.init(cgColor: calendarColor)
        } else {
            self = TilePalette.focus
        }
    }
}

private let calendarOrange = Color(red: 1.0, green: 0.58, blue: 0.2)
private let calendarGreen = Color(red: 0.25, green: 0.84, blue: 0.42)

/// Runs `action` when the tile is clicked in the bar. Library previews are
/// inert; the shell owns clicks there.
private struct CalendarBarTap: ViewModifier {
    let action: @MainActor () -> Void
    @Environment(\.tileContext) private var context

    @ViewBuilder
    func body(content: Content) -> some View {
        if context == .bar {
            content
                .contentShape(RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous))
                .onTapGesture { action() }
        } else {
            content
        }
    }
}

private extension View {
    func calendarBarTap(_ action: @escaping @MainActor () -> Void) -> some View {
        modifier(CalendarBarTap(action: action))
    }
}

/// A round button inside a tile; inert in the library.
private struct CalendarCircleButton: View {
    let symbol: String
    var diameter: CGFloat = 26
    var glyph: Color = TilePalette.ink
    var fill: Color = TilePalette.ink.opacity(0.1)
    var ring: Color? = nil
    let action: @MainActor () -> Void
    @Environment(\.tileContext) private var context

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.42, weight: .semibold))
                .foregroundStyle(glyph)
                .frame(width: diameter, height: diameter)
                .background { Circle().fill(fill) }
                .overlay {
                    if let ring {
                        Circle().strokeBorder(ring, lineWidth: 1.6)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(context == .bar)
    }
}

private struct CalendarComposeButton: View {
    let action: @MainActor () -> Void

    var body: some View {
        CalendarCircleButton(
            symbol: "square.and.pencil",
            diameter: 27,
            glyph: TilePalette.ink.opacity(0.88),
            fill: TilePalette.ink.opacity(0.1),
            action: action
        )
    }
}

/// Icon, title and caption: used for permission and empty states.
private struct CalendarNoticeTile: View {
    let width: CGFloat
    let icon: CalendarIconKind
    let title: String
    let caption: String

    var body: some View {
        DockTile(width: width) {
            HStack(spacing: 10) {
                CalendarAppIcon(kind: icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.tileValue(12.5))
                        .foregroundStyle(TilePalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(caption)
                        .font(.tileCaption(9))
                        .foregroundStyle(TilePalette.caption)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - App icons

private enum CalendarIconKind {
    case calendar, reminders, mail, notes, contacts
}

/// Small renditions of the system app icons, drawn to match the video.
private struct CalendarAppIcon: View {
    let kind: CalendarIconKind
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            switch kind {
            case .calendar: calendar
            case .reminders: reminders
            case .mail: mail
            case .notes: notes
            case .contacts: contacts
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
    }

    private var paper: LinearGradient {
        LinearGradient(colors: [Color(white: 0.99), Color(white: 0.9)], startPoint: .top, endPoint: .bottom)
    }

    private var calendar: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.36, blue: 0.36), Color(red: 0.9, green: 0.16, blue: 0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: size * 0.28)
            Canvas { context, canvas in
                let columns = 7, rows = 4
                let pitchX = canvas.width * 0.76 / CGFloat(columns - 1)
                let pitchY = canvas.height * 0.64 / CGFloat(rows - 1)
                let originX = canvas.width * 0.12, originY = canvas.height * 0.17
                let dot = size * 0.05
                for row in 0..<rows {
                    for column in 0..<columns {
                        let isToday = row == 2 && column == 4
                        let diameter = isToday ? dot * 1.9 : dot
                        let rect = CGRect(
                            x: originX + CGFloat(column) * pitchX - diameter / 2,
                            y: originY + CGFloat(row) * pitchY - diameter / 2,
                            width: diameter,
                            height: diameter
                        )
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(isToday ? Color(red: 0.93, green: 0.2, blue: 0.24) : Color(white: 0.3))
                        )
                    }
                }
            }
            .background(paper)
        }
    }

    private var reminders: some View {
        ZStack {
            paper
            VStack(alignment: .leading, spacing: size * 0.1) {
                ForEach(
                    [Color(red: 0.2, green: 0.5, blue: 1.0), Color(red: 1.0, green: 0.27, blue: 0.27), calendarOrange],
                    id: \.self
                ) { tint in
                    HStack(spacing: size * 0.07) {
                        Circle().fill(tint).frame(width: size * 0.12, height: size * 0.12)
                        Capsule().fill(Color(white: 0.78)).frame(width: size * 0.42, height: size * 0.05)
                    }
                }
            }
        }
    }

    private var mail: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.42, green: 0.78, blue: 1.0), Color(red: 0.08, green: 0.42, blue: 0.96)],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: "envelope.fill")
                .font(.system(size: size * 0.48, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.95))
        }
    }

    private var notes: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.87, blue: 0.33), Color(red: 0.98, green: 0.76, blue: 0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: size * 0.3)
            ZStack(alignment: .top) {
                paper
                VStack(spacing: size * 0.13) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle().fill(Color(white: 0.82)).frame(height: max(size * 0.025, 0.6))
                    }
                }
                .padding(.top, size * 0.14)
            }
        }
    }

    private var contacts: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.55), Color(white: 0.38)], startPoint: .top, endPoint: .bottom)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: size * 0.6))
                .foregroundStyle(Color.white.opacity(0.9))
        }
    }
}

// MARK: - Calendar data

@MainActor
private enum CalendarSchedule {
    typealias Event = CalendarInfo.Event

    /// Events still to come or under way today, all-day ones included.
    static func remainingToday(now: Date) -> [Event] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return CalendarInfo.shared.nearbyEvents.filter { $0.start < end && $0.end > now }
    }

    /// Timed events that have not ended yet, soonest first.
    static func upcoming(now: Date) -> [Event] {
        CalendarInfo.shared.nearbyEvents.filter { !$0.isAllDay && $0.end > now }
    }

    /// The next event with a video-call link, else the next timed event.
    static func nextMeeting(now: Date) -> Event? {
        let events = upcoming(now: now)
        return events.first { $0.meetingURL != nil } ?? events.first
    }

    static func hasEvents(on day: Date) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        return CalendarInfo.shared.nearbyEvents.contains { $0.start < end && $0.end > start }
    }

    /// Opens the call link, or Calendar when the event has none.
    static func join(_ event: Event?) {
        if let url = event?.meetingURL {
            NSWorkspace.shared.open(url)
        } else {
            CalendarApp.calendar.open()
        }
    }

    static func provider(of event: Event) -> String {
        guard let host = event.meetingURL?.host?.lowercased() else {
            if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
                return location
            }
            return "No call link"
        }
        let names: [(String, String)] = [
            ("meet.google.com", "Google Meet"), ("zoom", "Zoom"), ("teams.", "Microsoft Teams"),
            ("webex", "Webex"), ("facetime", "FaceTime"), ("whereby", "Whereby"),
            ("jit.si", "Jitsi Meet"), ("chime", "Amazon Chime"), ("around", "Around")
        ]
        return names.first { host.contains($0.0) }?.1 ?? host
    }

    /// "Starts in 8 min", "Ends in 20 min", "Tomorrow · 09:00".
    static func status(of event: Event, now: Date) -> String {
        if event.start <= now {
            return "Ends in \(minutesText(event.end.timeIntervalSince(now)))"
        }
        let until = event.start.timeIntervalSince(now)
        if until < 12 * 3600 || Calendar.current.isDate(event.start, inSameDayAs: now) {
            return "Starts in \(minutesText(until))"
        }
        return "\(CalendarFormat.day(event.start, now: now)) · \(CalendarFormat.time(event.start))"
    }

    private static func minutesText(_ interval: TimeInterval) -> String {
        let minutes = max(Int((interval / 60).rounded(.up)), 0)
        if minutes < 60 { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(rest) min"
    }
}

/// Shows `content` once EventKit access is granted; otherwise an access tile
/// that asks for it (bar) or explains it (library).
private struct CalendarEventKitGate<Content: View>: View {
    let entity: EKEntityType
    let width: CGFloat
    @ViewBuilder var content: () -> Content
    @Environment(\.tileContext) private var context

    private var hasAccess: Bool {
        entity == .event ? CalendarInfo.shared.hasAccess : RemindersInfo.shared.hasAccess
    }

    var body: some View {
        if hasAccess {
            content()
        } else {
            CalendarNoticeTile(
                width: width,
                icon: entity == .event ? .calendar : .reminders,
                title: entity == .event ? "Calendar" : "Reminders",
                caption: "Click to allow access"
            )
            .calendarBarTap { Task { await sync(fromClick: true) } }
            .task { await sync(fromClick: false) }
        }
    }

    private func sync(fromClick: Bool) async {
        switch EKEventStore.authorizationStatus(for: entity) {
        case .fullAccess:
            if entity == .event {
                CalendarInfo.shared.hasAccess = true
                CalendarInfo.shared.refresh()
            } else {
                RemindersInfo.shared.hasAccess = true
                RemindersInfo.shared.refresh()
            }
        case .notDetermined:
            guard context == .bar else { return }
            if entity == .event {
                await CalendarInfo.shared.requestAccess()
            } else {
                await RemindersInfo.shared.requestAccess()
            }
        default:
            if fromClick {
                (entity == .event ? CalendarPrivacyPane.calendars : .reminders).open()
            }
        }
    }
}

private struct CalendarEventDot: View {
    let color: CGColor?
    var diameter: CGFloat = 5

    var body: some View {
        Circle()
            .fill(Color(calendarColor: color))
            .frame(width: diameter, height: diameter)
    }
}

/// "● Team standup        13:30"
private struct CalendarEventRow: View {
    let event: CalendarInfo.Event
    let now: Date
    var titleSize: CGFloat = 10.5

    var body: some View {
        HStack(spacing: 6) {
            CalendarEventDot(color: event.color)
            Text(event.title)
                .font(.tileText(titleSize, weight: .semibold))
                .foregroundStyle(TilePalette.ink.opacity(0.94))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(timeLabel)
                .font(.tileText(9.5, weight: .medium))
                .foregroundStyle(TilePalette.caption)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var timeLabel: String {
        if event.isAllDay { return "All day" }
        let time = CalendarFormat.time(event.start)
        if Calendar.current.isDate(event.start, inSameDayAs: now) || event.start < now { return time }
        return "\(event.start.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
}

// MARK: - Calendar tiles

private struct CalendarTodayTile: View {
    private let width: CGFloat = 200

    var body: some View {
        CalendarEventKitGate(entity: .event, width: width) {
            TimelineView(.everyMinute) { timeline in
                let events = CalendarSchedule.remainingToday(now: timeline.date)
                DockTile(width: width) {
                    HStack(spacing: 10) {
                        CalendarAppIcon(kind: .calendar)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Today")
                                .font(.tileCaption(9.5))
                                .foregroundStyle(TilePalette.caption)
                            if events.isEmpty {
                                Text("No more events")
                                    .font(.tileText(10.5, weight: .semibold))
                                    .foregroundStyle(TilePalette.ink.opacity(0.7))
                            }
                            ForEach(events.prefix(2)) { event in
                                CalendarEventRow(event: event, now: timeline.date)
                            }
                        }
                    }
                }
            }
            .calendarBarTap { CalendarApp.calendar.open() }
        }
    }
}

private struct CalendarNextEventTile: View {
    private let width: CGFloat = 200

    var body: some View {
        CalendarEventKitGate(entity: .event, width: width) {
            TimelineView(.everyMinute) { timeline in
                let now = timeline.date
                let next = CalendarSchedule.upcoming(now: now).first
                DockTile(width: width) {
                    HStack(spacing: 10) {
                        CalendarAppIcon(kind: .calendar)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(next.map { headline($0, now: now) } ?? "No events")
                                .font(.tileValue(14.5))
                                .foregroundStyle(next == nil ? TilePalette.ink : TilePalette.focus)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(next?.title ?? "Your next two weeks are clear")
                                .font(.tileCaption(9.5))
                                .foregroundStyle(TilePalette.caption)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .calendarBarTap { CalendarApp.calendar.open() }
        }
    }

    private func headline(_ event: CalendarInfo.Event, now: Date) -> String {
        if event.start <= now { return "Now · until \(CalendarFormat.time(event.end))" }
        return "\(CalendarFormat.day(event.start, now: now)) · \(CalendarFormat.time(event.start))"
    }
}

private struct CalendarNextThreeTile: View {
    private let width: CGFloat = 176

    var body: some View {
        CalendarEventKitGate(entity: .event, width: width) {
            TimelineView(.everyMinute) { timeline in
                let events = CalendarSchedule.upcoming(now: timeline.date)
                DockTile(width: width) {
                    VStack(alignment: .leading, spacing: 4) {
                        if events.isEmpty {
                            Text("No upcoming events")
                                .font(.tileText(10.5, weight: .semibold))
                                .foregroundStyle(TilePalette.ink.opacity(0.7))
                        }
                        ForEach(events.prefix(3)) { event in
                            CalendarEventRow(event: event, now: timeline.date)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .calendarBarTap { CalendarApp.calendar.open() }
        }
    }
}

/// A rounded box holding a large number over a small caption.
private struct CalendarNumberBox: View {
    let number: String
    let caption: String
    var tint: Color = TilePalette.ink
    var width: CGFloat = 42

    var body: some View {
        VStack(spacing: 0) {
            Text(number)
                .font(.tileValue(22, weight: .bold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.tileCaption(8.5))
                .foregroundStyle(TilePalette.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: width, height: 46)
        .background {
            RoundedRectangle(cornerRadius: TileMetrics.corner * 0.75, style: .continuous)
                .fill(TilePalette.ink.opacity(0.055))
        }
    }
}

/// "+3"
private struct CalendarMoreChip: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.tileText(8.5, weight: .semibold))
            .foregroundStyle(TilePalette.ink.opacity(0.6))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background { Capsule().fill(TilePalette.ink.opacity(0.08)) }
    }
}

private struct CalendarTodayAgendaTile: View {
    private let width: CGFloat = 207

    var body: some View {
        CalendarEventKitGate(entity: .event, width: width) {
            TimelineView(.everyMinute) { timeline in
                let now = timeline.date
                let events = CalendarSchedule.remainingToday(now: now)
                DockTile(width: width, inset: 5) {
                    HStack(spacing: 9) {
                        CalendarNumberBox(
                            number: now.formatted(.dateTime.day()),
                            caption: now.formatted(.dateTime.month(.abbreviated))
                        )
                        VStack(alignment: .leading, spacing: 0) {
                            if events.isEmpty {
                                Text("No more events")
                                    .font(.tileText(10.5, weight: .semibold))
                                    .foregroundStyle(TilePalette.ink.opacity(0.75))
                                Text("Enjoy the rest of today")
                                    .font(.tileCaption(9.5))
                                    .foregroundStyle(TilePalette.caption)
                            }
                            ForEach(events.prefix(2)) { event in
                                Text(event.title)
                                    .font(.tileText(10.5, weight: .semibold))
                                    .foregroundStyle(Color(calendarColor: event.color))
                                    .lineLimit(1)
                                Text(event.isAllDay ? "All day" : CalendarFormat.range(event.start, event.end))
                                    .font(.tileText(9.5, weight: .medium))
                                    .foregroundStyle(TilePalette.caption)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .padding(.bottom, 2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if events.count > 2 {
                            CalendarMoreChip(count: events.count - 2)
                                .padding(.trailing, 3)
                                .padding(.bottom, 1)
                        }
                    }
                }
            }
            .calendarBarTap { CalendarApp.calendar.open() }
        }
    }
}

private struct CalendarWeekTile: View {
    private let width: CGFloat = 189

    var body: some View {
        CalendarEventKitGate(entity: .event, width: width) {
            TimelineView(.everyMinute) { timeline in
                let now = timeline.date
                let calendar = Calendar.current
                let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
                let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
                DockTile(width: width, inset: 4) {
                    HStack(spacing: 0) {
                        ForEach(days, id: \.self) { day in
                            column(day, isToday: calendar.isDate(day, inSameDayAs: now))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .calendarBarTap { CalendarApp.calendar.open() }
        }
    }

    private func column(_ day: Date, isToday: Bool) -> some View {
        let calendar = Calendar.current
        let letter = calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: day) - 1]
        return VStack(spacing: 3) {
            Text(letter)
                .font(.tileText(8, weight: .semibold))
                .foregroundStyle(isToday ? TilePalette.focus : TilePalette.caption)
            Text("\(calendar.component(.day, from: day))")
                .font(.tileText(12.5, weight: .semibold))
                .foregroundStyle(isToday ? TilePalette.onFocus : TilePalette.ink)
                .monospacedDigit()
                .frame(width: 20, height: 20)
                .background {
                    if isToday { Circle().fill(TilePalette.focus) }
                }
            Circle()
                .fill(CalendarSchedule.hasEvents(on: day) ? TilePalette.focus : .clear)
                .frame(width: 3.5, height: 3.5)
        }
    }
}

private struct CalendarSevenDaysTile: View {
    private let width: CGFloat = 195

    var body: some View {
        CalendarEventKitGate(entity: .event, width: width) {
            TimelineView(.everyMinute) { timeline in
                let now = timeline.date
                let calendar = Calendar.current
                let days = (0..<7).compactMap {
                    calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: now))
                }
                DockTile(width: width, inset: 6) {
                    VStack(spacing: 3) {
                        HStack(spacing: 3) {
                            Text(now.formatted(.dateTime.month(.wide)))
                                .font(.tileText(9, weight: .semibold))
                                .foregroundStyle(TilePalette.ink.opacity(0.9))
                            Spacer(minLength: 0)
                            weather
                        }
                        .padding(.horizontal, 2)
                        HStack(spacing: 1.5) {
                            ForEach(days, id: \.self) { day in
                                cell(day, isToday: calendar.isDate(day, inSameDayAs: now))
                            }
                        }
                    }
                }
            }
            .calendarBarTap { CalendarApp.calendar.open() }
        }
    }

    @ViewBuilder
    private var weather: some View {
        let weather = WeatherInfo.shared
        if let temperature = weather.temperature {
            HStack(spacing: 2) {
                Image(systemName: weather.symbol + ".fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 9))
                Text("\(Int(temperature.rounded()))°")
                    .font(.tileText(9.5, weight: .semibold))
                    .foregroundStyle(TilePalette.ink.opacity(0.9))
            }
        }
    }

    private func cell(_ day: Date, isToday: Bool) -> some View {
        VStack(spacing: 0) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.tileText(8, weight: .semibold))
                .foregroundStyle(isToday ? TilePalette.onFocus : TilePalette.caption)
            Text(day.formatted(.dateTime.day()))
                .font(.tileText(13.5, weight: .semibold))
                .foregroundStyle(isToday ? TilePalette.onFocus : TilePalette.ink)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background {
            RoundedRectangle(cornerRadius: TileMetrics.corner * 7 / 12, style: .continuous)
                .fill(isToday ? TilePalette.focus : TilePalette.ink.opacity(0.045))
        }
    }
}

// MARK: Progress

private enum CalendarProgressSpan {
    case month, day, year
}

/// A grid of dots, one per day/hour/week, with a label and a percentage.
private struct CalendarDotProgressTile: View {
    let span: CalendarProgressSpan

    private var width: CGFloat {
        switch span {
        case .month, .day: 102
        case .year: 116
        }
    }

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let model = progress(at: timeline.date)
            let ink = TilePalette.ink
            DockTile(width: width, inset: 7) {
                VStack(spacing: 3) {
                    Canvas { context, size in
                        draw(model, ink: ink, in: context, size: size)
                    }
                    HStack(spacing: 2) {
                        Text(model.label)
                            .font(.tileCaption(8.5))
                            .foregroundStyle(TilePalette.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        Text("\(model.percent)%")
                            .font(.tileText(9.5, weight: .bold))
                            .foregroundStyle(TilePalette.ink)
                            .monospacedDigit()
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private struct Model {
        let columns: Int
        let rows: Int
        let total: Int
        let filled: Int
        let percent: Int
        let label: String
    }

    private func progress(at now: Date) -> Model {
        let calendar = Calendar.current
        switch span {
        case .month:
            let days = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
            let day = calendar.component(.day, from: now)
            return Model(
                columns: Int((Double(days) / 3).rounded(.up)),
                rows: 3,
                total: days,
                filled: day,
                percent: Int((Double(day) / Double(days) * 100).rounded()),
                label: now.formatted(.dateTime.month(.wide).year())
            )
        case .day:
            let components = calendar.dateComponents([.hour, .minute], from: now)
            let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            return Model(
                columns: 8,
                rows: 3,
                total: 24,
                filled: (components.hour ?? 0) + 1,
                percent: Int((Double(minutes) / 1440 * 100).rounded()),
                label: now.formatted(.dateTime.month(.wide).day())
            )
        case .year:
            let week = min(max(calendar.component(.weekOfYear, from: now), 1), 52)
            return Model(
                columns: 13,
                rows: 4,
                total: 52,
                filled: week,
                percent: Int((Double(week) / 52 * 100).rounded()),
                label: now.formatted(.dateTime.year())
            )
        }
    }

    private func draw(_ model: Model, ink: Color, in context: GraphicsContext, size: CGSize) {
        let pitch = min(size.width / CGFloat(model.columns), size.height / CGFloat(model.rows))
        let diameter = pitch * 0.8
        let gridWidth = pitch * CGFloat(model.columns - 1) + diameter
        let gridHeight = pitch * CGFloat(model.rows - 1) + diameter
        let originX = (size.width - gridWidth) / 2
        let originY = (size.height - gridHeight) / 2
        for index in 0..<model.total {
            let rect = CGRect(
                x: originX + CGFloat(index % model.columns) * pitch,
                y: originY + CGFloat(index / model.columns) * pitch,
                width: diameter,
                height: diameter
            )
            let color = index < model.filled ? ink.opacity(0.92) : ink.opacity(0.13)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }
}

// MARK: Meetings

private struct CalendarNextMeetingTile: View {
    private let width: CGFloat = 200

    var body: some View {
        CalendarEventKitGate(entity: .event, width: width) {
            TimelineView(.everyMinute) { timeline in
                let now = timeline.date
                let meeting = CalendarSchedule.nextMeeting(now: now)
                DockTile(width: width) {
                    HStack(spacing: 10) {
                        CalendarAppIcon(kind: .calendar)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meeting?.title ?? "No meetings")
                                .font(.tileText(12.5, weight: .semibold))
                                .foregroundStyle(TilePalette.ink)
                                .lineLimit(1)
                            Text(meeting.map { detail($0, now: now) } ?? "Nothing in the next two weeks")
                                .font(.tileText(9.5, weight: .medium))
                                .foregroundStyle(TilePalette.caption)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if let meeting {
                            if meeting.meetingURL != nil {
                                CalendarCircleButton(symbol: "video.fill", glyph: TilePalette.onFocus, fill: TilePalette.focus) {
                                    CalendarSchedule.join(meeting)
                                }
                            } else {
                                CalendarCircleButton(symbol: "calendar", fill: TilePalette.ink.opacity(0.12)) {
                                    CalendarApp.calendar.open()
                                }
                            }
                        }
                    }
                }
            }
            .calendarBarTap { CalendarApp.calendar.open() }
        }
    }

    /// "10:30 – 11:15  8m"
    private func detail(_ event: CalendarInfo.Event, now: Date) -> String {
        var text = CalendarFormat.range(event.start, event.end)
        if !Calendar.current.isDate(event.start, inSameDayAs: now) {
            text = "\(CalendarFormat.day(event.start, now: now)) \(text)"
        }
        let until = event.start <= now ? "now" : CalendarFormat.span(event.start.timeIntervalSince(now))
        return "\(text)  \(until)"
    }
}

private struct CalendarMeetingCenterTile: View {
    private let width: CGFloat = 252
    @State private var micMuted = CalendarMicrophone.isMuted()
    @State private var showsCamera = false

    var body: some View {
        CalendarEventKitGate(entity: .event, width: width) {
            TimelineView(.everyMinute) { timeline in
                let now = timeline.date
                let meeting = CalendarSchedule.nextMeeting(now: now)
                DockTile(width: width) {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(meeting?.title ?? "No meetings")
                                .font(.tileText(11.5, weight: .bold))
                                .foregroundStyle(TilePalette.ink)
                                .lineLimit(1)
                            if let meeting {
                                Text(CalendarSchedule.provider(of: meeting))
                                    .font(.tileCaption(8.5))
                                    .foregroundStyle(TilePalette.caption)
                                    .lineLimit(1)
                                Text(CalendarFormat.range(meeting.start, meeting.end))
                                    .font(.tileCaption(8.5))
                                    .foregroundStyle(TilePalette.caption)
                                    .monospacedDigit()
                                Text(CalendarSchedule.status(of: meeting, now: now))
                                    .font(.tileText(9.5, weight: .semibold))
                                    .foregroundStyle(TilePalette.focus)
                                    .lineLimit(1)
                            } else {
                                Text("Nothing in the next two weeks")
                                    .font(.tileCaption(9))
                                    .foregroundStyle(TilePalette.caption)
                            }
                        }
                        Spacer(minLength: 4)
                        controls(meeting)
                    }
                }
                .task(id: now) { micMuted = CalendarMicrophone.isMuted() }
            }
            .calendarBarTap { CalendarApp.calendar.open() }
        }
    }

    private func controls(_ meeting: CalendarInfo.Event?) -> some View {
        HStack(spacing: 6) {
            CalendarCircleButton(
                symbol: micMuted ? "mic.slash.fill" : "mic.fill",
                glyph: micMuted ? TilePalette.ink.opacity(0.55) : calendarGreen,
                fill: micMuted ? TilePalette.ink.opacity(0.08) : calendarGreen.opacity(0.14),
                ring: micMuted ? nil : calendarGreen
            ) {
                CalendarMicrophone.setMuted(!micMuted)
                micMuted = CalendarMicrophone.isMuted()
            }
            .help(micMuted ? "Unmute microphone" : "Mute microphone")
            CalendarCircleButton(
                symbol: showsCamera ? "video.fill" : "video.slash.fill",
                glyph: showsCamera ? TilePalette.ink : TilePalette.ink.opacity(0.55),
                fill: TilePalette.ink.opacity(showsCamera ? 0.18 : 0.08)
            ) {
                NSApp.activate()
                showsCamera.toggle()
            }
            .help("Check your camera")
            .popover(isPresented: $showsCamera, arrowEdge: .top) {
                CalendarCameraCheck()
                    .preferredColorScheme(AppearanceStore.shared.theme.appearance)
            }
            if let meeting {
                CalendarCircleButton(
                    symbol: meeting.meetingURL == nil ? "calendar" : "video.fill",
                    glyph: meeting.meetingURL == nil ? TilePalette.ink : TilePalette.onFocus,
                    fill: meeting.meetingURL == nil ? TilePalette.ink.opacity(0.12) : TilePalette.focus
                ) {
                    CalendarSchedule.join(meeting)
                }
                .help(meeting.meetingURL == nil ? "Open in Calendar" : "Join")
            }
        }
    }
}

/// The default input device's mute, through Core Audio. Devices without a
/// mute control are silenced by taking their input volume to zero.
private enum CalendarMicrophone {
    private static let savedVolumeKey = "calendarMicrophoneVolume"

    static func isMuted() -> Bool {
        guard let device = defaultInput() else { return true }
        if let mute = read(UInt32.self, kAudioDevicePropertyMute, device) {
            if mute != 0 { return true }
        }
        if let volume = read(Float32.self, kAudioDevicePropertyVolumeScalar, device) {
            return volume <= 0.001
        }
        return false
    }

    static func setMuted(_ muted: Bool) {
        guard let device = defaultInput() else { return }
        if write(UInt32(muted ? 1 : 0), kAudioDevicePropertyMute, device) {
            if !muted, let volume = read(Float32.self, kAudioDevicePropertyVolumeScalar, device), volume <= 0.001 {
                restoreVolume(device)
            }
            return
        }
        if muted {
            if let volume = read(Float32.self, kAudioDevicePropertyVolumeScalar, device), volume > 0.001 {
                UserDefaults.standard.set(Double(volume), forKey: savedVolumeKey)
            }
            _ = write(Float32(0), kAudioDevicePropertyVolumeScalar, device)
        } else {
            restoreVolume(device)
        }
    }

    private static func restoreVolume(_ device: AudioDeviceID) {
        let saved = UserDefaults.standard.double(forKey: savedVolumeKey)
        _ = write(Float32(saved > 0.001 ? saved : 0.75), kAudioDevicePropertyVolumeScalar, device)
    }

    private static func defaultInput() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != 0 ? device : nil
    }

    /// The main element when it has the control, else the first channels.
    private static func addresses(_ selector: AudioObjectPropertySelector, _ device: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        [kAudioObjectPropertyElementMain, 1, 2].compactMap { element in
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: element
            )
            return AudioObjectHasProperty(device, &address) ? address : nil
        }
    }

    private static func read(_: UInt32.Type, _ selector: AudioObjectPropertySelector, _ device: AudioDeviceID) -> UInt32? {
        guard var address = addresses(selector, device).first else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func read(_: Float32.Type, _ selector: AudioObjectPropertySelector, _ device: AudioDeviceID) -> Float32? {
        guard var address = addresses(selector, device).first else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    /// Writes every element that carries the control; true when one took it.
    private static func write<Value: BitwiseCopyable>(_ value: Value, _ selector: AudioObjectPropertySelector, _ device: AudioDeviceID) -> Bool {
        var wrote = false
        for var address in addresses(selector, device) {
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { continue }
            let status = withUnsafeBytes(of: value) { bytes in
                AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(bytes.count), bytes.baseAddress!)
            }
            if status == noErr {
                wrote = true
            }
        }
        return wrote
    }
}

/// A live camera preview to check yourself before joining.
private struct CalendarCameraCheck: View {
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Group {
            switch status {
            case .authorized:
                if AVCaptureDevice.default(for: .video) != nil {
                    CalendarCameraPreview()
                        .frame(width: 240, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    message("No camera found")
                }
            case .notDetermined:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 240, height: 150)
                    .onAppear {
                        AVCaptureDevice.requestAccess(for: .video) { _ in
                            Task { @MainActor in
                                status = AVCaptureDevice.authorizationStatus(for: .video)
                            }
                        }
                    }
            default:
                VStack(spacing: 8) {
                    message("Camera access is off")
                    Button("Open Privacy Settings") { CalendarPrivacyPane.camera.open() }
                        .controlSize(.small)
                }
                .frame(width: 240, height: 150)
            }
        }
        .padding(8)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.tileText(11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 240)
    }
}

private struct CalendarCameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> CalendarCameraView {
        CalendarCameraView()
    }

    func updateNSView(_ nsView: CalendarCameraView, context: Context) {}

    static func dismantleNSView(_ nsView: CalendarCameraView, coordinator: ()) {
        nsView.stop()
    }
}

private final class CalendarCameraView: NSView {
    private let session: AVCaptureSession
    private let preview: AVCaptureVideoPreviewLayer

    init() {
        let session = AVCaptureSession()
        self.session = session
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)
        let box = UncheckedBox(value: session)
        DispatchQueue.global(qos: .userInitiated).async { box.value.startRunning() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        preview.frame = bounds
    }

    func stop() {
        let box = UncheckedBox(value: session)
        DispatchQueue.global(qos: .userInitiated).async { box.value.stopRunning() }
    }
}

// MARK: - Reminders

@MainActor
private enum CalendarReminderSchedule {
    typealias Reminder = RemindersInfo.Reminder

    static func next() -> Reminder? {
        RemindersInfo.shared.reminders.first
    }

    /// Reminders due by the end of today, overdue ones included.
    static func dueToday(now: Date) -> [Reminder] {
        let calendar = Calendar.current
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return [] }
        return RemindersInfo.shared.reminders.filter { ($0.dueDate ?? .distantFuture) < end }
    }

    static func isOverdue(_ reminder: Reminder, now: Date) -> Bool {
        guard let due = reminder.dueDate else { return false }
        return reminder.hasDueTime ? due < now : due < Calendar.current.startOfDay(for: now)
    }

    /// "14:26", "Overdue", "Today".
    static func shortDue(_ reminder: Reminder, now: Date) -> String {
        guard let due = reminder.dueDate else { return "" }
        if isOverdue(reminder, now: now) { return "Overdue" }
        if reminder.hasDueTime, Calendar.current.isDate(due, inSameDayAs: now) { return CalendarFormat.time(due) }
        return CalendarFormat.day(due, now: now)
    }

    /// "Today · 14:26", "Overdue · Jun 20", "No due date".
    static func longDue(_ reminder: Reminder, now: Date) -> String {
        guard let due = reminder.dueDate else { return "No due date" }
        let day = isOverdue(reminder, now: now) && !Calendar.current.isDate(due, inSameDayAs: now)
            ? "Overdue · \(CalendarFormat.day(due, now: now))"
            : CalendarFormat.day(due, now: now)
        return reminder.hasDueTime ? "\(day) · \(CalendarFormat.time(due))" : day
    }

    /// Reminders shows "!!!" for high, "!!" for medium and "!" for low.
    static func priorityMarks(_ priority: Int) -> String {
        switch priority {
        case 1...4: "!!!"
        case 5: "!!"
        case 6...9: "!"
        default: ""
        }
    }
}

private struct CalendarNextReminderTile: View {
    private let width: CGFloat = 200

    var body: some View {
        CalendarEventKitGate(entity: .reminder, width: width) {
            TimelineView(.everyMinute) { timeline in
                let now = timeline.date
                let next = CalendarReminderSchedule.next()
                let overdue = next.map { CalendarReminderSchedule.isOverdue($0, now: now) } ?? false
                DockTile(width: width) {
                    HStack(spacing: 10) {
                        CalendarAppIcon(kind: .reminders)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(next.map { CalendarReminderSchedule.longDue($0, now: now) } ?? "All done")
                                .font(.tileValue(14.5))
                                .foregroundStyle(next == nil ? TilePalette.ink : overdue ? calendarOrange : TilePalette.focus)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(next?.title ?? "No open reminders")
                                .font(.tileCaption(9.5))
                                .foregroundStyle(TilePalette.caption)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .calendarBarTap { CalendarApp.reminders.open() }
        }
    }
}

private struct CalendarDueTodayTile: View {
    private let width: CGFloat = 178
    @State private var completing: Set<String> = []
    @Environment(\.tileContext) private var context

    var body: some View {
        CalendarEventKitGate(entity: .reminder, width: width) {
            TimelineView(.everyMinute) { timeline in
                let now = timeline.date
                let due = CalendarReminderSchedule.dueToday(now: now)
                DockTile(width: width) {
                    VStack(alignment: .leading, spacing: 4) {
                        if due.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(calendarGreen)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Nothing due today")
                                        .font(.tileText(10.5, weight: .semibold))
                                        .foregroundStyle(TilePalette.ink.opacity(0.9))
                                    Text("\(RemindersInfo.shared.reminders.count) open reminders")
                                        .font(.tileCaption(9))
                                        .foregroundStyle(TilePalette.caption)
                                }
                            }
                        }
                        ForEach(due.prefix(3)) { reminder in
                            row(reminder, now: now)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .calendarBarTap { CalendarApp.reminders.open() }
        }
    }

    private func row(_ reminder: RemindersInfo.Reminder, now: Date) -> some View {
        let tint = Color(calendarColor: reminder.listColor)
        let isDone = completing.contains(reminder.id)
        let overdue = CalendarReminderSchedule.isOverdue(reminder, now: now)
        let marks = CalendarReminderSchedule.priorityMarks(reminder.priority)
        return HStack(spacing: 6) {
            Button {
                complete(reminder)
            } label: {
                ZStack {
                    Circle().strokeBorder(tint, lineWidth: 1.3)
                    if isDone {
                        Circle().fill(tint)
                        Image(systemName: "checkmark")
                            .font(.system(size: 6, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 10, height: 10)
                .contentShape(Rectangle().inset(by: -3))
            }
            .buttonStyle(.plain)
            .allowsHitTesting(context == .bar)
            Text(reminder.title)
                .font(.tileText(10.5, weight: .semibold))
                .foregroundStyle(TilePalette.ink.opacity(isDone ? 0.45 : 0.94))
                .strikethrough(isDone)
                .lineLimit(1)
            if !marks.isEmpty {
                Text(marks)
                    .font(.tileText(10, weight: .bold))
                    .foregroundStyle(calendarOrange)
            }
            Spacer(minLength: 4)
            Text(CalendarReminderSchedule.shortDue(reminder, now: now))
                .font(.tileText(9.5, weight: .medium))
                .foregroundStyle(overdue ? calendarOrange : TilePalette.caption)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func complete(_ reminder: RemindersInfo.Reminder) {
        withAnimation(.easeOut(duration: 0.2)) { _ = completing.insert(reminder.id) }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            RemindersInfo.shared.complete(id: reminder.id)
            completing.remove(reminder.id)
        }
    }
}

private struct CalendarRemindersAgendaTile: View {
    private let width: CGFloat = 200

    var body: some View {
        CalendarEventKitGate(entity: .reminder, width: width) {
            TimelineView(.everyMinute) { timeline in
                let now = timeline.date
                let reminders = RemindersInfo.shared.reminders
                let overdue = reminders.filter { CalendarReminderSchedule.isOverdue($0, now: now) }.count
                let dueToday = CalendarReminderSchedule.dueToday(now: now).count
                DockTile(width: width, inset: 5) {
                    HStack(spacing: 9) {
                        if overdue > 0 {
                            CalendarNumberBox(number: "\(overdue)", caption: "Overdue", tint: calendarOrange)
                        } else {
                            CalendarNumberBox(number: "\(dueToday)", caption: "Today", tint: TilePalette.focus)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            if reminders.isEmpty {
                                Text("All done")
                                    .font(.tileText(10.5, weight: .semibold))
                                    .foregroundStyle(TilePalette.ink.opacity(0.85))
                                Text("No open reminders")
                                    .font(.tileCaption(9))
                                    .foregroundStyle(TilePalette.caption)
                            }
                            ForEach(reminders.prefix(2)) { reminder in
                                entry(reminder, now: now)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if reminders.count > 2 {
                            CalendarMoreChip(count: reminders.count - 2)
                                .padding(.trailing, 3)
                                .padding(.bottom, 1)
                        }
                    }
                }
            }
            .calendarBarTap { CalendarApp.reminders.open() }
        }
    }

    @ViewBuilder
    private func entry(_ reminder: RemindersInfo.Reminder, now: Date) -> some View {
        let marks = CalendarReminderSchedule.priorityMarks(reminder.priority)
        HStack(spacing: 3) {
            Text(reminder.title)
                .font(.tileText(10.5, weight: .semibold))
                .foregroundStyle(Color(calendarColor: reminder.listColor))
                .lineLimit(1)
            if !marks.isEmpty {
                Text(marks)
                    .font(.tileText(10, weight: .bold))
                    .foregroundStyle(calendarOrange)
            }
        }
        Text(subtitle(reminder, now: now))
            .font(.tileText(9, weight: .medium))
            .foregroundStyle(TilePalette.caption)
            .monospacedDigit()
            .lineLimit(1)
            .padding(.bottom, 2)
    }

    /// "Work · 14:26"
    private func subtitle(_ reminder: RemindersInfo.Reminder, now: Date) -> String {
        [reminder.listTitle, CalendarReminderSchedule.shortDue(reminder, now: now)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

// MARK: - Quick Contacts

@MainActor
@Observable
private final class CalendarContactsStore {
    static let shared = CalendarContactsStore()
    static let limit = 3

    struct Person: Identifiable {
        let id: String
        let name: String
        let initial: String
        let thumbnail: NSImage?
        let phones: [String]
        let emails: [String]
    }

    /// The people on the tile, in the order chosen.
    private(set) var people: [Person] = []
    private(set) var status = CNContactStore.authorizationStatus(for: .contacts)

    private static let defaultsKey = "quickContacts"
    private let store = CNContactStore()
    private var loaded = false

    private static let keys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor
    ]

    /// Explicit picks; `nil` until the user picks, meaning "the first people
    /// in Contacts".
    private var chosenIDs: [String]? {
        get { UserDefaults.standard.stringArray(forKey: Self.defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.defaultsKey) }
    }

    init() {
        NotificationCenter.default.addObserver(forName: .CNContactStoreDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CalendarContactsStore.shared.reload() }
        }
    }

    func loadIfNeeded() {
        guard !loaded else { return }
        reload()
    }

    func reload() {
        status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized else {
            people = []
            return
        }
        loaded = true
        if let ids = chosenIDs {
            guard !ids.isEmpty else {
                people = []
                return
            }
            let predicate = CNContact.predicateForContacts(withIdentifiers: ids)
            let found = ((try? store.unifiedContacts(matching: predicate, keysToFetch: Self.keys)) ?? [])
                .map(Self.person(from:))
            people = ids.compactMap { id in found.first { $0.id == id } }
        } else {
            people = firstPeople(matching: "", limit: Self.limit)
        }
    }

    func requestAccess() {
        guard status == .notDetermined else { return }
        store.requestAccess(for: .contacts) { _, _ in
            Task { @MainActor in CalendarContactsStore.shared.reload() }
        }
    }

    /// People whose name matches `query` (everyone when empty), reachable by
    /// phone or email.
    func firstPeople(matching query: String, limit: Int) -> [Person] {
        guard status == .authorized else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let predicate = CNContact.predicateForContacts(matchingName: trimmed)
            return ((try? store.unifiedContacts(matching: predicate, keysToFetch: Self.keys)) ?? [])
                .map(Self.person(from:))
                .filter { !$0.phones.isEmpty || !$0.emails.isEmpty }
                .prefix(limit)
                .map { $0 }
        }
        var result: [Person] = []
        let request = CNContactFetchRequest(keysToFetch: Self.keys)
        request.sortOrder = .userDefault
        try? store.enumerateContacts(with: request) { contact, stop in
            let person = Self.person(from: contact)
            if !person.phones.isEmpty || !person.emails.isEmpty {
                result.append(person)
            }
            if result.count >= limit { stop.pointee = true }
        }
        return result
    }

    func isChosen(_ person: Person) -> Bool {
        people.contains { $0.id == person.id }
    }

    func toggle(_ person: Person) {
        var ids = people.map(\.id)
        if let index = ids.firstIndex(of: person.id) {
            ids.remove(at: index)
        } else if ids.count < Self.limit {
            ids.append(person.id)
        } else {
            return
        }
        chosenIDs = ids
        reload()
    }

    private static func person(from contact: CNContact) -> Person {
        let formatted = CNContactFormatter.string(from: contact, style: .fullName)
        let name = formatted?.isEmpty == false ? formatted! : contact.organizationName
        let initialSource = contact.givenName.isEmpty ? name : contact.givenName
        return Person(
            id: contact.identifier,
            name: name.isEmpty ? "No Name" : name,
            initial: initialSource.first.map { String($0).uppercased() } ?? "?",
            thumbnail: contact.thumbnailImageData.flatMap { NSImage(data: $0) },
            phones: contact.phoneNumbers.map { $0.value.stringValue },
            emails: contact.emailAddresses.map { $0.value as String }
        )
    }
}

private struct CalendarAvatar: View {
    let person: CalendarContactsStore.Person
    var diameter: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(TilePalette.ink.opacity(0.08))
            if let thumbnail = person.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(Circle())
            } else {
                Text(person.initial)
                    .font(.tileText(diameter * 0.32, weight: .semibold))
                    .foregroundStyle(TilePalette.ink.opacity(0.82))
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay { Circle().strokeBorder(TilePalette.ink.opacity(0.06), lineWidth: 1) }
    }
}

private struct CalendarQuickContactsTile: View {
    private let width: CGFloat = 130
    @Environment(\.tileContext) private var context

    var body: some View {
        let store = CalendarContactsStore.shared
        Group {
            if store.status != .authorized {
                CalendarNoticeTile(width: width, icon: .contacts, title: "Contacts", caption: "Allow access")
                    .calendarBarTap {
                        if store.status == .notDetermined {
                            store.requestAccess()
                        } else {
                            CalendarPrivacyPane.contacts.open()
                        }
                    }
            } else if store.people.isEmpty {
                CalendarNoticeTile(width: width, icon: .contacts, title: "No people", caption: "Right-click to choose")
            } else {
                DockTile(width: width, inset: 5) {
                    HStack(spacing: 6) {
                        ForEach(store.people) { person in
                            Button {
                                CalendarContactActions.showMenu(for: person)
                            } label: {
                                CalendarAvatar(person: person)
                            }
                            .buttonStyle(.plain)
                            .allowsHitTesting(context == .bar)
                            .help(person.name)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .task {
            store.loadIfNeeded()
            if context == .bar { store.requestAccess() }
        }
    }
}

/// Message, FaceTime, call or email a person from a pop-up menu.
@MainActor
private enum CalendarContactActions {
    static func showMenu(for person: CalendarContactsStore.Person) {
        let menu = NSMenu()
        let header = NSMenuItem(title: person.name, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let phone = person.phones.first.map(dialable)
        let email = person.emails.first
        if let handle = phone ?? email {
            add("Message", symbol: "message.fill", to: menu, url: phone != nil ? "sms:\(handle)" : "imessage:\(handle)")
            add("FaceTime", symbol: "video.fill", to: menu, url: "facetime://\(handle)")
            add("FaceTime Audio", symbol: "phone.fill", to: menu, url: "facetime-audio://\(handle)")
        }
        if let phone {
            add("Call \(person.phones[0])", symbol: "phone", to: menu, url: "tel:\(phone)")
        }
        if let email {
            add("Email \(email)", symbol: "envelope.fill", to: menu, url: "mailto:\(email)")
        }
        _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private static func dialable(_ number: String) -> String {
        String(number.filter { $0.isNumber || $0 == "+" })
    }

    private static func add(_ title: String, symbol: String, to menu: NSMenu, url: String) {
        guard let target = URL(string: url) else { return }
        let action = CalendarMenuAction { NSWorkspace.shared.open(target) }
        let item = NSMenuItem(title: title, action: #selector(CalendarMenuAction.run), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        menu.addItem(item)
    }
}

@MainActor
private final class CalendarMenuAction: NSObject {
    private let handler: @MainActor () -> Void

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @objc func run() {
        handler()
    }
}

/// The settings popover: search Contacts and pick up to three people.
private struct CalendarContactsPicker: View {
    @State private var query = ""

    var body: some View {
        let store = CalendarContactsStore.shared
        VStack(alignment: .leading, spacing: 8) {
            if store.status != .authorized {
                Text("DockDock needs access to Contacts.")
                    .font(.tileText(11, weight: .medium))
                    .foregroundStyle(TilePalette.ink.opacity(0.7))
                Button(store.status == .notDetermined ? "Allow Access" : "Open Privacy Settings") {
                    if store.status == .notDetermined {
                        store.requestAccess()
                    } else {
                        CalendarPrivacyPane.contacts.open()
                    }
                }
                .controlSize(.small)
            } else {
                Text("Choose up to \(CalendarContactsStore.limit) people")
                    .font(.tileText(9.5, weight: .medium))
                    .foregroundStyle(TilePalette.ink.opacity(0.45))
                CalendarTextField(placeholder: "Search contacts", text: $query)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.firstPeople(matching: query, limit: 40)) { person in
                            row(person, store: store)
                        }
                    }
                }
                .frame(height: 200)
            }
        }
        .frame(width: 260)
        .task { store.loadIfNeeded() }
    }

    private func row(_ person: CalendarContactsStore.Person, store: CalendarContactsStore) -> some View {
        let chosen = store.isChosen(person)
        return Button {
            store.toggle(person)
        } label: {
            HStack(spacing: 8) {
                CalendarAvatar(person: person, diameter: 22)
                Text(person.name)
                    .font(.tileText(11.5, weight: .medium))
                    .foregroundStyle(TilePalette.ink.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(chosen ? TilePalette.focus : TilePalette.ink.opacity(0.25))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: min(8, TileMetrics.corner), style: .continuous)
                    .fill(TilePalette.ink.opacity(chosen ? 0.07 : 0.0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!chosen && store.people.count >= CalendarContactsStore.limit)
    }
}

private struct CalendarTextField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.tileText(11.5))
            .foregroundStyle(TilePalette.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: min(8, TileMetrics.corner), style: .continuous)
                    .fill(TilePalette.ink.opacity(0.07))
            }
            .onSubmit(onSubmit)
    }
}

// MARK: - Mail

@MainActor
private enum CalendarMail {
    static func compose() {
        if let url = URL(string: "mailto:") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens Mail when it is closed; asks for automation when the script was
    /// refused.
    static func openOrAllow() {
        let mail = MailService.shared
        if mail.isMailRunning, mail.unread == nil {
            CalendarPrivacyPane.automation.open()
        } else {
            CalendarApp.mail.open()
        }
    }

    /// Caption shown when Mail can't be read.
    static var unavailableCaption: String? {
        let mail = MailService.shared
        if !mail.isMailRunning { return "Open Mail to see new mail" }
        if mail.unread == nil { return "Allow DockDock to control Mail" }
        return nil
    }
}

private struct CalendarMailUnreadTile: View {
    private let width: CGFloat = 200

    var body: some View {
        let mail = MailService.shared
        DockTile(width: width) {
            HStack(spacing: 10) {
                CalendarAppIcon(kind: .mail)
                VStack(alignment: .leading, spacing: 0) {
                    if let unread = mail.unread {
                        Text("\(unread)")
                            .font(.tileValue(19))
                            .foregroundStyle(TilePalette.ink)
                            .monospacedDigit()
                        Text(caption(today: mail.unreadToday))
                            .font(.tileCaption(8.5))
                            .foregroundStyle(TilePalette.caption)
                            .lineLimit(1)
                    } else {
                        Text("Mail")
                            .font(.tileValue(14))
                            .foregroundStyle(TilePalette.ink)
                        Text(CalendarMail.unavailableCaption ?? "")
                            .font(.tileCaption(8.5))
                            .foregroundStyle(TilePalette.caption)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                CalendarComposeButton { CalendarMail.compose() }
            }
        }
        .calendarBarTap { CalendarMail.openOrAllow() }
    }

    private func caption(today: Int?) -> String {
        guard let today, today > 0 else { return "Unread" }
        return "Unread · +\(today) today"
    }
}

private struct CalendarLatestMailTile: View {
    private let width: CGFloat = 244

    var body: some View {
        let mail = MailService.shared
        DockTile(width: width) {
            HStack(spacing: 10) {
                CalendarAppIcon(kind: .mail)
                VStack(alignment: .leading, spacing: 1) {
                    if let unread = mail.unread {
                        Text(mail.latestSender.map { unread > 0 ? "\($0) sent" : "Latest from \($0)" } ?? "Inbox")
                            .font(.tileCaption(8.5))
                            .foregroundStyle(TilePalette.caption)
                            .lineLimit(1)
                        Text(mail.latestSubject ?? "No messages")
                            .font(.tileText(12, weight: .bold))
                            .foregroundStyle(TilePalette.ink)
                            .lineLimit(1)
                        Text(more(unread: unread))
                            .font(.tileCaption(8.5))
                            .foregroundStyle(TilePalette.caption)
                            .lineLimit(1)
                    } else {
                        Text("Latest Mail")
                            .font(.tileText(12, weight: .bold))
                            .foregroundStyle(TilePalette.ink)
                        Text(CalendarMail.unavailableCaption ?? "")
                            .font(.tileCaption(8.5))
                            .foregroundStyle(TilePalette.caption)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                CalendarComposeButton { CalendarMail.compose() }
            }
        }
        .calendarBarTap { CalendarMail.openOrAllow() }
    }

    private func more(unread: Int) -> String {
        switch unread {
        case 0: "No unread mail"
        case 1: "No more unread"
        default: "+\(unread - 1) more unread"
        }
    }
}

// MARK: - Notes

private struct CalendarBookmarksTile: View {
    @State private var isEditing = false

    var body: some View {
        DockTile(width: TileMetrics.square) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(TilePalette.ink.opacity(0.42))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .calendarBarTap {
            NSApp.activate()
            isEditing = true
        }
        .popover(isPresented: $isEditing, arrowEdge: .top) {
            CalendarBookmarksEditor()
                .padding(12)
                .preferredColorScheme(AppearanceStore.shared.theme.appearance)
        }
    }
}

/// Saved links: click to open, × to remove, and a field to add one.
private struct CalendarBookmarksEditor: View {
    @State private var title = ""
    @State private var address = ""

    var body: some View {
        let store = BookmarkStore.shared
        VStack(alignment: .leading, spacing: 8) {
            if store.bookmarks.isEmpty {
                Text("No bookmarks yet")
                    .font(.tileText(11, weight: .medium))
                    .foregroundStyle(TilePalette.ink.opacity(0.45))
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.bookmarks) { bookmark in
                            row(bookmark, store: store)
                        }
                    }
                }
                .frame(maxHeight: 180)
                .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 5) {
                CalendarTextField(placeholder: "Title (optional)", text: $title, onSubmit: add)
                HStack(spacing: 6) {
                    CalendarTextField(placeholder: "example.com", text: $address, onSubmit: add)
                    Button("Add", action: add)
                        .controlSize(.small)
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(width: 260)
    }

    private func row(_ bookmark: BookmarkStore.Bookmark, store: BookmarkStore) -> some View {
        HStack(spacing: 8) {
            Button {
                if let url = URL(string: bookmark.url) { NSWorkspace.shared.open(url) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                        .foregroundStyle(TilePalette.focus)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(bookmark.title)
                            .font(.tileText(11.5, weight: .medium))
                            .foregroundStyle(TilePalette.ink.opacity(0.9))
                            .lineLimit(1)
                        Text(URL(string: bookmark.url)?.host ?? bookmark.url)
                            .font(.tileText(9, weight: .medium))
                            .foregroundStyle(TilePalette.ink.opacity(0.4))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                store.remove(bookmark)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(TilePalette.ink.opacity(0.3))
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: min(8, TileMetrics.corner), style: .continuous)
                .fill(TilePalette.ink.opacity(0.04))
        }
    }

    private func add() {
        guard !address.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        BookmarkStore.shared.add(title: title, url: address)
        title = ""
        address = ""
    }
}

private struct CalendarNotesTile: View {
    private let width: CGFloat = 200
    @State private var isEditing = false

    var body: some View {
        let lines = NotesStore.shared.text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        DockTile(width: width) {
            HStack(spacing: 10) {
                CalendarAppIcon(kind: .notes)
                VStack(alignment: .leading, spacing: 1) {
                    Text(lines.first.map(Self.stripHeading) ?? "New Note")
                        .font(.tileText(11, weight: .bold))
                        .foregroundStyle(TilePalette.ink)
                        .lineLimit(1)
                    Text(lines.isEmpty ? "Click to start writing" : lines.dropFirst().joined(separator: " "))
                        .font(.tileCaption(8.5))
                        .foregroundStyle(TilePalette.caption)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                CalendarComposeButton { edit() }
            }
        }
        .calendarBarTap { edit() }
        .popover(isPresented: $isEditing, arrowEdge: .top) {
            CalendarNoteEditor()
                .padding(12)
                .preferredColorScheme(AppearanceStore.shared.theme.appearance)
        }
    }

    private func edit() {
        NSApp.activate()
        isEditing = true
    }

    private static func stripHeading(_ line: String) -> String {
        let stripped = line.drop { $0 == "#" || $0 == " " }
        return stripped.isEmpty ? line : String(stripped)
    }
}

/// Edits the note; the first line is its title.
private struct CalendarNoteEditor: View {
    @Bindable private var notes = NotesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $notes.text)
                .font(.tileText(12))
                .foregroundStyle(TilePalette.ink)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background {
                    RoundedRectangle(cornerRadius: min(8, TileMetrics.corner), style: .continuous)
                        .fill(TilePalette.ink.opacity(0.06))
                }
                .frame(height: 170)
            Text("The first line is the note's title.")
                .font(.tileText(9, weight: .medium))
                .foregroundStyle(TilePalette.ink.opacity(0.4))
        }
        .frame(width: 260)
    }
}
