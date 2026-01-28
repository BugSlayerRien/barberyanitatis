-- Seed roles and admin user
-- NOTE: Replace the password hash with a real bcrypt hash.
-- Generate with PHP: php -r "echo password_hash('Admin@123', PASSWORD_BCRYPT);"

INSERT INTO roles (roleName) VALUES ('Admin'), ('Receptionist'), ('Customer')
ON DUPLICATE KEY UPDATE roleName = VALUES(roleName);

-- Replace <<BCRYPT_HASH>> with the generated hash.
INSERT INTO users (fullName, email, passwordHash, phone)
VALUES ('System Admin', 'admin@barberyanitatis.com', '<<BCRYPT_HASH>>', '');

INSERT INTO userRoles (userID, roleID)
SELECT u.userID, r.roleID
FROM users u
JOIN roles r ON r.roleName = 'Admin'
WHERE u.email = 'admin@barberyanitatis.com'
ON DUPLICATE KEY UPDATE roleID = VALUES(roleID);
