--  LOCATIONS

CREATE TABLE locations (
    locationID INT AUTO_INCREMENT PRIMARY KEY,
    locationName VARCHAR(100) NOT NULL,
    allowAppointments BOOLEAN DEFAULT FALSE,
    allowWalkIns BOOLEAN DEFAULT TRUE,
    isActive BOOLEAN DEFAULT TRUE
);

--  KIOSK

CREATE TABLE kioskDevices (
    kioskID INT AUTO_INCREMENT PRIMARY KEY,
    locationID INT NOT NULL,
    deviceIdentifier VARCHAR(100) UNIQUE NOT NULL,
    isActive BOOLEAN DEFAULT TRUE,
    lastHeartbeat TIMESTAMP NULL,
    FOREIGN KEY (locationID) REFERENCES locations(locationID)
);

-- USERS & ACCESS CONTROL

CREATE TABLE users (
    userID INT AUTO_INCREMENT PRIMARY KEY,
    fullName VARCHAR(150) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    passwordHash VARCHAR(255),
    phone VARCHAR(20),
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE roles (
    roleID INT AUTO_INCREMENT PRIMARY KEY,
    roleName VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE userRoles (
    userRoleID INT AUTO_INCREMENT PRIMARY KEY,
    userID INT NOT NULL,
    roleID INT NOT NULL,
    FOREIGN KEY (userID) REFERENCES users(userID),
    FOREIGN KEY (roleID) REFERENCES roles(roleID)
);

-- BARBERS AS RESOURCES (NOT USERS)

CREATE TABLE barbers (
    barberID INT AUTO_INCREMENT PRIMARY KEY,
    fullName VARCHAR(150) NOT NULL,
    isActive BOOLEAN DEFAULT TRUE
);

-- SERVICES & HAIRCUTS

CREATE TABLE services (
    serviceID INT AUTO_INCREMENT PRIMARY KEY,
    serviceName VARCHAR(100) NOT NULL,
    durationMinutes INT NOT NULL,
    price DECIMAL(10,2) NOT NULL
);

CREATE TABLE haircuts (
    haircutID INT AUTO_INCREMENT PRIMARY KEY,
    haircutName VARCHAR(100) NOT NULL,
    description TEXT
);

-- PRE-GENERATED AI HAIRSTYLE VARIANTS (TOKEN SAVER)

CREATE TABLE hairstyleVariants (
    variantID INT AUTO_INCREMENT PRIMARY KEY,
    haircutID INT NOT NULL,
    faceShape VARCHAR(50),
    hairType VARCHAR(50),
    imagePath VARCHAR(255),
    FOREIGN KEY (haircutID) REFERENCES haircuts(haircutID)
);

-- USER FAVORITES

CREATE TABLE favorites (
    favoriteID INT AUTO_INCREMENT PRIMARY KEY,
    userID INT NOT NULL,
    haircutID INT,
    barberID INT,
    FOREIGN KEY (userID) REFERENCES users(userID),
    FOREIGN KEY (haircutID) REFERENCES haircuts(haircutID),
    FOREIGN KEY (barberID) REFERENCES barbers(barberID)
);

-- SCHEDULING TEMPLATES

CREATE TABLE scheduleTemplates (
    templateID INT AUTO_INCREMENT PRIMARY KEY,
    dayOfWeek ENUM('Mon','Tue','Wed','Thu','Fri','Sat','Sun') NOT NULL,
    startTime TIME NOT NULL,
    endTime TIME NOT NULL
);

CREATE TABLE barberScheduleTemplates (
    barberScheduleID INT AUTO_INCREMENT PRIMARY KEY,
    barberID INT NOT NULL,
    templateID INT NOT NULL,
    FOREIGN KEY (barberID) REFERENCES barbers(barberID),
    FOREIGN KEY (templateID) REFERENCES scheduleTemplates(templateID)
);

-- LEAVES & HOLIDAYS

CREATE TABLE barberLeaves (
    leaveID INT AUTO_INCREMENT PRIMARY KEY,
    barberID INT NOT NULL,
    startDate DATE NOT NULL,
    endDate DATE NOT NULL,
    reason VARCHAR(255),
    FOREIGN KEY (barberID) REFERENCES barbers(barberID)
);

CREATE TABLE shopClosures (
    closureID INT AUTO_INCREMENT PRIMARY KEY,
    closureDate DATE NOT NULL,
    reason VARCHAR(255)
);

-- APPOINTMENTS (MOBILE APP)

CREATE TABLE appointments (
    appointmentID INT AUTO_INCREMENT PRIMARY KEY,
    userID INT NOT NULL,
    serviceID INT NOT NULL,
    appointmentDate DATE NOT NULL,
    startTime TIME NOT NULL,
    endTime TIME NOT NULL,
    status ENUM('Scheduled','Completed','Cancelled','NoShow') DEFAULT 'Scheduled',
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (userID) REFERENCES users(userID),
    FOREIGN KEY (serviceID) REFERENCES services(serviceID)
);

-- MULTIPLE PEOPLE PER APPOINTMENT (ANONYMOUS DEPENDENTS)

CREATE TABLE appointmentParticipants (
    participantID INT AUTO_INCREMENT PRIMARY KEY,
    appointmentID INT NOT NULL,
    participantType ENUM('Adult','Child') NOT NULL,
    FOREIGN KEY (appointmentID) REFERENCES appointments(appointmentID)
);

-- MULTIPLE BARBERS PER APPOINTMENT

CREATE TABLE appointmentBarbers (
    appointmentBarberID INT AUTO_INCREMENT PRIMARY KEY,
    appointmentID INT NOT NULL,
    barberID INT NOT NULL,
    FOREIGN KEY (appointmentID) REFERENCES appointments(appointmentID),
    FOREIGN KEY (barberID) REFERENCES barbers(barberID)
);

-- WALK-INS (KIOSK ONLY)

CREATE TABLE walkIns (
    walkInID INT AUTO_INCREMENT PRIMARY KEY,
    serviceID INT NOT NULL,
    participantCount INT NOT NULL,
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (serviceID) REFERENCES services(serviceID)
);

-- FIFO QUEUE (APPOINTMENTS + WALK-INS)

CREATE TABLE appointmentQueue (
    queueID INT AUTO_INCREMENT PRIMARY KEY,
    appointmentID INT,
    walkInID INT,
    queueNumber INT NOT NULL,
    status ENUM('Waiting','InProgress','Completed') DEFAULT 'Waiting'
);

-- PAYMENTS (SINGLE PAYMENT, PARTIAL REFUND ONLY)

CREATE TABLE payments (
    paymentID INT AUTO_INCREMENT PRIMARY KEY,
    appointmentID INT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    status ENUM('Paid','Refunded') NOT NULL,
    refundAmount DECIMAL(10,2),
    FOREIGN KEY (appointmentID) REFERENCES appointments(appointmentID)
);

-- FEEDBACK

CREATE TABLE feedback (
    feedbackID INT AUTO_INCREMENT PRIMARY KEY,
    appointmentID INT NOT NULL,
    rating INT CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    FOREIGN KEY (appointmentID) REFERENCES appointments(appointmentID)
);

-- NOTIFICATIONS

CREATE TABLE notifications (
    notificationID INT AUTO_INCREMENT PRIMARY KEY,
    userID INT NOT NULL,
    message TEXT,
    isRead BOOLEAN DEFAULT FALSE,
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (userID) REFERENCES users(userID)
);

-- DEVICE TOKENS (MOBILE PUSH)

CREATE TABLE deviceTokens (
    tokenID INT AUTO_INCREMENT PRIMARY KEY,
    userID INT,
    deviceToken VARCHAR(255),
    deviceType VARCHAR(50),
    FOREIGN KEY (userID) REFERENCES users(userID)
);

-- SYSTEM / AI / KIOSK SETTINGS

CREATE TABLE adminSettings (
    settingKey VARCHAR(100) PRIMARY KEY,
    settingValue VARCHAR(255)
);
