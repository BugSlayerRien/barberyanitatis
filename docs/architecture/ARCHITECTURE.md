# Project Architecture

## System Overview

The Barbershop Management System is a multi-platform application consisting of three main components:

1. **Mobile Application (Flutter)** - Customer interface
2. **Web Application** - Admin/Receptionist interface
3. **Backend API** - Central data management and business logic
4. **AI Service** - Computer vision and recommendation engine

## Architecture Diagram

```
┌─────────────────┐      ┌─────────────────┐
│  Mobile App     │      │  Web App        │
│  (Flutter)      │      │  (HTML/JS)      │
└────────┬────────┘      └────────┬────────┘
         │                        │
         │   REST API Calls       │
         └────────┬───────────────┘
                  │
         ┌────────▼────────┐
         │  Backend API    │
         │  (Node.js)      │
         └────────┬────────┘
                  │
         ┌────────┼────────┐
         │        │        │
    ┌────▼───┐ ┌─▼──────┐ ┌▼─────────┐
    │ MySQL  │ │AI Service│ │External │
    │   DB   │ │(Python)  │ │ Services│
    └────────┘ └──────────┘ └──────────┘
```

## Component Details

### Mobile Application (Flutter)

**Purpose**: Customer-facing mobile app for iOS and Android

**Key Features**:
- User authentication and profile management
- AI-powered hairstyle recommendations
- Appointment booking and management
- Service browsing
- Review and rating system

**Technology Stack**:
- Framework: Flutter 3.0+
- State Management: Provider/Riverpod
- HTTP Client: Dio
- Local Storage: Hive

### Web Application

**Purpose**: Administrative dashboard for staff

**Key Features**:
- Dashboard with analytics
- Appointment management
- Stylist and service management
- Customer database
- Reports and analytics

**Technology Stack**:
- Frontend: HTML5, CSS3, JavaScript
- Optional: React/Vue.js
- Charts: Chart.js
- Authentication: JWT

### Backend API

**Purpose**: Central business logic and data management

**Key Features**:
- RESTful API endpoints
- User authentication and authorization
- Database operations
- Business logic processing
- Integration with AI service

**Technology Stack**:
- Runtime: Node.js
- Framework: Express.js
- Database: MySQL 8.0+
- Authentication: JWT
- Security: Helmet, CORS

### Database (MySQL)

**Purpose**: Persistent data storage

**Key Entities**:
- Users (customers, stylists, staff)
- Appointments
- Services
- Reviews
- AI Recommendations
- Analytics Events

**Features**:
- Relational data model
- Foreign key constraints
- Indexing for performance
- Transaction support

### AI Service

**Purpose**: Computer vision and recommendation engine

**Key Features**:
- Face shape detection
- Facial feature analysis
- Hairstyle recommendation algorithm
- Feasibility scoring

**Technology Stack**:
- Framework: Flask/FastAPI
- ML Libraries: TensorFlow/PyTorch
- Computer Vision: OpenCV, dlib
- Face Detection: MediaPipe

## Data Flow

### Appointment Booking Flow

1. Customer opens mobile app
2. App requests available stylists from API
3. API queries database for stylist availability
4. Customer selects stylist, service, and time
5. App sends booking request to API
6. API validates availability and creates appointment
7. Database stores appointment record
8. API sends confirmation to app
9. Notification sent to customer and stylist

### AI Recommendation Flow

1. Customer uploads photo in mobile app
2. App sends image to Backend API
3. Backend forwards to AI Service
4. AI Service analyzes face shape
5. AI Service generates recommendations
6. Recommendations sent back to Backend
7. Backend stores in database
8. Results returned to mobile app
9. Customer views personalized suggestions

## Security Architecture

### Authentication

- JWT-based token authentication
- Password hashing with bcrypt
- Secure token storage
- Token expiration and refresh

### Authorization

- Role-based access control (RBAC)
- Customer, Stylist, Receptionist, Admin roles
- Endpoint-level permissions
- Resource ownership validation

### Data Protection

- HTTPS/TLS encryption in transit
- Database encryption at rest
- Input validation and sanitization
- SQL injection prevention
- XSS protection

## Scalability Considerations

### Horizontal Scaling

- Stateless API servers
- Load balancer ready
- Database connection pooling
- Session management with Redis

### Performance Optimization

- Database query optimization
- Index usage
- API response caching
- Image CDN for media files
- Lazy loading in mobile app

### Monitoring

- Application logging
- Error tracking
- Performance metrics
- Database query monitoring
- API endpoint analytics

## Deployment Architecture

### Development Environment

```
Local Machine
├── Mobile App (Flutter)
├── Web App (Live Server)
├── Backend API (localhost:3000)
├── AI Service (localhost:5000)
└── MySQL Database (localhost:3306)
```

### Production Environment

```
Cloud Infrastructure
├── Mobile App (App Stores)
├── Web App (CDN + Web Server)
├── Backend API (Multiple Instances + Load Balancer)
├── AI Service (Container + Auto-scaling)
└── MySQL Database (Managed Service + Replication)
```

## Technology Choices Rationale

### Why Flutter for Mobile?

- Single codebase for iOS and Android
- Native performance
- Rich UI components
- Strong community support

### Why Node.js for Backend?

- JavaScript ecosystem
- Fast I/O operations
- Large package ecosystem (npm)
- Easy integration with modern tools

### Why MySQL for Database?

- ACID compliance
- Strong relational model
- Mature and stable
- Good performance for structured data
- Wide hosting support

### Why Python for AI?

- Rich ML/AI libraries
- Strong computer vision support
- Easy model deployment
- Fast prototyping

## Future Enhancements

1. Real-time chat between customers and stylists
2. Video consultation feature
3. AR try-on for hairstyles
4. Mobile payment integration
5. Multi-language support
6. Advanced analytics with ML
7. Inventory management for products
8. Loyalty program automation
9. SMS/Email marketing integration
10. Multi-location support
