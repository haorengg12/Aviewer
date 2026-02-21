<div align="center">

<img src="https://storage.moegirl.org.cn/moegirl/commons/8/88/%E7%86%8A%E5%90%89.jpg" alt="熊吉头像" width="96">
<p><em>変態じゃないよ、仮に変態だとしても変態という名の紳士だよ！</em><br/><small>—— 熊吉</small></p>

# Aviewer

A viewer for your 'private' research. Stay hands-free (mostly).

[![Downloads](https://img.shields.io/github/downloads/haorengg12/Aviewer/total?style=flat-square&logo=github)](https://github.com/haorengg12/Aviewer/releases/) [![Release](https://img.shields.io/github/release/haorengg12/Aviewer/all.svg?style=flat-square)](https://github.com/haorengg12/Aviewer/releases/) [![License](https://img.shields.io/github/license/haorengg12/Aviewer?style=flat-square)](LICENSE)

</div>

## Features
- Multi‑platform: Android, Windows, iOS
- Modern UI and dark mode
- Open‑source, no ads
- Actively maintained with release artifacts

## Download
<p align="center">
  <a href="https://github.com/haorengg12/Aviewer/releases">
    <img src="https://raw.githubusercontent.com/rubenpgrady/get-it-on-github/refs/heads/main/get-it-on-github.png" alt="Get it on GitHub" height="96">
  </a>
</p>

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

## Star History

If you find this project useful, please consider starring (⭐) it to support the development.

<a href="https://www.star-history.com/#haorengg12/Aviewer&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=haorengg12/Aviewer&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=haorengg12/Aviewer&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=haorengg12/Aviewer&type=date&legend=top-left" />
 </picture>
</a>
