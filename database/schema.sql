-- 1. USERS
CREATE TABLE users (
  userID INT AUTO_INCREMENT PRIMARY KEY,
  fullName VARCHAR(150) NOT NULL,
  email VARCHAR(150),
  passwordHash VARCHAR(255),
  role ENUM('Admin','Barber','Receptionist','Customer') NOT NULL,
  isActive TINYINT(1) DEFAULT 1,
  createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) COMMENT='Stores all system users';

-- 2. ROLES
CREATE TABLE roles (
  roleID INT AUTO_INCREMENT PRIMARY KEY,
  roleName VARCHAR(50) UNIQUE NOT NULL
) COMMENT='Defines system roles';

-- 3. USER ROLES
CREATE TABLE userRoles (
  userRoleID INT AUTO_INCREMENT PRIMARY KEY,
  userID INT NOT NULL,
  roleID INT NOT NULL
) COMMENT='Maps users to roles';

-- 4. BARBERS
CREATE TABLE barbers (
  barberID INT AUTO_INCREMENT PRIMARY KEY,
  userID INT NOT NULL,
  rating DECIMAL(2,1) DEFAULT 0,
  isAvailable TINYINT(1) DEFAULT 1
) COMMENT='Barber profiles linked to users';

-- 5. SERVICES
CREATE TABLE services (
  serviceID INT AUTO_INCREMENT PRIMARY KEY,
  serviceName VARCHAR(100) NOT NULL,
  durationMinutes INT NOT NULL,
  price DECIMAL(10,2) NOT NULL,
  isActive TINYINT(1) DEFAULT 1
) COMMENT='Services offered by the barbershop';

-- 6. SERVICE CATEGORIES
CREATE TABLE serviceCategories (
  categoryID INT AUTO_INCREMENT PRIMARY KEY,
  categoryName VARCHAR(100) NOT NULL
) COMMENT='Groups services into categories';

-- 7. HAIRCUTS
CREATE TABLE haircuts (
  haircutID INT AUTO_INCREMENT PRIMARY KEY,
  haircutName VARCHAR(100) NOT NULL,
  faceShape VARCHAR(50),
  imagePath VARCHAR(255),
  isActive TINYINT(1) DEFAULT 1
) COMMENT='Hairstyle library for AI recommendation';

-- 8. FAVORITES
CREATE TABLE favorites (
  favoriteID INT AUTO_INCREMENT PRIMARY KEY,
  userID INT NOT NULL,
  haircutID INT,
  barberID INT
) COMMENT='User favorite haircuts or barbers';

-- 9. SCHEDULE TEMPLATES
CREATE TABLE scheduleTemplates (
  templateID INT AUTO_INCREMENT PRIMARY KEY,
  barberID INT NOT NULL,
  dayOfWeek ENUM('Mon','Tue','Wed','Thu','Fri','Sat','Sun') NOT NULL,
  startTime TIME NOT NULL,
  endTime TIME NOT NULL
) COMMENT='Recurring barber schedules';

-- 10. SCHEDULE EXCEPTIONS
CREATE TABLE scheduleExceptions (
  exceptionID INT AUTO_INCREMENT PRIMARY KEY,
  barberID INT NOT NULL,
  exceptionDate DATE NOT NULL,
  reason VARCHAR(255)
) COMMENT='Overrides for barber schedules';

-- 11. APPOINTMENTS
CREATE TABLE appointments (
  appointmentID INT AUTO_INCREMENT PRIMARY KEY,
  userID INT NOT NULL,
  barberID INT NOT NULL,
  appointmentDate DATE NOT NULL,
  appointmentTime TIME NOT NULL,
  status ENUM('Scheduled','Cancelled','Rejected','Completed') DEFAULT 'Scheduled',
  createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) COMMENT='Appointments and reserved slots';

-- 12. APPOINTMENT SERVICES
CREATE TABLE appointmentServices (
  appointmentServiceID INT AUTO_INCREMENT PRIMARY KEY,
  appointmentID INT NOT NULL,
  serviceID INT NOT NULL
) COMMENT='Services linked to appointments';

-- 13. WALK-INS
CREATE TABLE walkIns (
  walkInID INT AUTO_INCREMENT PRIMARY KEY,
  customerName VARCHAR(150),
  barberID INT,
  visitDate DATE NOT NULL,
  status ENUM('Waiting','InService','Completed') DEFAULT 'Waiting'
) COMMENT='Tracks walk-in customers';

-- 14. PAYMENTS
CREATE TABLE payments (
  paymentID INT AUTO_INCREMENT PRIMARY KEY,
  appointmentID INT,
  amount DECIMAL(10,2),
  method VARCHAR(50),
  status ENUM('Pending','Paid','Failed') DEFAULT 'Pending',
  createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) COMMENT='Payment records';

-- 15. TRANSACTIONS
CREATE TABLE transactions (
  transactionID INT AUTO_INCREMENT PRIMARY KEY,
  paymentID INT NOT NULL,
  referenceNumber VARCHAR(100),
  processedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) COMMENT='Finalized payment transactions';

-- 16. FEEDBACK
CREATE TABLE feedback (
  feedbackID INT AUTO_INCREMENT PRIMARY KEY,
  appointmentID INT NOT NULL,
  rating INT,
  comment TEXT,
  createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) COMMENT='Customer feedback and ratings';

-- 17. NOTIFICATIONS
CREATE TABLE notifications (
  notificationID INT AUTO_INCREMENT PRIMARY KEY,
  userID INT NOT NULL,
  message TEXT NOT NULL,
  isRead TINYINT(1) DEFAULT 0,
  createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) COMMENT='System notifications';

-- 18. DEVICE TOKENS
CREATE TABLE deviceTokens (
  deviceTokenID INT AUTO_INCREMENT PRIMARY KEY,
  userID INT NOT NULL,
  deviceToken VARCHAR(255) NOT NULL,
  platform VARCHAR(50)
) COMMENT='Push notification device tokens';

-- 19. KIOSK DEVICES
CREATE TABLE kioskDevices (
  kioskID INT AUTO_INCREMENT PRIMARY KEY,
  deviceCode VARCHAR(100) UNIQUE NOT NULL,
  isActive TINYINT(1) DEFAULT 1
) COMMENT='Registered kiosk devices';

-- 20. AI RECOMMENDATIONS
CREATE TABLE aiRecommendations (
  recommendationID INT AUTO_INCREMENT PRIMARY KEY,
  userID INT NOT NULL,
  haircutID INT NOT NULL,
  confidenceScore DECIMAL(5,2),
  createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) COMMENT='AI-generated haircut recommendations';

-- 21. APPOINTMENT STATUS HISTORY
CREATE TABLE appointmentStatusHistory (
  historyID INT AUTO_INCREMENT PRIMARY KEY,
  appointmentID INT NOT NULL,
  oldStatus VARCHAR(50),
  newStatus VARCHAR(50),
  changedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) COMMENT='Tracks appointment status changes';

-- 22. AUDIT LOGS
CREATE TABLE auditLogs (
  logID INT AUTO_INCREMENT PRIMARY KEY,
  userID INT,
  tableChanged VARCHAR(100),
  columnChanged VARCHAR(100),
  oldValue TEXT,
  newValue TEXT,
  action VARCHAR(50),
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) COMMENT='System audit trail';CREATE TABLE users (
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
