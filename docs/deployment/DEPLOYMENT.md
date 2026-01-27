# Deployment Guide

## Prerequisites

- Server with Ubuntu 20.04+ or similar Linux distribution
- Domain name configured
- SSL certificate
- Access to server via SSH

## Components to Deploy

1. MySQL Database
2. Backend API (Node.js)
3. AI Service (Python)
4. Web Application
5. Mobile Application

## 1. Database Deployment

### Option A: Self-Hosted MySQL

```bash
# Install MySQL
sudo apt update
sudo apt install mysql-server

# Secure installation
sudo mysql_secure_installation

# Create database and user
sudo mysql
CREATE DATABASE barbershop_db;
CREATE USER 'barbershop_user'@'localhost' IDENTIFIED BY 'secure_password';
GRANT ALL PRIVILEGES ON barbershop_db.* TO 'barbershop_user'@'localhost';
FLUSH PRIVILEGES;

# Import schema
mysql -u barbershop_user -p barbershop_db < database/schemas/barbershop_schema.sql
```

### Option B: Managed Database (AWS RDS, DigitalOcean, etc.)

1. Create MySQL instance in cloud provider
2. Configure security groups
3. Import schema
4. Note connection details

## 2. Backend API Deployment

### Prepare Server

```bash
# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# Install PM2 for process management
sudo npm install -g pm2

# Create app directory
sudo mkdir -p /var/www/barbershop-api
sudo chown $USER:$USER /var/www/barbershop-api
```

### Deploy Application

```bash
cd /var/www/barbershop-api

# Clone repository
git clone <repository-url> .
cd backend

# Install dependencies
npm install --production

# Create .env file
cat > .env << EOF
PORT=3000
NODE_ENV=production
DB_HOST=localhost
DB_PORT=3306
DB_NAME=barbershop_db
DB_USER=barbershop_user
DB_PASSWORD=secure_password
JWT_SECRET=your_secret_key_here
JWT_EXPIRATION=24h
AI_SERVICE_URL=http://localhost:5000
EOF

# Start with PM2
pm2 start src/server.js --name barbershop-api
pm2 save
pm2 startup
```

### Configure Nginx as Reverse Proxy

```bash
# Install Nginx
sudo apt install nginx

# Create Nginx configuration
sudo nano /etc/nginx/sites-available/barbershop-api

# Add configuration:
server {
    listen 80;
    server_name api.yourdomain.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}

# Enable site
sudo ln -s /etc/nginx/sites-available/barbershop-api /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

### Setup SSL with Let's Encrypt

```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d api.yourdomain.com

# Auto-renewal is configured automatically
```

## 3. AI Service Deployment

```bash
# Install Python and pip
sudo apt install python3 python3-pip python3-venv

# Create directory
sudo mkdir -p /var/www/barbershop-ai
sudo chown $USER:$USER /var/www/barbershop-ai

cd /var/www/barbershop-ai
git clone <repository-url> .
cd ai-models

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Create .env file
cat > .env << EOF
PORT=5000
ENV=production
EOF

# Start with PM2
pm2 start src/app.py --name barbershop-ai --interpreter python3
pm2 save
```

## 4. Web Application Deployment

### Option A: Static Hosting

```bash
# Copy files to web server
sudo mkdir -p /var/www/barbershop-web
sudo cp -r web/* /var/www/barbershop-web/

# Configure Nginx
sudo nano /etc/nginx/sites-available/barbershop-web

# Add configuration:
server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;
    root /var/www/barbershop-web;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}

# Enable and restart
sudo ln -s /etc/nginx/sites-available/barbershop-web /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# Get SSL certificate
sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com
```

### Option B: CDN Deployment (Netlify, Vercel, etc.)

1. Connect repository to hosting service
2. Configure build settings
3. Set environment variables
4. Deploy

## 5. Mobile Application Deployment

### iOS Deployment

1. **Build for iOS:**
```bash
cd mobile
flutter build ios --release
```

2. **Open in Xcode:**
```bash
open ios/Runner.xcworkspace
```

3. **Configure:**
   - Set bundle identifier
   - Configure signing
   - Set version number

4. **Archive and Upload:**
   - Product > Archive
   - Upload to App Store Connect
   - Submit for review

### Android Deployment

1. **Build APK/App Bundle:**
```bash
cd mobile
flutter build appbundle --release
# Or for APK
flutter build apk --release
```

2. **Sign the App:**
   - Create keystore if needed
   - Configure signing in `android/app/build.gradle`

3. **Upload to Play Console:**
   - Go to Google Play Console
   - Create app listing
   - Upload app bundle
   - Submit for review

## 6. Monitoring and Logs

### Setup Logging

```bash
# View PM2 logs
pm2 logs barbershop-api
pm2 logs barbershop-ai

# Setup log rotation
pm2 install pm2-logrotate
```

### Setup Monitoring

```bash
# Install monitoring tools
pm2 install pm2-server-monit

# View monitoring
pm2 monit
```

### Database Backups

```bash
# Create backup script
cat > /home/$USER/backup-db.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/home/$USER/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mysqldump -u barbershop_user -p'secure_password' barbershop_db > $BACKUP_DIR/backup_$TIMESTAMP.sql
find $BACKUP_DIR -name "backup_*.sql" -mtime +7 -delete
EOF

chmod +x /home/$USER/backup-db.sh

# Add to crontab (daily at 2 AM)
crontab -e
# Add: 0 2 * * * /home/$USER/backup-db.sh
```

## 7. Security Checklist

- [ ] Firewall configured (UFW or iptables)
- [ ] SSH key authentication enabled
- [ ] Password authentication disabled
- [ ] Database not exposed to public
- [ ] Environment variables secured
- [ ] SSL certificates installed
- [ ] Regular security updates scheduled
- [ ] Backup system in place
- [ ] Monitoring configured
- [ ] Rate limiting enabled

## 8. Environment Variables

Update production URLs in all applications:

**Backend (.env):**
```env
NODE_ENV=production
DB_HOST=your-db-host
JWT_SECRET=your-strong-secret
```

**Web (js/api.js):**
```javascript
const API_BASE_URL = 'https://api.yourdomain.com/api';
```

**Mobile (lib/config/app_config.dart):**
```dart
static const String apiBaseUrl = 'https://api.yourdomain.com/api';
```

## Troubleshooting

### API not responding
```bash
pm2 status
pm2 logs barbershop-api
sudo systemctl status nginx
```

### Database connection issues
```bash
mysql -u barbershop_user -p
# Check connection
```

### SSL certificate issues
```bash
sudo certbot certificates
sudo certbot renew --dry-run
```

## Scaling Considerations

1. **Load Balancing**: Use multiple API server instances
2. **Database Replication**: Setup master-slave replication
3. **Caching**: Implement Redis for session and API caching
4. **CDN**: Use CDN for static assets
5. **Auto-scaling**: Use cloud auto-scaling for traffic spikes
