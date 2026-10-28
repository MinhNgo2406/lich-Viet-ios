import SwiftUI
import UIKit

struct GoogleCalendarSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var service: GoogleCalendarService
    let month: Date

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    accountCard
                    accessCard

                    if let error = service.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(red: 0.68, green: 0.22, blue: 0.15))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    }

                    if !GoogleCalendarService.isConfigured {
                        setupCard
                    }
                }
                .padding(18)
            }
            .background(Color(red: 0.97, green: 0.96, blue: 0.93).ignoresSafeArea())
            .navigationTitle("Google Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.white).frame(width: 46, height: 46)
                    Text("G")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.isSignedIn ? "Đã kết nối" : "Kết nối tài khoản")
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .foregroundStyle(Color(red: 0.15, green: 0.20, blue: 0.29))
                    Text(service.accountEmail ?? "Đăng nhập để xem lịch của bạn")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 0.48, green: 0.51, blue: 0.57))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if service.isSignedIn {
                HStack(spacing: 10) {
                    Button {
                        Task { await service.sync(for: month) }
                    } label: {
                        HStack(spacing: 8) {
                            if service.isLoading { ProgressView().tint(.white) }
                            else { Image(systemName: "arrow.clockwise") }
                            Text(service.isLoading ? "Đang đồng bộ…" : "Đồng bộ ngay")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.73, green: 0.28, blue: 0.21), in: Capsule())
                    }
                    .disabled(service.isLoading)

                    Button("Ngắt kết nối") { service.signOut() }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.48, green: 0.51, blue: 0.57))
                }
                if let lastSyncedAt = service.lastSyncedAt {
                    Text("Cập nhật lúc \(lastSyncedAt.formatted(date: .omitted, time: .shortened)) · \(service.events.count) sự kiện trong tháng")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.48, green: 0.51, blue: 0.57))
                }
            } else {
                Button {
                    Task {
                        guard let root = UIApplication.shared.calendarRootViewController else { return }
                        await service.signIn(presenting: root, month: month)
                    }
                } label: {
                    HStack(spacing: 9) {
                        Text("G")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                        Text("Đăng nhập bằng Google")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0.15, green: 0.20, blue: 0.29))
                        Spacer()
                        if service.isLoading { ProgressView() }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 13)
                    .background(.white, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .disabled(service.isLoading || !GoogleCalendarService.isConfigured)
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Quyền truy cập", systemImage: "lock.shield")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(red: 0.15, green: 0.20, blue: 0.29))
            Text("Ứng dụng chỉ đọc sự kiện trong lịch chính của bạn. App không tạo, sửa hoặc xoá sự kiện Google Calendar.")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.48, green: 0.51, blue: 0.57))
                .fixedSize(horizontal: false, vertical: true)
            if !service.isSignedIn {
                Text("Sau khi kết nối, sự kiện sẽ xuất hiện ở ngày tương ứng và được đồng bộ lại khi bạn chuyển tháng.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.48, green: 0.51, blue: 0.57))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Cần cấu hình Google Cloud", systemImage: "wrench.and.screwdriver")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(red: 0.15, green: 0.20, blue: 0.29))
            Text("Tạo OAuth Client ID loại iOS cho Bundle ID com.minhngopersonalteam.Calendar, bật Google Calendar API, rồi thay YOUR_IOS_OAUTH_CLIENT_ID và YOUR_CLIENT_ID_REVERSED trong Build Settings của target Calendar. Khi có Client ID, mình có thể giúp điền nốt cấu hình.")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.48, green: 0.51, blue: 0.57))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.77, green: 0.59, blue: 0.27).opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private extension UIApplication {
    var calendarRootViewController: UIViewController? {
        let scene = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.windows.first(where: \.isKeyWindow)?.rootViewController
    }
}
