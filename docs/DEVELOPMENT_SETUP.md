# Development Setup Guide

## Overview

This guide will help you set up the complete development environment for the Barbershop Management System.

## Prerequisites

Before starting, ensure you have the following installed:

- **Git**: Version control
- **Node.js**: 16+ (for backend)
- **Python**: 3.8+ (for AI service)
- **MySQL**: 8.0+
- **Flutter SDK**: 3.0+ (for mobile app)
- **Code Editor**: VS Code, Android Studio, or your preferred IDE

## Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd barberyanitatis
```

### 2. Database Setup

```bash
# Start MySQL
# On macOS
brew services start mysql

# On Ubuntu
sudo systemctl start mysql

# Create database and import schema
mysql -u root -p
```

In MySQL console:
```sql
CREATE DATABASE barbershop_db;
USE barbershop_db;
source database/schemas/barbershop_schema.sql;
exit;
```

### 3. Backend API Setup

```bash
cd backend

# Install dependencies
npm install

# Create .env file
cp .env.example .env

# Edit .env with your settings
nano .env

# Start development server
npm run dev
```

The API will be available at `http://localhost:3000`

### 4. AI Service Setup

```bash
cd ai-models

# Create virtual environment
python3 -m venv venv

# Activate virtual environment
# On macOS/Linux
source venv/bin/activate
# On Windows
venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Start the service
python src/app.py
```

The AI service will be available at `http://localhost:5000`

### 5. Mobile App Setup

```bash
cd mobile

# Get Flutter dependencies
flutter pub get

# Run the app
flutter run
```

Or open the project in Android Studio/VS Code and run from there.

### 6. Web App Setup

```bash
cd web

# Option 1: Use any local web server
# Using Python
python -m http.server 8080

# Using Node.js
npx live-server

# Option 2: Open index.html directly in browser
```

The web app will be available at `http://localhost:8080`

## Detailed Setup Instructions

### Environment Variables

#### Backend (.env)

```env
# Server Configuration
PORT=3000
NODE_ENV=development

# Database Configuration
DB_HOST=localhost
DB_PORT=3306
DB_NAME=barbershop_db
DB_USER=root
DB_PASSWORD=your_password

# JWT Configuration
JWT_SECRET=your_dev_secret_key_change_in_production
JWT_EXPIRATION=24h

# AI Service Configuration
AI_SERVICE_URL=http://localhost:5000
AI_API_KEY=dev_api_key

# File Upload Configuration
UPLOAD_DIR=uploads
MAX_FILE_SIZE=5242880
```

#### AI Service (.env)

```env
PORT=5000
ENV=development
MODEL_PATH=models/
```

#### Mobile App (lib/config/app_config.dart)

```dart
class AppConfig {
  static const String apiBaseUrl = 'http://localhost:3000/api';
  static const String aiServiceUrl = 'http://localhost:5000/api';
  static const String appName = 'Barbershop Dev';
}
```

For Android emulator, use `http://10.0.2.2:3000/api` instead of localhost.
For iOS simulator, localhost works fine.

## Testing the Setup

### 1. Test Backend API

```bash
# Health check
curl http://localhost:3000/health

# Test authentication endpoint
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"test123","firstName":"Test","lastName":"User","role":"customer"}'
```

### 2. Test AI Service

```bash
# Health check
curl http://localhost:5000/health

# Test face analysis (requires valid base64 image)
curl -X POST http://localhost:5000/api/analyze-face \
  -H "Content-Type: application/json" \
  -d '{"image":"base64_image_data"}'
```

### 3. Test Mobile App

1. Start the app in an emulator/simulator
2. Navigate through all screens
3. Check console for any errors

### 4. Test Web App

1. Open in browser
2. Open browser console
3. Check for JavaScript errors
4. Try navigating different pages

## Development Workflow

### Making Changes

1. **Create a feature branch**
```bash
git checkout -b feature/your-feature-name
```

2. **Make your changes**
   - Edit code
   - Test locally
   - Commit frequently

3. **Test your changes**
   - Run linters
   - Run tests
   - Manual testing

4. **Push and create PR**
```bash
git push origin feature/your-feature-name
```

### Running Tests

#### Backend Tests
```bash
cd backend
npm test
```

#### AI Service Tests
```bash
cd ai-models
pytest tests/
```

#### Mobile App Tests
```bash
cd mobile
flutter test
```

## Common Issues and Solutions

### Database Connection Error

**Problem**: "Cannot connect to MySQL server"

**Solution**:
```bash
# Check if MySQL is running
sudo systemctl status mysql

# Restart MySQL
sudo systemctl restart mysql

# Verify credentials in .env file
```

### Port Already in Use

**Problem**: "Port 3000 is already in use"

**Solution**:
```bash
# Find process using the port
lsof -i :3000

# Kill the process
kill -9 <PID>

# Or use a different port in .env
```

### Flutter Dependencies Error

**Problem**: "Package dependencies error"

**Solution**:
```bash
cd mobile
flutter clean
flutter pub get
```

### Python Module Not Found

**Problem**: "ModuleNotFoundError"

**Solution**:
```bash
# Make sure virtual environment is activated
source venv/bin/activate

# Reinstall dependencies
pip install -r requirements.txt
```

## IDE Setup

### VS Code Recommended Extensions

- Flutter
- Dart
- Python
- ESLint
- MySQL
- REST Client
- GitLens

### Android Studio Setup

1. Install Flutter plugin
2. Configure Flutter SDK path
3. Setup Android emulator

### Database Tools

- MySQL Workbench
- DBeaver
- phpMyAdmin

## Hot Reload and Auto-Restart

### Backend (with nodemon)
```bash
npm run dev
# Changes to .js files will auto-restart the server
```

### Mobile (Flutter)
```bash
flutter run
# Press 'r' to hot reload
# Press 'R' to hot restart
```

### AI Service (with Flask debug mode)
```bash
python src/app.py
# Auto-reloads on file changes in debug mode
```

## Next Steps

1. Review the [API Documentation](../api/API_DOCUMENTATION.md)
2. Check the [Architecture Guide](../architecture/ARCHITECTURE.md)
3. Read component-specific READMEs in each directory
4. Start developing!

## Getting Help

- Check the documentation
- Review existing code
- Ask team members
- Search for similar issues online

## Contributing

Please follow the coding standards and best practices:
- Write clean, readable code
- Add comments for complex logic
- Write tests for new features
- Follow the existing code style
- Update documentation
