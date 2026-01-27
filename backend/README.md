# Backend API

REST API backend for the Barbershop Management System.

## Tech Stack

- **Runtime**: Node.js 16+
- **Framework**: Express.js
- **Database**: MySQL 8.0+
- **Authentication**: JWT (JSON Web Tokens)
- **Security**: Helmet, CORS

## Project Structure

```
backend/
├── src/
│   ├── routes/          # API route definitions
│   ├── controllers/     # Request handlers
│   ├── models/          # Database models
│   ├── middleware/      # Custom middleware
│   ├── services/        # Business logic
│   ├── utils/           # Helper functions
│   └── server.js        # Application entry point
├── config/              # Configuration files
├── tests/               # Test files
└── package.json
```

## Setup

### 1. Install Dependencies

```bash
cd backend
npm install
```

### 2. Configure Environment

Create a `.env` file in the backend directory:

```env
# Server Configuration
PORT=3000
NODE_ENV=development

# Database Configuration
DB_HOST=localhost
DB_PORT=3306
DB_NAME=barbershop_db
DB_USER=your_username
DB_PASSWORD=your_password

# JWT Configuration
JWT_SECRET=your_secret_key_here
JWT_EXPIRATION=24h

# AI Service Configuration
AI_SERVICE_URL=http://localhost:5000
AI_API_KEY=your_ai_api_key

# File Upload Configuration
UPLOAD_DIR=uploads
MAX_FILE_SIZE=5242880
```

### 3. Run Database Migrations

```bash
npm run migrate
```

### 4. Start the Server

```bash
# Development
npm run dev

# Production
npm start
```

## API Endpoints

### Authentication
- `POST /api/auth/register` - Register new user
- `POST /api/auth/login` - Login user
- `POST /api/auth/logout` - Logout user
- `GET /api/auth/profile` - Get user profile

### Customers
- `GET /api/customers` - Get all customers (admin)
- `GET /api/customers/:id` - Get customer details
- `PUT /api/customers/:id` - Update customer profile
- `DELETE /api/customers/:id` - Delete customer (admin)

### Stylists
- `GET /api/stylists` - Get all stylists
- `GET /api/stylists/:id` - Get stylist details
- `POST /api/stylists` - Create stylist (admin)
- `PUT /api/stylists/:id` - Update stylist
- `DELETE /api/stylists/:id` - Delete stylist (admin)
- `GET /api/stylists/:id/availability` - Get stylist availability

### Services
- `GET /api/services` - Get all services
- `GET /api/services/:id` - Get service details
- `POST /api/services` - Create service (admin)
- `PUT /api/services/:id` - Update service (admin)
- `DELETE /api/services/:id` - Delete service (admin)

### Appointments
- `GET /api/appointments` - Get appointments
- `GET /api/appointments/:id` - Get appointment details
- `POST /api/appointments` - Create appointment
- `PUT /api/appointments/:id` - Update appointment
- `DELETE /api/appointments/:id` - Cancel appointment
- `PATCH /api/appointments/:id/status` - Update appointment status

### AI Recommendations
- `POST /api/ai/recommend` - Get AI hairstyle recommendations
- `GET /api/ai/recommendations/:customerId` - Get customer's recommendations
- `POST /api/ai/analyze-face` - Analyze face shape from image

### Reviews
- `GET /api/reviews` - Get all reviews
- `GET /api/reviews/stylist/:stylistId` - Get stylist reviews
- `POST /api/reviews` - Create review
- `PUT /api/reviews/:id` - Update review
- `DELETE /api/reviews/:id` - Delete review

### Analytics
- `GET /api/analytics/dashboard` - Get dashboard metrics
- `GET /api/analytics/revenue` - Get revenue reports
- `GET /api/analytics/popular-services` - Get popular services
- `GET /api/analytics/stylist-performance` - Get stylist performance

## Authentication

The API uses JWT for authentication. Include the token in the Authorization header:

```
Authorization: Bearer <your_jwt_token>
```

## Error Handling

API returns consistent error responses:

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error message",
    "details": {}
  }
}
```

## Testing

```bash
npm test
```

## Security Features

- Password hashing with bcrypt
- JWT token-based authentication
- CORS configuration
- Helmet for security headers
- Input validation
- SQL injection prevention
- Rate limiting

## Development

```bash
# Watch mode
npm run dev

# Run tests with coverage
npm test
```

## Production Deployment

1. Set `NODE_ENV=production`
2. Use a process manager (PM2, systemd)
3. Set up reverse proxy (nginx)
4. Enable HTTPS
5. Configure proper logging
6. Set up monitoring

## License

MIT
