import Foundation
import Combine
import GoogleSignIn
import UIKit

struct GoogleCalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let details: String?
    let location: String?
    let start: Date?
    let end: Date?
    let isAllDay: Bool
    let firstDateKey: String
    let lastDateKey: String

    func occurs(on date: Date) -> Bool {
        let key = CalendarDateKey.string(from: date)
        return firstDateKey <= key && key <= lastDateKey
    }

    var timeLabel: String {
        guard !isAllDay, let start else { return "Cả ngày" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        if let end {
            return "\(formatter.string(from: start))–\(formatter.string(from: end))"
        }
        return formatter.string(from: start)
    }
}

@MainActor
final class GoogleCalendarService: ObservableObject {
    static let readOnlyScope = "https://www.googleapis.com/auth/calendar.events.readonly"

    @Published private(set) var events: [GoogleCalendarEvent] = []
    @Published private(set) var accountEmail: String?
    @Published private(set) var isSignedIn = false
    @Published private(set) var isLoading = false
    @Published private(set) var lastSyncedAt: Date?
    @Published var errorMessage: String?

    private var currentUser: GIDGoogleUser?
    private var lastRequestedMonth = Date()

    static var isConfigured: Bool {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else { return false }
        return !clientID.isEmpty && !clientID.contains("YOUR_") && clientID.hasSuffix(".apps.googleusercontent.com")
    }

    func restorePreviousSignIn() {
        guard Self.isConfigured else { return }
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, _ in
            guard let self else { return }
            self.currentUser = user
            self.accountEmail = user?.profile?.email
            self.isSignedIn = user != nil
            if user != nil {
                Task { await self.sync(for: self.lastRequestedMonth) }
            }
        }
    }

    func signIn(presenting controller: UIViewController, month: Date) async {
        guard Self.isConfigured else {
            errorMessage = "Chưa cấu hình Google OAuth. Hãy thay Client ID và URL scheme trong GoogleOAuthInfo.plist / Build Settings bằng thông tin từ Google Cloud."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: controller,
                hint: nil,
                additionalScopes: [Self.readOnlyScope]
            )
            currentUser = result.user
            accountEmail = result.user.profile?.email
            isSignedIn = true
            await sync(for: month)
        } catch {
            errorMessage = "Không đăng nhập được Google: \(error.localizedDescription)"
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        currentUser = nil
        accountEmail = nil
        isSignedIn = false
        events = []
        lastSyncedAt = nil
        errorMessage = nil
    }

    func sync(for month: Date) async {
        lastRequestedMonth = month
        guard Self.isConfigured, let currentUser else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let refreshedUser = try await currentUser.refreshTokensIfNeeded()
            self.currentUser = refreshedUser
            let token = refreshedUser.accessToken.tokenString
            let range = visibleRange(for: month)
            events = try await fetchEvents(accessToken: token, from: range.start, to: range.end)
            lastSyncedAt = Date()
        } catch {
            errorMessage = "Không đồng bộ được Google Calendar: \(error.localizedDescription)"
        }
    }

    func events(on date: Date) -> [GoogleCalendarEvent] {
        events.filter { $0.occurs(on: date) }
            .sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    private func visibleRange(for month: Date) -> (start: Date, end: Date) {
        let calendar = CalendarDateKey.calendar
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let mondayOffset = (weekday + 5) % 7
        let start = calendar.date(byAdding: .day, value: -mondayOffset, to: firstOfMonth) ?? firstOfMonth
        let end = calendar.date(byAdding: .day, value: 42, to: start) ?? firstOfMonth
        return (start, end)
    }

    private func fetchEvents(accessToken: String, from start: Date, to end: Date) async throws -> [GoogleCalendarEvent] {
        var allEvents: [GoogleCalendarEvent] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
            var query: [URLQueryItem] = [
                URLQueryItem(name: "timeMin", value: Self.apiDateFormatter.string(from: start)),
                URLQueryItem(name: "timeMax", value: Self.apiDateFormatter.string(from: end)),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "2500"),
            ]
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            components.queryItems = query
            guard let url = components.url else { throw GoogleCalendarError.invalidURL }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GoogleCalendarError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let detail = String(data: data, encoding: .utf8) ?? ""
                throw GoogleCalendarError.api(status: http.statusCode, detail: detail)
            }
            let page = try JSONDecoder().decode(GoogleEventsPage.self, from: data)
            allEvents.append(contentsOf: page.items.compactMap(GoogleCalendarEvent.init(payload:)))
            pageToken = page.nextPageToken
        } while pageToken != nil

        return allEvents.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = CalendarDateKey.vietnamTimeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        return formatter
    }()
}

private struct GoogleEventsPage: Decodable {
    let items: [GoogleEventPayload]
    let nextPageToken: String?
}

private struct GoogleEventPayload: Decodable {
    let id: String?
    let summary: String?
    let description: String?
    let location: String?
    let start: GoogleEventDate?
    let end: GoogleEventDate?
    let status: String?
}

private struct GoogleEventDate: Decodable {
    let date: String?
    let dateTime: String?
    let timeZone: String?
}

private enum GoogleCalendarError: LocalizedError {
    case invalidURL
    case invalidResponse
    case api(status: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Địa chỉ yêu cầu không hợp lệ."
        case .invalidResponse:
            return "Google Calendar trả về dữ liệu không hợp lệ."
        case let .api(status, detail):
            return "Lỗi Google Calendar (\(status)): \(detail)"
        }
    }
}

private extension GoogleCalendarEvent {
    init?(payload: GoogleEventPayload) {
        guard let id = payload.id, payload.status != "cancelled" else { return nil }
        let title = payload.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let startValue = payload.start, let endValue = payload.end else { return nil }

        if let startDate = startValue.date, let endDate = endValue.date,
           let firstDay = CalendarDateKey.date(from: startDate),
           let endExclusive = CalendarDateKey.date(from: endDate),
           let lastDay = CalendarDateKey.calendar.date(byAdding: .day, value: -1, to: endExclusive) {
            self.init(
                id: id,
                title: title?.isEmpty == false ? title! : "Sự kiện",
                details: payload.description,
                location: payload.location,
                start: nil,
                end: nil,
                isAllDay: true,
                firstDateKey: CalendarDateKey.string(from: firstDay),
                lastDateKey: CalendarDateKey.string(from: lastDay)
            )
            return
        }

        guard let start = Self.parseDateTime(startValue.dateTime),
              let end = Self.parseDateTime(endValue.dateTime) else { return nil }
        let finalInstant = end.addingTimeInterval(-1)
        self.init(
            id: id,
            title: title?.isEmpty == false ? title! : "Sự kiện",
            details: payload.description,
            location: payload.location,
            start: start,
            end: end,
            isAllDay: false,
            firstDateKey: CalendarDateKey.string(from: start),
            lastDateKey: CalendarDateKey.string(from: finalInstant)
        )
    }

    static func parseDateTime(_ value: String?) -> Date? {
        guard let value else { return nil }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = precise.date(from: value) { return result }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}
