# 🔐 Password Manager Pro

A secure, cross-platform password manager built with Flutter.

## ✨ Features

| Feature | Detail |
|---|---|
| Encryption | AES-256-CBC with PBKDF2 key derivation (10 000 iterations) |
| Master Password | Never stored — used only to derive the encryption key |
| Cross-platform | Windows · Ubuntu Linux · Android (single codebase) |
| Sync | Encrypted GitHub Gist — no custom server needed |
| Storage | SQLite (encrypted per-row) |
| Secure storage | PAT / salt / verifier in OS Keychain / Keystore / libsecret |
| Password gen | 14–18 chars, strength indicator (Weak / Medium / Strong) |
| Fields | Website, Password, URL, Email/Username, API Key |
| Export | CSV · JSON backup |

---

## 🚀 Quick Start

### Prerequisites

```
Flutter ≥ 3.19.0  (dart ≥ 3.0.0)
```

### 1 — Install Flutter

Follow https://flutter.dev/docs/get-started/install for your OS.

### 2 — Clone / copy this project

```bash
cd password_manager_pro
flutter pub get
```

### 3 — Run

```bash
# Android (connected device or emulator)
flutter run

# Windows
flutter run -d windows

# Linux
flutter run -d linux
```

### 4 — Build release binaries

```bash
# Android APK
flutter build apk --release

# Windows installer
flutter build windows --release

# Linux bundle
flutter build linux --release
```

---

## 🔄 GitHub Gist Sync — Setup

1. Go to **github.com/settings/tokens** → *Generate new token (classic)*
2. Enable only the **`gist`** scope
3. Copy the token (`ghp_…`)
4. Open the app → **Settings → Gist Sync**
5. Paste the PAT and tap **Save Settings**
6. Tap **Test & Push** — a private Gist is created automatically
7. Copy the **Gist ID** shown and paste it into Settings on your other devices
   *(Each device needs its own PAT; the Gist ID is shared)*

### How sync works

```
PUSH  →  Encrypt all credentials (AES-256) → PATCH Gist file
PULL  →  GET Gist file → Decrypt → Merge by modifiedAt per entry
AUTO  →  Pull on app launch · Push after every save
MANUAL→  Settings → Full Sync (pull + push)
```

> **Security note:** The Gist contains only an encrypted blob.
> GitHub cannot read your credentials even if someone accesses the Gist URL.

---

## 🏗️ Project Structure

```
lib/
├── main.dart                        # Entry point, platform FFI init
├── theme/
│   └── app_theme.dart               # Dark colour palette
├── models/
│   └── credential.dart              # Data model + JSON serialisation
├── services/
│   ├── encryption_service.dart      # AES-256 + PBKDF2 (singleton)
│   ├── storage_service.dart         # SQLite CRUD + merge logic
│   └── gist_service.dart            # GitHub Gist REST API
└── screens/
    ├── master_password_screen.dart  # Vault setup / unlock
    ├── home_screen.dart             # Two-column layout + sidebar
    ├── credential_form_screen.dart  # Create / edit credential
    └── settings_screen.dart        # Gist config, export, backup
```

---

## 📦 Key Dependencies

| Package | Purpose |
|---|---|
| `encrypt` | AES-256-CBC cipher |
| `crypto` | HMAC-SHA256 for PBKDF2 |
| `flutter_secure_storage` | Keychain / Keystore / libsecret |
| `sqflite` + `sqflite_common_ffi` | SQLite (Android + desktop) |
| `http` | GitHub Gist REST API |
| `uuid` | Stable credential IDs |

---

## 🐧 Linux Notes

`flutter_secure_storage` on Linux requires **libsecret**:

```bash
sudo apt install libsecret-1-dev
```

Also add to `linux/CMakeLists.txt`:
```cmake
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)
pkg_check_modules(SECRET REQUIRED IMPORTED_TARGET libsecret-1)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::SECRET)
```

---

## 🪟 Windows Notes

`flutter_secure_storage` uses the Windows Credential Manager — no extra setup needed.

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Ctrl + S` | Save credential (in form) |
| `Ctrl + G` | Generate password (in form) |
| `Tab` | Navigate between fields |
| `Enter` | Submit dialogs |

---

## ⚠️ CSV / JSON Export Warning

Exported files are **unencrypted**. Store them securely (encrypted drive, etc.) and delete them after use.
