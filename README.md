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

---

### 3️⃣ Build for production

```bash
flutter build web
```

---

### 4️⃣ Deploy to Firebase

```bash
firebase deploy
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
