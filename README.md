<img src="./assets/logo.png" width="120"/>

# 🌱 2D Montessori App

A modern, scalable Montessori school management web app built using **Flutter + Firebase**, designed with clean architecture, dual authentication flows, and a premium user experience.

---

## 🚀 Overview

The **2D Montessori App** is designed to support school staff with essential daily operations like attendance tracking, while maintaining a clean and intuitive interface inspired by Apple/Stripe design systems.

This project demonstrates:

* 🔐 Secure authentication (OTP-based for production)
* ⚡ Fast development workflow (no-OTP dev mode)
* ☁️ Firebase integration (Auth + Firestore + Hosting)
* 📱 Fully responsive UI (Web + Mobile)
* 🎯 Clean separation between DEV and PROD environments

---

## 🧩 Features

### 🔑 Authentication

* **Production**

  * OTP-based login using Firebase Authentication
  * reCAPTCHA verification for web
  * Secure user session handling
* **Development**

  * No OTP required
  * Direct login using phone number
  * Fetch user from Firestore

---

### 👤 User Management

* Users stored in Firestore (`users` collection)
* Supports:

  * UID-based lookup (PROD)
  * Phone-based lookup fallback (DEV)
* Auto-create user if not exists (PROD)

---

### 📊 Dashboard

* Clean, modern layout
* Responsive design:

  * 🖥 Sidebar navigation (Web)
  * 📱 Bottom navigation (Mobile)
* Displays:

  * User info
  * Quick actions (e.g., Mark Attendance)

---

### ✅ Attendance Module

* One-click attendance marking
* Designed for fast daily usage
* Extendable for reporting & analytics

---

## 🏗 Tech Stack

| Layer      | Technology              |
| ---------- | ----------------------- |
| Frontend   | Flutter (Web + Mobile)  |
| Backend    | Firebase                |
| Auth       | Firebase Authentication |
| Database   | Cloud Firestore         |
| Hosting    | Firebase Hosting        |
| State Mgmt | Riverpod                |

---

## 🔄 Environment Architecture

The app uses **strict separation of DEV and PROD flows**:

### 🧪 DEV Mode

* No OTP
* Login via phone number
* Fetch user directly from Firestore

### 🌍 PROD Mode

* OTP authentication via FirebaseAuth
* Uses UID for user mapping
* Creates user if not found

---

## ⚙️ Running the Project

### 1️⃣ Install dependencies

```bash
flutter pub get
```

---

### 2️⃣ Run in DEV mode

```bash
flutter run -d chrome
```

In this mode, website forms are written straight to the DEV project's Firestore, and only while **Settings → Public form submissions** is on. To send forms without touching DEV, use the emulator (below). See `docs/website_forms.md`.

---

### 2️⃣b Local form submissions (emulators, development only)

To try sending website forms without touching DEV, run the app against the local Firestore emulator. **Everything** the app reads and writes then goes to the emulator on this machine, never to the DEV or production project. Submissions are written directly to Firestore, as in DEV.

```bash
# Terminal 1: the emulators (needs JDK 21), with the proposed forms rules,
# under the app's own project id (so the seed and the app share local data)
PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH" firebase emulators:start \
  --config test/firebase_rules/forms.firebase.json \
  --project montessori-app-95988 --only firestore,auth

# Terminal 2: synthetic data — an active "General Enquiry" form on /pages/privacy,
# and public submissions switched on for the synthetic school
FIRESTORE_EMULATOR_HOST=127.0.0.1:8086 python3 -I test/emulator/seed_local_forms_dev.py seed

# Terminal 3: the app, connected to the emulator
flutter run -d chrome --dart-define=APP_ENV=dev --dart-define=DEPLOY_TARGET=dev \
  --dart-define=FIRESTORE_EMULATOR_HOST=127.0.0.1:8086
```

- **Try it:** open `/pages/privacy`, fill in the form and send it. You get a reference (`WF-…`).
- **See what was saved:** `python3 -I test/emulator/seed_local_forms_dev.py list`.
- **Where data goes:** the emulator keeps it under the app's project ID, locally. Stopping it discards it.
- **Public submissions setting:** visitors can send forms only while **Settings → Public form submissions** is on (off by default; the seed turns it on). See `docs/website_forms.md`.
- **Safety:** `FIRESTORE_EMULATOR_HOST` must be `localhost` or `127.0.0.1`. The app won't start with it and `DEPLOY_TARGET=prod`.
- **Admin screens:** in this mode, admin sign-in still uses the DEV project's Auth. To use the Submissions Inbox locally, the admin's token needs the `role: admin` claim that the proposed rules expect; otherwise use `list` above.

---

### 3️⃣ Build

```bash
# DEV (montessori-app-95988)
flutter build web --release --dart-define=DEPLOY_TARGET=dev --dart-define=APP_ENV=prod
# Production (twod-montessori-prod): only with approval
flutter build web --release --dart-define=DEPLOY_TARGET=prod --dart-define=APP_ENV=prod
```

---

### 4️⃣ Deploy to Firebase

Always name the project: the Firebase CLI's active project may be production.

```bash
# The website (Hosting only)
firebase deploy --only hosting --project montessori-app-95988
```

---

## 🔐 Firebase Setup

Make sure the following are configured:

### Authentication

* Enable **Phone Authentication**
* Add your domain under **Authorized Domains**

### Firestore

* Collection: `users`
* Example document:

```json
{
  "phone": "8971422811",
  "role": "staff",
  "isActive": true,
  "createdAt": "timestamp"
}
```

---

## 📁 Project Structure

```
lib/
 ├── core/
 ├── modules/
 │    ├── auth/
 │    ├── dashboard/
 │    ├── attendance/
 ├── shared/
 ├── main.dart
```

---

## 🎯 Design Philosophy

* ✨ Minimal and clean UI
* 📐 Apple / Stripe inspired spacing
* ⚡ Fast interactions
* 📱 Mobile-first responsiveness
* 🔁 Reusable components

---

## 🚧 Future Enhancements

* 📊 Attendance analytics dashboard
* 👨‍🏫 Multi-role support (Admin, Teacher, Parent)
* 📅 Calendar integration
* 🔔 Notifications
* 📱 Native mobile builds (Android / iOS)

---

## 🤝 Contribution

This is an actively evolving project. Contributions, ideas, and improvements are welcome.

---

## 📄 License

This project is currently private and maintained by the author.

---

## 👤 Author

**Sivakesh Raman**
Psychologist | Product Builder | Educator

---

## 💡 Vision

To build a **simple, scalable, and human-centered digital ecosystem for Montessori education**.
