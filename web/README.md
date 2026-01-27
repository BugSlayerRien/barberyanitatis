# Web Application

Admin and receptionist dashboard for the Barbershop Management System.

## Overview

Web-based admin panel for:
- Managing appointments and schedules
- Stylist and service management
- Customer database
- Analytics and reporting
- System configuration

## Tech Stack

- **Frontend**: HTML5, CSS3, JavaScript (ES6+)
- **Framework**: React / Vue.js (recommended)
- **UI Library**: Bootstrap / Material-UI
- **Charts**: Chart.js / D3.js
- **State Management**: Redux / Vuex

## Features

### Dashboard
- Overview metrics (appointments, revenue, customers)
- Real-time appointment status
- Recent activity feed
- Quick actions

### Appointment Management
- Calendar view of all appointments
- Create/edit/cancel appointments
- Status tracking
- Customer check-in

### Stylist Management
- Add/edit stylist profiles
- Manage schedules and availability
- Performance metrics
- Service assignments

### Service Management
- Service catalog management
- Pricing configuration
- Category management
- Active/inactive status

### Customer Management
- Customer database
- Appointment history
- AI recommendation history
- Loyalty program

### Analytics & Reports
- Revenue reports (daily/weekly/monthly)
- Popular services analysis
- Stylist performance metrics
- Customer insights
- Export functionality

## Project Structure

```
web/
├── css/
│   ├── style.css
│   └── dashboard.css
├── js/
│   ├── app.js
│   ├── api.js
│   └── components/
├── images/
├── pages/
│   ├── dashboard.html
│   ├── appointments.html
│   ├── stylists.html
│   ├── services.html
│   ├── customers.html
│   └── analytics.html
├── index.html
└── package.json
```

## Setup

### Option 1: Static HTML/CSS/JS

```bash
cd web
# Open index.html in browser
```

### Option 2: React Application

```bash
npx create-react-app barbershop-admin
cd barbershop-admin
npm start
```

### Option 3: Vue.js Application

```bash
npm create vue@latest barbershop-admin
cd barbershop-admin
npm install
npm run dev
```

## Pages

### 1. Login
- Admin/receptionist authentication
- Role-based access

### 2. Dashboard
- Key metrics overview
- Today's appointments
- Quick stats
- Activity timeline

### 3. Appointments
- Calendar/list view
- Filter by status, stylist, date
- Create new appointments
- Modify existing bookings
- Check-in customers

### 4. Stylists
- Stylist directory
- Add/edit profiles
- Set availability schedules
- View performance stats

### 5. Services
- Service catalog
- Add/edit services
- Pricing management
- Category organization

### 6. Customers
- Customer database
- Search and filter
- View profiles
- Appointment history
- AI recommendations history

### 7. Analytics
- Revenue charts
- Service popularity
- Stylist performance
- Customer trends
- Export reports

### 8. Settings
- System configuration
- User management
- Notification settings
- Business information

## API Integration

```javascript
// js/api.js
const API_BASE_URL = 'http://localhost:3000/api';

async function getAppointments() {
  const response = await fetch(`${API_BASE_URL}/appointments`, {
    headers: {
      'Authorization': `Bearer ${getToken()}`
    }
  });
  return response.json();
}

async function createAppointment(data) {
  const response = await fetch(`${API_BASE_URL}/appointments`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${getToken()}`
    },
    body: JSON.stringify(data)
  });
  return response.json();
}
```

## Authentication

JWT-based authentication with role checking:

```javascript
function checkAuth() {
  const token = localStorage.getItem('authToken');
  if (!token) {
    window.location.href = '/login.html';
  }
}

function getUserRole() {
  const token = localStorage.getItem('authToken');
  // Decode JWT to get role
  return role;
}
```

## Development

```bash
# Using live server
npx live-server web/

# Or with Python
cd web
python -m http.server 8080
```

## Build & Deploy

### Static Files
```bash
# Upload to web server
scp -r web/* user@server:/var/www/html/
```

### React Build
```bash
npm run build
# Deploy build/ directory
```

### Vue Build
```bash
npm run build
# Deploy dist/ directory
```

## Security

- HTTPS only in production
- JWT token validation
- Role-based access control
- Input sanitization
- CSRF protection

## Browser Support

- Chrome (latest)
- Firefox (latest)
- Safari (latest)
- Edge (latest)

## License

MIT
