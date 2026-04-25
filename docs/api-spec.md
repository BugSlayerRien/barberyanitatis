# Barberya ni Tatis API Spec (PHP + PostgreSQL/Supabase)

## Conventions
- Base URL: /api
- Format: JSON (except image uploads use multipart/form-data)
- Auth: Role-based access control (RBAC) from users/roles/userRoles
- Flutter/web/kiosk must call API; no direct DB access

## Roles
- client (mobile)
- admin (web)
- receptionist (web)
- kiosk (kiosk device)

## Common error responses
- 400: invalid action
- 401: unauthenticated
- 403: forbidden (role)
- 404: not found
- 422: validation error
- 500: server/db error

---

# AUTH

## POST /api/auth.php
### Actions
- register
- login

### Tables
- users, roles, userRoles

### Validation
- email required, valid, unique
- password required (min 8 recommended)
- roleName defaults to Customer

### Request (register)
{
  "action": "register",
  "fullName": "Juan Dela Cruz",
  "email": "juan@email.com",
  "password": "Password123",
  "phone": "0917...",
  "roleName": "Customer"
}

### Response (register)
{
  "message": "Registration successful",
  "user": {
    "userID": 1,
    "fullName": "Juan Dela Cruz",
    "email": "juan@email.com",
    "phone": "0917...",
    "role": "Customer"
  }
}

### Request (login)
{
  "action": "login",
  "email": "juan@email.com",
  "password": "Password123"
}

### Response (login)
{
  "message": "Login successful",
  "user": {
    "userID": 1,
    "fullName": "Juan Dela Cruz",
    "email": "juan@email.com",
    "roles": ["Customer"]
  }
}

---

# USERS

## POST /api/users.php (future)
### Actions
- list (admin/receptionist)
- update (admin)
- deactivate (admin)

### Tables
- users, userRoles, roles

### Validation
- role-based access required
- email uniqueness preserved

---

# SERVICES

## POST /api/services.php (future)
### Actions
- list (all)
- create/update/delete (admin)

### Tables
- services

### Validation
- price > 0, durationMinutes > 0

---

# BARBERS

## POST /api/barbers.php (future)
### Actions
- list (all)
- create/update/deactivate (admin/receptionist)

### Tables
- barbers

---

# HAIRCUTS + VARIANTS

## POST /api/haircuts.php (future)
### Actions
- list (all)
- create/update/delete (admin)

### Tables
- haircuts, hairstyleVariants

---

# AI FACE SCAN

## POST /api/ai_scan.php
### Role
- client (mobile)

### Tables
- hairstyleVariants, haircuts

### Validation
- image required (multipart/form-data)
- AI provider configured via env: AI_PROVIDER, AI_API_KEY

### Request (multipart/form-data)
- image: file
- userID: 1
- faceShape: Oval (optional if AI detects)
- hairType: Straight (optional if AI detects)

### Response
{
  "message": "Scan received",
  "userID": 1,
  "faceShape": "Oval",
  "hairType": "Straight",
  "variants": [
    {"variantID": 10, "imagePath": "/assets/ai/variant10.png", "haircutName": "Textured Crop"}
  ]
}

### Notes
- Mobile captures image and calls this endpoint.
- API should send image to external AI provider (Azure Face API + custom hair model + image generator like Replicate/Stability).
- Results are stored as hairstyleVariants for reuse.

---

# APPOINTMENTS

## POST /api/booking.php
### Actions
- create (client)
- listByCustomer (client)

### Tables
- appointments, services, appointmentBarbers, appointmentParticipants

### Validation
- userID, serviceID, appointmentDate, startTime, endTime required
- barberIDs optional
- participants optional: only "Adult" or "Child"

### Request (create)
{
  "action": "create",
  "userID": 1,
  "serviceID": 2,
  "appointmentDate": "2026-01-30",
  "startTime": "10:00:00",
  "endTime": "11:00:00",
  "barberIDs": [1, 3],
  "participants": ["Adult", "Child"]
}

### Response (create)
{
  "message": "Appointment created",
  "appointmentID": 55
}

### Request (listByCustomer)
{
  "action": "listByCustomer",
  "userID": 1
}

### Response (listByCustomer)
{
  "appointments": [
    {
      "appointmentID": 55,
      "appointmentDate": "2026-01-30",
      "startTime": "10:00:00",
      "endTime": "11:00:00",
      "status": "Scheduled",
      "serviceID": 2,
      "serviceName": "Precision Cut",
      "durationMinutes": 60,
      "price": "350.00",
      "barbers": [
        {"barberID": 1, "fullName": "Miguel Cruz"}
      ]
    }
  ]
}

---

# QUEUE (RECEPTIONIST)

## POST /api/queue.php (future)
### Actions
- enqueue appointment or walkin
- update status (Waiting, InProgress, Completed)

### Tables
- appointmentQueue, appointments, walkIns

---

# WALK-INS (KIOSK)

## POST /api/walkins.php (future)
### Actions
- create (kiosk)
- list (receptionist)

### Tables
- walkIns, appointmentQueue

---

# PAYMENTS

## POST /api/payments.php (future)
### Actions
- create (client/receptionist)
- refund (admin/receptionist)

### Tables
- payments

### Validation
- refundAmount <= amount * 0.5 (business rule)

---

# NOTIFICATIONS

## POST /api/notifications.php (future)
### Actions
- list (client)
- markRead (client)

### Tables
- notifications

---

# DATA FLOW NOTES (MOBILE, WEB, KIOSK)

- Mobile creates appointments -> stored in appointments table -> immediately visible to receptionist (web) and admin analytics.
- Web updates queue status -> affects real-time tracking and analytics across all platforms.
- Kiosk creates walk-ins -> inserted into walkIns + appointmentQueue -> visible to receptionist immediately.
- AI face scan results stored as hairstyleVariants -> mobile can reuse without new AI costs.
- Single database ensures no duplication; all platforms read/write through API only.
