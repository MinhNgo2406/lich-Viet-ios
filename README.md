# Lịch Việt

Ứng dụng lịch iPhone kết hợp lịch dương và âm lịch Việt Nam, ghi chú theo ngày, nhắc việc và xem sự kiện Google Calendar.
Ứng dụng này thuộc repository `lich-Viet-ios`.

## Mở project

1. Mở `Calendar.xcodeproj` bằng Xcode.
2. Chọn scheme **Calendar** và một iPhone Simulator hoặc iPhone đã kết nối.
3. Nhấn **Run** để build và chạy ứng dụng.

App hiển thị trên iPhone với tên **Lịch Việt**. Tên scheme và project Xcode vẫn là `Calendar`.

## Google Calendar

Lưu ý: thêm cấu hình OAuth iOS trong Google Cloud Console trước khi bật đăng nhập Google. Đặt client ID và URL scheme tương ứng trong cấu hình build của Xcode. Không commit client secret, khóa riêng tư hoặc file chứng thực vào repository.

## Nền tảng

- SwiftUI
- iOS 16 trở lên
- Google Sign-In SDK for iOS
