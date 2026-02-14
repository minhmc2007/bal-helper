
# 📂 BAL Helper (Blue Archive Linux)

![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-02569B?logo=flutter)
![Linux](https://img.shields.io/badge/Distro-Arch%20Linux-1793D1?logo=arch-linux)
![Style](https://img.shields.io/badge/Style-Blue%20Archive-128CFF)

> *"Welcome to Schale, Sensei. System initialization complete."*

**BAL Helper** is the central command hub for **Blue Archive Linux**, an Arch-based distribution. It provides a highly animated, anime-inspired interface to manage post-installation tasks, system updates, and aesthetic customization.

Designed with **Flutter**, it replaces boring terminal setups with a modern, "Schale Office" aesthetic.

---

## ✨ Key Features

### 🖥️ The Interface
*   **Rich Animations:** Every element features entrance animations (Fade/Slide) to keep the user engaged.
*   **Video Background:** dynamic loop capability using `media_kit`.
*   **Glassmorphism & Grids:** A clean, tech-inspired UI overlay.
*   **Custom Window Controls:** MacOS-style traffic light buttons (Red/Yellow/Green) for a sleek look, fully integrated with `window_manager`.

### 📦 Logistics (Post-Install)
Automated scripts running via **Konsole** to install essential tools:
*   **AUR Support:** Automated installation of `yay-bin` (fast compilation).
*   **Gaming:** One-click setup for Steam.
*   **Drivers:** Proprietary Nvidia driver installation.
*   **Audio:** Full Pipewire stack setup.

### 🎨 Art Club (Visuals)
*   **Random Wallpaper:** Scans `/usr/share/backgrounds` and applies a random wallpaper using KDE Plasma APIs.
*   **KDE Integration:** Direct links to System Settings.

### 🔧 Engineering (Maintenance)
*   **System Update:** Runs `sudo pacman -Syu` in a secure terminal window.
*   **Cache Cleaner:** Frees up disk space.
*   **Orphan Remover:** Smart script that checks for unused dependencies (`pacman -Qtdq`) before attempting removal.

---

## 🛠️ System Requirements

Since this app interacts deeply with the system, it requires the following environment:

*   **OS:** Arch Linux (or Arch-based derivatives).
*   **Desktop Environment:** KDE Plasma (required for wallpaper switching).
*   **Terminal:** `konsole` (Required for command execution).
*   **Video Drivers:** `libmpv` (Required for video background).

### Dependencies
Ensure these system packages are installed before running:

```bash
sudo pacman -S  konsole mpv libmpv base-devel git && yay -S flutter
```

---

## 🚀 Installation & Build

### 1. Clone the Repository
```bash
git clone https://github.com/your-username/bal-helper.git
cd bal-helper
```

### 2. Install Dart Dependencies
```bash
flutter pub get
```
### 3. Run in Debug Mode
```bash
flutter run -d linux
```

### 4. Build for Release
To create the standalone executable for the distro:
```bash
flutter build linux --release
```

### 4.1 Build for Arch linux based distro
```bash
bash dist/binary_build.sh
```

The binary will be located at: `build/linux/x64/release/bundle/bal_helper`

---

## 📂 Project Structure

```text
bal-helper/
├── assets/
│   └── video/
│       └── bg_loop.mp4    # The main background animation
├── lib/
│   ├── main.dart          # Main application logic
│   └── ...
├── linux/                 # Linux-specific runner configuration
├── pubspec.yaml           # Dependency management
└── README.md
```

---

## 🧩 Technical Details

### Secure Command Execution
Unlike standard exec commands, BAL Helper uses `Process.run` to launch a visible **Konsole** window.
*   **Why?** This allows the user to securely enter their `sudo` password in a native environment.
*   **Feedback:** The terminal remains open after execution so the user can verify success or failure.

### Linux Locale Fix
Includes a native C-interop fix (`fixLinuxLocale`) to prevent crashes on non-standard locale configurations common in fresh Linux installs.

---

## 📝 License

This project is open-source. Feel free to modify it for your own Sensei experience!

---

> *Developed by minhmc2007 or [Minhmc2077] for the Blue Archive Linux Project.*
