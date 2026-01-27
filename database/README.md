# Database Setup

This directory contains the MySQL database schema, migrations, and seed data for the Barbershop Management System.

## Structure

- `schemas/` - Complete database schema definitions
- `migrations/` - Database migration scripts for version control
- `seeds/` - Sample data for testing and development

## Quick Start

### 1. Install MySQL

Ensure MySQL 8.0+ is installed on your system.

```bash
# Ubuntu/Debian
sudo apt-get install mysql-server

# macOS
brew install mysql

# Windows
# Download from https://dev.mysql.com/downloads/mysql/
```

### 2. Create Database

```bash
mysql -u root -p < schemas/barbershop_schema.sql
```

### 3. Configure Connection

Create a `.env` file in the backend directory with your database credentials:

```
DB_HOST=localhost
DB_PORT=3306
DB_NAME=barbershop_db
DB_USER=your_username
DB_PASSWORD=your_password
```

## Database Schema Overview

### Core Tables

#### Users & Authentication
- `users` - Base user authentication and profile
- `customers` - Customer-specific data and preferences
- `stylists` - Stylist profiles and settings

#### Services & Appointments
- `services` - Service catalog with pricing
- `stylist_services` - Stylist-service associations
- `appointments` - Booking and scheduling
- `working_hours` - Stylist availability schedules

#### AI Features
- `ai_recommendations` - AI-generated hairstyle recommendations
- Face shape detection results
- Feasibility scores and confidence metrics

#### Business Operations
- `reviews` - Customer reviews and ratings
- `payments` - Payment tracking and processing
- `notifications` - System notifications
- `analytics_events` - Business analytics tracking

## Migrations

To run migrations:

```bash
# Example using migration tool
npm run migrate:up

# Or manually
mysql -u root -p barbershop_db < migrations/001_initial_schema.sql
```

## Seed Data

Load sample data for development:

```bash
mysql -u root -p barbershop_db < seeds/sample_data.sql
```

## Backup & Restore

### Backup
```bash
mysqldump -u root -p barbershop_db > backup_$(date +%Y%m%d).sql
```

### Restore
```bash
mysql -u root -p barbershop_db < backup_20260127.sql
```

## Performance Optimization

The schema includes:
- Proper indexing on frequently queried columns
- Foreign key constraints for data integrity
- Optimized data types for storage efficiency

## Security Considerations

- Passwords are stored as hashes (never plain text)
- User roles for access control
- Foreign key constraints prevent orphaned data
- Timestamps for audit trails
