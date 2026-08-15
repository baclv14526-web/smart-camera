# 📷 Camera App – Flutter

App chụp ảnh & quay phim cho Android với các tính năng:

- 🎬 **Quay video hẹn giờ tự ngắt**: 15s / 30s / 1p / 3p / 5p / 10p
- 📷 **Hẹn giờ chụp ảnh**: 3s / 5s / 10s / 15s
- 🔄 **Camera trước / sau**
- 🌟 **Chất lượng HD / Full HD**
- 💡 **Flash**: Tắt / Auto / Bật
- 👁️ **Xem trước ngay sau khi chụp / quay**

---

## ⚙️ Yêu cầu

| Công cụ | Phiên bản |
|---------|-----------|
| Flutter | ≥ 3.0.0   |
| Dart    | ≥ 3.0.0   |
| Android SDK | 21+ (Android 5.0+) |

---

## 🚀 Build APK

### 1. Cài dependencies

```bash
flutter pub get
```

### 2. Build APK release

```bash
flutter build apk --release
```

APK xuất ra tại:
```
build/app/outputs/flutter-apk/app-release.apk
```

### 3. Build APK theo ABI (nhỏ hơn)

```bash
flutter build apk --release --split-per-abi
```

Sẽ tạo ra 3 file nhỏ hơn:
- `app-armeabi-v7a-release.apk`  → điện thoại cũ 32-bit
- `app-arm64-v8a-release.apk`    → điện thoại mới 64-bit ✅ (dùng cái này)
- `app-x86_64-release.apk`       → giả lập

---

## 📁 Nơi lưu file

| Loại | Đường dẫn trên máy |
|------|-------------------|
| Ảnh  | `Pictures/CameraApp/IMG_*.jpg` |
| Video | `Movies/CameraApp/VID_*.mp4` |

---

## 📦 Cài APK lên điện thoại

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

Hoặc copy file APK sang điện thoại và mở trực tiếp (cần bật "Cài từ nguồn không rõ").

---

## 🐛 Lưu ý

- Lần đầu mở app cần **cấp quyền**: Camera, Microphone, Storage
- Màn hình sẽ **không tắt** trong khi đang quay video
- Android 13+ dùng quyền `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` thay cho `READ_EXTERNAL_STORAGE`
