<div align="center">

# Aviewer

Cross‑platform Flutter application. Simple, clean, and open‑source.

[![Downloads](https://img.shields.io/github/downloads/haorengg12/Aviewer/total?style=flat-square&logo=github)](https://github.com/haorengg12/Aviewer/releases/)
[![Release](https://img.shields.io/github/release/haorengg12/Aviewer/all.svg?style=flat-square)](https://github.com/haorengg12/Aviewer/releases/)
[![License](https://img.shields.io/github/license/haorengg12/Aviewer?style=flat-square)](LICENSE)

</div>

## Features
- Multi‑platform: Android, Windows, iOS
- Modern UI and dark mode
- Open‑source, no ads
- Actively maintained with release artifacts

## Download
- Android
  - Visit Releases and download APK for your ABI:
    - ARM64 (arm64‑v8a)
    - ARMv7 (armeabi‑v7a)
    - x86_64
  - Releases: https://github.com/haorengg12/Aviewer/releases
- Windows
  - Setup EXE installer or Portable ZIP
  - Releases: https://github.com/haorengg12/Aviewer/releases
- iOS
  - Unsigned IPA (sideload via tools like AltStore)
  - Releases: https://github.com/haorengg12/Aviewer/releases

## Build
Ensure you have Flutter installed (stable channel) and platform prerequisites.

### Common
```bash
flutter --version
flutter pub get
```

### Android
```bash
# Optionally ensure Android SDK/NDK are installed via Android Studio
flutter build apk --release --split-per-abi
```

### Windows
```bash
flutter config --enable-windows-desktop
flutter pub get
flutter build windows --release
```

### iOS (macOS required)
```bash
# Xcode and CocoaPods required
flutter pub get
flutter build ipa --release --no-codesign
```

## Star
If you find this project useful, please consider starring it to support the development.
