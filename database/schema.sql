1. USERS & ACCESS CONTROL
CREATE TABLE users (
    userID INT AUTO_INCREMENT PRIMARY KEY,
    fullName VARCHAR(150) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    passwordHash VARCHAR(255) NOT NULL,
    isActive TINYINT(1) DEFAULT 1,
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
    assignedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (userID) REFERENCES users(userID),
    FOREIGN KEY (roleID) REFERENCES roles(roleID)
);

2. BARBERSHOP DOMAIN
CREATE TABLE barbers (
    barberID INT AUTO_INCREMENT PRIMARY KEY,
    userID INT NOT NULL,
    isAvailable TINYINT(1) DEFAULT 1,
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (userID) REFERENCES users(userID)
);

CREATE TABLE barberProfiles (
    profileID INT AUTO_INCREMENT PRIMARY KEY,
    barberID INT NOT NULL,
    bio TEXT,
    experienceYears INT,
    rating DECIMAL(2,1) DEFAULT 0,
    FOREIGN KEY (barberID) REFERENCES barbers(barberID)
);

CREATE TABLE serviceCategories (
    categoryID INT AUTO_INCREMENT PRIMARY KEY,
    categoryName VARCHAR(100) NOT NULL
);

CREATE TABLE services (
    serviceID INT AUTO_INCREMENT PRIMARY KEY,
    categoryID INT NOT NULL,
    serviceName VARCHAR(150) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    durationMinutes INT NOT NULL,
    isActive TINYINT(1) DEFAULT 1,
    FOREIGN KEY (categoryID) REFERENCES serviceCategories(categoryID)
);

CREATE TABLE haircuts (
    haircutID INT AUTO_INCREMENT PRIMARY KEY,
    haircutName VARCHAR(150) NOT NULL,
    faceShape VARCHAR(50),
    description TEXT,
    imageUrl VARCHAR(255)
);

3. CUSTOMER INTERACTION
CREATE TABLE favorites (
    favoriteID INT AUTO_INCREMENT PRIMARY KEY,
    userID INT NOT NULL,
    haircutID INT,
    barberID INT,
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (userID) REFERENCES users(userID),
    FOREIGN KEY (haircutID) REFERENCES haircuts(haircutID),
    FOREIGN KEY (barberID) REFERENCES barbers(barberID)
);

CREATE TABLE feedback (
    feedbackID INT AUTO_INCREMENT PRIMARY KEY,
    userID INT NOT NULL,
    barberID INT NOT NULL,
    rating INT CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (userID) REFERENCES users(userID),
    FOREIGN KEY (barberID) REFERENCES barbers(barberID)
);

CREATE TABLE notifications (
    notificationID INT AUTO_INCREMENT PRIMARY KEY,
    userID INT NOT NULL,
    message TEXT NOT NULL,
    isRead TINYINT(1) DEFAULT 0,
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (userID) REFERENCES users(userID)
);

4. APPOINTMENT & WALK-IN FLOW (UNIFIED)
CREATE TABLE appointments (
    appointmentID INT AUTO_INCREMENT PRIMARY KEY,
    userID INT NOT NULL,
    barberID INT,
    appointmentType ENUM('APPOINTMENT','WALKIN') NOT NULL,
    appointmentDate DATE NOT NULL,
    appointmentTime TIME,
    status ENUM('WAITING','IN_CONSULTATION','COMPLETED','CANCELLED','REJECTED') DEFAULT 'WAITING',
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (userID) REFERENCES users(userID),
    FOREIGN KEY (barberID) REFERENCES barbers(barberID)
);

CREATE TABLE appointmentServices (
    appointmentServiceID INT AUTO_INCREMENT PRIMARY KEY,
    appointmentID INT NOT NULL,
    serviceID INT NOT NULL,
    FOREIGN KEY (appointmentID) REFERENCES appointments(appointmentID),
    FOREIGN KEY (serviceID) REFERENCES services(serviceID)
);

CREATE TABLE scheduleTemplates (
    templateID INT AUTO_INCREMENT PRIMARY KEY,
    barberID INT NOT NULL,
    dayOfWeek ENUM('MON','TUE','WED','THU','FRI','SAT','SUN'),
    startTime TIME,
    endTime TIME,
    slotDuration INT,
    FOREIGN KEY (barberID) REFERENCES barbers(barberID)
);

CREATE TABLE walkInQueue (
    queueID INT AUTO_INCREMENT PRIMARY KEY,
    appointmentID INT NOT NULL,
    queueNumber INT NOT NULL,
    FOREIGN KEY (appointmentID) REFERENCES appointments(appointmentID)
);

5. PAYMENTS
CREATE TABLE payments (
    paymentID INT AUTO_INCREMENT PRIMARY KEY,
    appointmentID INT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    paymentStatus ENUM('PENDING','PAID','FAILED') DEFAULT 'PENDING',
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (appointmentID) REFERENCES appointments(appointmentID)
);

CREATE TABLE transactions (
    transactionID INT AUTO_INCREMENT PRIMARY KEY,
    paymentID INT NOT NULL,
    referenceNo VARCHAR(100),
    transactionDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (paymentID) REFERENCES payments(paymentID)
);

6. SYSTEM & SECURITY
CREATE TABLE auditLogs (
    logID INT AUTO_INCREMENT PRIMARY KEY,
    userID INT,
    tableChanged VARCHAR(100),
    columnChanged VARCHAR(100),
    oldValue TEXT,
    newValue TEXT,
    action VARCHAR(50),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE deviceTokens (
    tokenID INT AUTO_INCREMENT PRIMARY KEY,
    userID INT NOT NULL,
    deviceToken VARCHAR(255) NOT NULL,
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (userID) REFERENCES users(userID)
);

CREATE TABLE kioskDevices (
    kioskID INT AUTO_INCREMENT PRIMARY KEY,
    deviceName VARCHAR(100),
    isActive TINYINT(1) DEFAULT 1,
    registeredAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

7. CONFIGURATION & REFERENCES
CREATE TABLE systemConfig (
    configID INT AUTO_INCREMENT PRIMARY KEY,
    configKey VARCHAR(100) UNIQUE NOT NULL,
    configValue VARCHAR(255) NOT NULL
);

CREATE TABLE referenceTables (
    referenceID INT AUTO_INCREMENT PRIMARY KEY,
    referenceType VARCHAR(100),
    referenceValue VARCHAR(100)
);
