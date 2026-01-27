# API Documentation

## Base URL

```
Development: http://localhost:3000/api
Production: https://api.barbershop.com/api
```

## Authentication

All authenticated endpoints require a JWT token in the Authorization header:

```
Authorization: Bearer <your_jwt_token>
```

## Response Format

### Success Response

```json
{
  "success": true,
  "data": { ... }
}
```

### Error Response

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error message",
    "details": { ... }
  }
}
```

## Endpoints

### Authentication

#### POST /auth/register

Register a new user.

**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "securepassword",
  "firstName": "John",
  "lastName": "Doe",
  "role": "customer",
  "phone": "+1234567890"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "userId": 1,
    "token": "eyJhbGciOiJIUzI1NiIs..."
  }
}
```

#### POST /auth/login

Authenticate a user.

**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "securepassword"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIs...",
    "user": {
      "id": 1,
      "email": "user@example.com",
      "role": "customer"
    }
  }
}
```

### Stylists

#### GET /stylists

Get all stylists.

**Query Parameters:**
- `page` (optional): Page number (default: 1)
- `limit` (optional): Items per page (default: 10)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "userId": 5,
      "firstName": "Jane",
      "lastName": "Smith",
      "specialization": "Classic Cuts",
      "rating": 4.8,
      "experienceYears": 5,
      "profileImageUrl": "/images/jane.jpg"
    }
  ]
}
```

#### GET /stylists/:id

Get stylist details.

**Response:**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "userId": 5,
    "firstName": "Jane",
    "lastName": "Smith",
    "specialization": "Classic Cuts",
    "rating": 4.8,
    "experienceYears": 5,
    "bio": "Passionate stylist with 5 years experience",
    "profileImageUrl": "/images/jane.jpg",
    "services": [
      {
        "id": 1,
        "name": "Classic Haircut",
        "price": 25.00
      }
    ]
  }
}
```

#### GET /stylists/:id/availability

Get stylist availability.

**Query Parameters:**
- `date` (required): Date in YYYY-MM-DD format

**Response:**
```json
{
  "success": true,
  "data": {
    "date": "2026-01-28",
    "availableSlots": [
      {
        "startTime": "09:00",
        "endTime": "09:30"
      },
      {
        "startTime": "10:00",
        "endTime": "10:30"
      }
    ]
  }
}
```

### Services

#### GET /services

Get all services.

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "name": "Classic Haircut",
      "description": "Traditional barbershop haircut",
      "category": "haircut",
      "basePrice": 25.00,
      "durationMinutes": 30,
      "imageUrl": "/images/classic-cut.jpg"
    }
  ]
}
```

### Appointments

#### GET /appointments

Get appointments.

**Query Parameters:**
- `customerId` (optional): Filter by customer
- `stylistId` (optional): Filter by stylist
- `status` (optional): Filter by status
- `date` (optional): Filter by date

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "customerId": 2,
      "stylistId": 1,
      "serviceId": 1,
      "appointmentDate": "2026-01-28",
      "startTime": "10:00",
      "endTime": "10:30",
      "status": "confirmed",
      "customer": {
        "firstName": "John",
        "lastName": "Doe"
      },
      "stylist": {
        "firstName": "Jane",
        "lastName": "Smith"
      },
      "service": {
        "name": "Classic Haircut",
        "price": 25.00
      }
    }
  ]
}
```

#### POST /appointments

Create a new appointment.

**Request Body:**
```json
{
  "customerId": 2,
  "stylistId": 1,
  "serviceId": 1,
  "appointmentDate": "2026-01-28",
  "startTime": "10:00",
  "notes": "First time customer"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "appointmentDate": "2026-01-28",
    "startTime": "10:00",
    "status": "pending"
  }
}
```

#### PATCH /appointments/:id/status

Update appointment status.

**Request Body:**
```json
{
  "status": "confirmed"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Appointment status updated"
}
```

### AI Recommendations

#### POST /ai/recommend

Get AI hairstyle recommendations.

**Request Body:**
```json
{
  "customerId": 2,
  "faceImage": "base64_encoded_image_data"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "customerId": 2,
    "faceShape": "oval",
    "recommendations": [
      {
        "styleName": "Classic Fade",
        "imageUrl": "/images/classic-fade.jpg",
        "confidenceScore": 0.92,
        "feasibilityScore": 0.88,
        "description": "A versatile style that suits your face shape"
      }
    ]
  }
}
```

#### POST /ai/analyze-face

Analyze face shape from image.

**Request Body:**
```json
{
  "image": "base64_encoded_image_data"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "faceShape": "oval",
    "confidence": 0.89,
    "facialFeatures": {
      "foreheadWidth": 0.75,
      "cheekboneWidth": 0.80,
      "jawlineWidth": 0.70,
      "faceLength": 1.0
    }
  }
}
```

### Reviews

#### POST /reviews

Create a review.

**Request Body:**
```json
{
  "appointmentId": 1,
  "customerId": 2,
  "stylistId": 1,
  "rating": 5,
  "comment": "Excellent service!"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "rating": 5,
    "comment": "Excellent service!"
  }
}
```

### Analytics

#### GET /analytics/dashboard

Get dashboard metrics.

**Response:**
```json
{
  "success": true,
  "data": {
    "totalAppointments": 150,
    "totalRevenue": 3750.00,
    "activeCustomers": 75,
    "averageRating": 4.7,
    "topServices": [],
    "recentActivity": []
  }
}
```

## Error Codes

- `VALIDATION_ERROR` - Invalid input data
- `AUTHENTICATION_ERROR` - Invalid credentials
- `AUTHORIZATION_ERROR` - Insufficient permissions
- `NOT_FOUND` - Resource not found
- `CONFLICT` - Resource conflict (e.g., time slot taken)
- `INTERNAL_SERVER_ERROR` - Server error

## Rate Limiting

- 100 requests per minute per IP
- 1000 requests per hour per user

## Versioning

API version is included in the URL: `/api/v1/...`

Current version: v1
