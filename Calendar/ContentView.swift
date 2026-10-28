import SwiftUI
import Combine
import UserNotifications

@MainActor
final class CalendarStore: ObservableObject {
    @Published private(set) var notes: [CalendarNote] = []
    private let storageKey = "calendar.notes.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([CalendarNote].self, from: data) {
            notes = saved
        }
    }

    func notes(on date: Date) -> [CalendarNote] {
        notes.filter { $0.dateKey == CalendarDateKey.string(from: date) }
            .sorted { ($0.reminder ?? .distantFuture) < ($1.reminder ?? .distantFuture) }
    }

    func save(_ note: CalendarNote) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.append(note)
        }
        persist()
        Task { await LocalReminderCenter.shared.schedule(note) }
    }

    func delete(_ note: CalendarNote) {
        notes.removeAll { $0.id == note.id }
        persist()
        LocalReminderCenter.shared.cancel(note)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

@MainActor
final class LocalReminderCenter {
    static let shared = LocalReminderCenter()
    private let center = UNUserNotificationCenter.current()

    func schedule(_ note: CalendarNote) async {
        let identifier = note.id.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let reminder = note.reminder, reminder > Date() else { return }
        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard allowed else { return }
            let content = UNMutableNotificationContent()
            content.title = note.title.isEmpty ? "Nhắc việc" : note.title
            content.body = note.details.isEmpty ? "Bạn có một việc cần nhớ hôm nay." : note.details
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        } catch {
            print("Không thể lên lịch thông báo: \(error.localizedDescription)")
        }
    }

    func cancel(_ note: CalendarNote) {
        center.removePendingNotificationRequests(withIdentifiers: [note.id.uuidString])
    }
}

private enum CalendarStyle {
    static let ink = Color(red: 0.15, green: 0.20, blue: 0.29)
    static let muted = Color(red: 0.48, green: 0.51, blue: 0.57)
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let card = Color.white
    static let accent = Color(red: 0.73, green: 0.28, blue: 0.21)
    static let gold = Color(red: 0.77, green: 0.59, blue: 0.27)
}

struct ContentView: View {
    @StateObject private var store = CalendarStore()
    @StateObject private var googleCalendar = GoogleCalendarService()
    @State private var selectedDate = CalendarDateKey.calendar.startOfDay(for: Date())
    @State private var displayedMonth = CalendarDateKey.calendar.startOfDay(for: Date())
    @State private var editingNote: CalendarNote?
    @State private var showingEditor = false
    @State private var editorDate = Date()
    @State private var showingGoogleSettings = false

