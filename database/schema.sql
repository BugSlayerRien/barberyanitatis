-- =========================
-- CORE IDENTITY
-- =========================

CREATE TABLE roles (
    roleID INT AUTO_INCREMENT PRIMARY KEY,
    roleName VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE users (
    userID INT AUTO_INCREMENT PRIMARY KEY,
    fullName VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    passwordHash VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    isActive BOOLEAN DEFAULT TRUE,
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE userRoles (
    userID INT NOT NULL,
    roleID INT NOT NULL,
    PRIMARY KEY (userID, roleID),
    FOREIGN KEY (userID) REFERENCES users(userID),
    FOREIGN KEY (roleID) REFERENCES roles(roleID)
);

-- =========================
-- BARBER DOMAIN
-- =========================

CREATE TABLE barbers (
    barberID INT AUTO_INCREMENT PRIMARY KEY,
    userID INT UNIQUE NOT NULL,
    bio TEXT,
    experienceYears INT,
    ratingAverage DECIMAL(3,2) DEFAULT 0.00,
    FOREIGN KEY (userID) REFERENCES users(userID)
);

CREATE TABLE services (
    serviceID INT AUTO_INCREMENT PRIMARY KEY,
    serviceName VARCHAR(100) NOT NULL,
    durationMinutes INT NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    isActive BOOLEAN DEFAULT TRUE
);

CREATE TABLE haircuts (
    haircutID INT AUTO_INCREMENT PRIMARY KEY,
    haircutName VARCHAR(100) NOT NULL,
    description TEXT,
    referenceImage VARCHAR(255)
);

-- =========================
-- FAVORITES
-- =========================

CREATE TABLE favorites (
    favoriteID INT AUTO_INCREMENT PRIMARY KEY,
    userID INT NOT NULL,
    barberID INT NULL,
    haircutID INT NULL,
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (userID) REFERENCES users(userID),
    FOREIGN KEY (barberID) REFERENCES barbers(barberID),
    FOREIGN KEY (haircutID) REFERENCES haircuts(haircutID),
    CHECK (
        (barberID IS NOT NULL AND haircutID IS NULL) OR
        (barberID IS NULL AND haircutID IS NOT NULL)
    )
);

-- =========================
-- SCHEDULING
-- =========================

CREATE TABLE appointments (
    appointmentID INT AUTO_INCREMENT PRIMARY KEY,
    customerID INT NOT NULL,
    barberID INT NOT NULL,
    appointmentDate DATE NOT NULL,
    appointmentTime TIME NOT NULL,
    status ENUM('Scheduled','Completed','Cancelled','Rejected') DEFAULT 'Scheduled',
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customerID) REFERENCES users(userID),
    FOREIGN KEY (barberID) REFERENCES barbers(barberID)
);

CREATE TABLE appointmentServices (
    appointmentID INT NOT NULL,
    serviceID INT NOT NULL,
    PRIMARY KEY (appointmentID, serviceID),
    FOREIGN KEY (appointmentID) REFERENCES appointments(appointmentID),
    FOREIGN KEY (serviceID) REFERENCES services(serviceID)
);

CREATE TABLE scheduleTemplates (
    templateID INT AUTO_INCREMENT PRIMARY KEY,
    barberID INT NOT NULL,
    dayOfWeek ENUM('Mon','Tue','Wed','Thu','Fri','Sat','Sun') NOT NULL,
    startTime TIME NOT NULL,
    endTime TIME NOT NULL,
    FOREIGN KEY (barberID) REFERENCES barbers(barberID)
);

-- =========================
-- PAYMENTS
-- =========================

CREATE TABLE payments (
    paymentID INT AUTO_INCREMENT PRIMARY KEY,
    appointmentID INT NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    method ENUM('Cash','GCash','Card') NOT NULL,
    status ENUM('Pending','Paid','Failed','Refunded') DEFAULT 'Pending',
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (appointmentID) REFERENCES appointments(appointmentID)
);

CREATE TABLE transactions (
    transactionID INT AUTO_INCREMENT PRIMARY KEY,
    paymentID INT NOT NULL,
    referenceCode VARCHAR(100),
    processedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (paymentID) REFERENCES payments(paymentID)
);

-- =========================
-- FEEDBACK
-- =========================

CREATE TABLE feedback (
    feedbackID INT AUTO_INCREMENT PRIMARY KEY,
    appointmentID INT NOT NULL,
    userID INT NOT NULL,
    rating INT CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (appointmentID) REFERENCES appointments(appointmentID),
    FOREIGN KEY (userID) REFERENCES users(userID)
);

-- =========================
-- SYSTEM
-- =========================

CREATE TABLE notifications (
    notificationID INT AUTO_INCREMENT PRIMARY KEY,
    userID INT NOT NULL,
    title VARCHAR(100),
    message TEXT,
    isRead BOOLEAN DEFAULT FALSE,
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (userID) REFERENCES users(userID)
);

CREATE TABLE deviceTokens (
    tokenID INT AUTO_INCREMENT PRIMARY KEY,
    userID INT NOT NULL,
    deviceToken VARCHAR(255) UNIQUE NOT NULL,
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (userID) REFERENCES users(userID)
);

CREATE TABLE auditLogs (
    logID INT AUTO_INCREMENT PRIMARY KEY,
    userID INT,
    tableChanged VARCHAR(100),
    action VARCHAR(50),
    oldValue TEXT,
    newValue TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (userID) REFERENCES users(userID)
);