    private let weekdays = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        ZStack {
            CalendarStyle.paper.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    monthCard
                    selectedDayCard
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 26)
            }
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingEditor) {
            NoteEditor(date: editorDate, note: editingNote) { note in
                store.save(note)
            }
        }
        .sheet(isPresented: $showingGoogleSettings) {
            GoogleCalendarSettingsView(service: googleCalendar, month: displayedMonth)
        }
        .onAppear { googleCalendar.restorePreviousSignIn() }
        .onChange(of: displayedMonth) { month in
            Task { await googleCalendar.sync(for: month) }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LỊCH VIỆT")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(CalendarStyle.accent)
                Text("Âm Lịch")
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .foregroundStyle(CalendarStyle.ink)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedDate = CalendarDateKey.calendar.startOfDay(for: Date())
                    displayedMonth = selectedDate
                }
            } label: {
                Label("Hôm nay", systemImage: "sparkle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CalendarStyle.accent)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(CalendarStyle.card, in: Capsule())
            }
            .buttonStyle(.plain)
            Button { showingGoogleSettings = true } label: {
                Image(systemName: googleCalendar.isSignedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(googleCalendar.isSignedIn ? CalendarStyle.accent : CalendarStyle.ink)
                    .frame(width: 40, height: 40)
                    .background(CalendarStyle.card, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Google Calendar")
        }
    }

    private var monthCard: some View {
        VStack(spacing: 15) {
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(CalendarStyle.paper, in: Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                VStack(spacing: 2) {
                    Text(monthTitle)
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(CalendarStyle.ink)
                    Text("DƯƠNG LỊCH  ·  ÂM LỊCH VIỆT NAM")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(CalendarStyle.muted)
                }
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(CalendarStyle.paper, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(CalendarStyle.ink)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(day == "CN" ? CalendarStyle.accent : CalendarStyle.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                }
                ForEach(monthDays, id: \.self) { date in
                    dayCell(date)
                }
            }
            HStack(spacing: 6) {
                Circle().fill(CalendarStyle.accent).frame(width: 6, height: 6)
                Text("Ngày lễ")
                Circle().fill(CalendarStyle.gold).frame(width: 6, height: 6).padding(.leading, 8)
                Text("Có ghi chú")
                Circle().fill(Color.blue).frame(width: 6, height: 6).padding(.leading, 8)
                Text("Google")
                Spacer()
                Text("Chạm ngày để xem")
                    .foregroundStyle(CalendarStyle.muted)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(CalendarStyle.muted)
        }
        .padding(16)
        .background(CalendarStyle.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: CalendarStyle.ink.opacity(0.06), radius: 16, y: 6)
    }

    private func dayCell(_ date: Date) -> some View {
        let isInMonth = CalendarDateKey.calendar.component(.month, from: date) == CalendarDateKey.calendar.component(.month, from: displayedMonth)
        let isSelected = CalendarDateKey.string(from: date) == CalendarDateKey.string(from: selectedDate)
        let isToday = CalendarDateKey.string(from: date) == CalendarDateKey.string(from: Date())
        let holidays = VietnamHoliday.names(for: date)
        let hasNotes = !store.notes(on: date).isEmpty
        let hasGoogleEvents = !googleCalendar.events(on: date).isEmpty
        let lunar = VietnameseLunarCalendar.date(from: date)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedDate = date }
        } label: {
            VStack(spacing: 3) {
                Text("\(CalendarDateKey.calendar.component(.day, from: date))")
                    .font(.system(size: 15, weight: isSelected || isToday ? .bold : .medium, design: .rounded))
                Text(lunar.map { "\($0.day)" } ?? "—")
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 3) {
                    if !holidays.isEmpty { Circle().fill(isSelected ? .white : CalendarStyle.accent).frame(width: 4, height: 4) }
                    if hasNotes { Circle().fill(isSelected ? .white : CalendarStyle.gold).frame(width: 4, height: 4) }
                    if hasGoogleEvents { Circle().fill(isSelected ? .white : .blue).frame(width: 4, height: 4) }
                }
                .frame(height: 5)
            }
            .foregroundStyle(cellTextColor(isSelected: isSelected, isInMonth: isInMonth, isSunday: CalendarDateKey.calendar.component(.weekday, from: date) == 1))
            .frame(maxWidth: .infinity)
            .frame(height: 53)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CalendarStyle.accent)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CalendarStyle.accent.opacity(0.5), lineWidth: 1.2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityDate(date, lunar: lunar, holidays: holidays, hasNotes: hasNotes, hasGoogleEvents: hasGoogleEvents))
    }

    private func cellTextColor(isSelected: Bool, isInMonth: Bool, isSunday: Bool) -> Color {
        if isSelected { return .white }
        if !isInMonth { return CalendarStyle.muted.opacity(0.38) }
        if isSunday { return CalendarStyle.accent }
        return CalendarStyle.ink
    }

    private var selectedDayCard: some View {
        let lunar = VietnameseLunarCalendar.date(from: selectedDate)
        let holidays = VietnamHoliday.names(for: selectedDate)
        let notes = store.notes(on: selectedDate)
        let googleEvents = googleCalendar.events(on: selectedDate)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Text(shortWeekday(selectedDate))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.8))
                    Text("\(CalendarDateKey.calendar.component(.day, from: selectedDate))")
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                }
                .frame(width: 58, height: 66)
                .background(CalendarStyle.accent, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(fullSolarDate(selectedDate))
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundStyle(CalendarStyle.ink)
                    if let lunar {
                        Text("Âm lịch: \(lunarDescription(lunar))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CalendarStyle.muted)
                    } else {
                        Text("Chỉ hỗ trợ chuyển đổi âm lịch từ 1900–2100")
                            .font(.system(size: 11))
                            .foregroundStyle(CalendarStyle.muted)
                    }
                }
                .padding(.top, 3)
                Spacer(minLength: 0)
                Button { beginNewNote() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(CalendarStyle.ink, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Thêm ghi chú")
            }

            if !holidays.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(holidays, id: \.self) { holiday in
                        HStack(spacing: 8) {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(CalendarStyle.gold)
                            Text(holiday)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CalendarStyle.ink)
                        }
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CalendarStyle.gold.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            }

            if !googleEvents.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 7) {
                        Image(systemName: "g.circle.fill").foregroundStyle(Color.blue)
                        Text("GOOGLE CALENDAR")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(CalendarStyle.muted)
                        Spacer()
                        if googleCalendar.isLoading { ProgressView().scaleEffect(0.7) }
                    }
                    ForEach(googleEvents) { event in
                        HStack(alignment: .top, spacing: 10) {
                            Text(event.timeLabel)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.blue)
                                .frame(width: 70, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(CalendarStyle.ink)
                                if let location = event.location, !location.isEmpty {
                                    Label(location, systemImage: "mappin.and.ellipse")
                                        .font(.system(size: 11))
                                        .foregroundStyle(CalendarStyle.muted)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }

            Rectangle().fill(CalendarStyle.ink.opacity(0.08)).frame(height: 1)
            HStack {
                Text("GHI CHÚ TRONG NGÀY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(CalendarStyle.muted)
                Spacer()
                if !notes.isEmpty { Text("\(notes.count)").font(.system(size: 11, weight: .bold)).foregroundStyle(CalendarStyle.accent) }
            }

            if notes.isEmpty {
                Button { beginNewNote() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.pencil").font(.system(size: 15))
                        Text("Thêm việc cần nhớ cho ngày này")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(CalendarStyle.muted)
                    .padding(13)
                    .background(CalendarStyle.paper, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 9) {
                    ForEach(notes) { note in
                        noteRow(note)
                    }
                }
            }
        }
        .padding(16)
        .background(CalendarStyle.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: CalendarStyle.ink.opacity(0.05), radius: 14, y: 5)
    }

    private func noteRow(_ note: CalendarNote) -> some View {
        HStack(alignment: .top, spacing: 11) {
            RoundedRectangle(cornerRadius: 2).fill(CalendarStyle.gold).frame(width: 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(note.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(CalendarStyle.ink)
                if !note.details.isEmpty {
                    Text(note.details).font(.system(size: 12)).foregroundStyle(CalendarStyle.muted).lineLimit(3)
                }
                if let reminder = note.reminder {
                    Label(reminder.formatted(date: .omitted, time: .shortened), systemImage: "bell")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CalendarStyle.accent)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button("Sửa ghi chú", systemImage: "pencil") {
                    editingNote = note
                    editorDate = selectedDate
                    showingEditor = true
                }
                Button("Xóa ghi chú", systemImage: "trash", role: .destructive) { store.delete(note) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CalendarStyle.muted)
                    .frame(width: 30, height: 30)
                    .background(CalendarStyle.paper, in: Circle())
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(11)
        .background(CalendarStyle.paper.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "moon.stars.fill").foregroundStyle(CalendarStyle.gold)
            Text("Lịch âm tính theo giờ Việt Nam (UTC+7)")
                .foregroundStyle(CalendarStyle.muted)
        }
        .font(.system(size: 10, weight: .medium))
        .frame(maxWidth: .infinity)
    }

    private var monthDays: [Date] {
        let calendar = CalendarDateKey.calendar
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)),
              calendar.range(of: .day, in: .month, for: monthStart) != nil,
              let first = calendar.date(byAdding: .day, value: 0, to: monthStart) else { return [] }
        let weekday = calendar.component(.weekday, from: first)
        let offset = (weekday + 5) % 7 // Monday-first week
        guard let gridStart = calendar.date(byAdding: .day, value: -offset, to: first) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private var monthTitle: String {
        let c = CalendarDateKey.calendar.dateComponents([.month, .year], from: displayedMonth)
        return "Tháng \(c.month ?? 1), \(c.year ?? 2026)"
    }

    private func shiftMonth(_ amount: Int) {
        guard let next = CalendarDateKey.calendar.date(byAdding: .month, value: amount, to: displayedMonth) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            displayedMonth = next
            if let day = CalendarDateKey.calendar.date(byAdding: .month, value: amount, to: selectedDate) {
                selectedDate = day
            }
        }
    }

    private func beginNewNote() {
        editingNote = nil
        editorDate = selectedDate
        showingEditor = true
    }

    private func shortWeekday(_ date: Date) -> String {
        let symbols = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"]
        return symbols[CalendarDateKey.calendar.component(.weekday, from: date) - 1]
    }

    private func fullSolarDate(_ date: Date) -> String {
        date.formatted(.dateTime.locale(Locale(identifier: "vi_VN")).weekday(.wide).day().month(.wide).year())
    }

    private func lunarDescription(_ lunar: LunarDate) -> String {
        let dayName = lunar.day == 1 ? "mùng 1" : (lunar.day < 10 ? "mùng \(lunar.day)" : "ngày \(lunar.day)")
        return "\(dayName) tháng \(lunar.month)\(lunar.isLeapMonth ? " nhuận" : ""), năm \(lunar.year)"
    }

    private func accessibilityDate(_ date: Date, lunar: LunarDate?, holidays: [String], hasNotes: Bool, hasGoogleEvents: Bool) -> String {
        var description = fullSolarDate(date)
        if let lunar { description += ", âm lịch \(lunar.day)/\(lunar.month)" }
        if !holidays.isEmpty { description += ", \(holidays.joined(separator: ", "))" }
        if hasNotes { description += ", có ghi chú" }
        if hasGoogleEvents { description += ", có sự kiện Google Calendar" }
        return description
    }
}

private struct NoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let existingNote: CalendarNote?
    let onSave: (CalendarNote) -> Void

    @State private var title: String
    @State private var details: String
    @State private var hasReminder: Bool
    @State private var reminderTime: Date

    init(date: Date, note: CalendarNote?, onSave: @escaping (CalendarNote) -> Void) {
        self.date = date
        self.existingNote = note
        self.onSave = onSave
        _title = State(initialValue: note?.title ?? "")
        _details = State(initialValue: note?.details ?? "")
        _hasReminder = State(initialValue: note?.reminder != nil)
        _reminderTime = State(initialValue: note?.reminder ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ví dụ: Họp với khách hàng", text: $title)
                    TextField("Ghi chú thêm", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text(date.formatted(.dateTime.locale(Locale(identifier: "vi_VN")).weekday(.wide).day().month(.wide).year()))
                }

                Section {
                    Toggle("Nhắc tôi", isOn: $hasReminder.animation())
                    if hasReminder {
                        DatePicker("Giờ nhắc", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("Thông báo được lên lịch trên iPhone. Hãy cho phép thông báo khi iOS hỏi.")
                }
            }
            .navigationTitle(existingNote == nil ? "Ghi chú mới" : "Sửa ghi chú")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let savedReminder: Date? = hasReminder ? reminderDate() : nil
        let note = CalendarNote(
            id: existingNote?.id ?? UUID(),
            dateKey: CalendarDateKey.string(from: date),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            reminder: savedReminder
        )
        onSave(note)
        dismiss()
    }

    private func reminderDate() -> Date {
        // Calendar dates are stored as Vietnamese civil days (UTC+7), while the
        // reminder itself should fire at the selected clock time on this device.
        var parts = CalendarDateKey.calendar.dateComponents([.year, .month, .day], from: date)
        let timeParts = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        parts.hour = timeParts.hour
        parts.minute = timeParts.minute
        parts.second = 0
        return Calendar.current.date(from: parts) ?? date
    }
}

#Preview {
    ContentView()
}
