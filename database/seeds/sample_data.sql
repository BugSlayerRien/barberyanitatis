-- Sample data for development and testing

USE barbershop_db;

-- Insert sample users
INSERT INTO users (email, password_hash, role, first_name, last_name, phone) VALUES
('admin@barbershop.com', '$2b$10$abcdefghijklmnopqrstuvwxyz', 'admin', 'Admin', 'User', '+1234567890'),
('john.stylist@barbershop.com', '$2b$10$abcdefghijklmnopqrstuvwxyz', 'stylist', 'John', 'Smith', '+1234567891'),
('jane.customer@example.com', '$2b$10$abcdefghijklmnopqrstuvwxyz', 'customer', 'Jane', 'Doe', '+1234567892'),
('bob.stylist@barbershop.com', '$2b$10$abcdefghijklmnopqrstuvwxyz', 'stylist', 'Bob', 'Johnson', '+1234567893');

-- Insert sample customers
INSERT INTO customers (user_id, face_shape, hair_type, hair_length) VALUES
(3, 'oval', 'straight', 'medium');

-- Insert sample stylists
INSERT INTO stylists (user_id, specialization, experience_years, rating, bio) VALUES
(2, 'Classic Cuts & Fades', 5, 4.8, 'Experienced stylist specializing in modern and classic haircuts'),
(4, 'Color & Styling', 3, 4.6, 'Expert in hair coloring and creative styling');

-- Insert sample services
INSERT INTO services (name, description, category, base_price, duration_minutes, is_active) VALUES
('Classic Haircut', 'Traditional barbershop haircut with styling', 'haircut', 25.00, 30, TRUE),
('Fade Haircut', 'Modern fade cut with clean lines', 'haircut', 30.00, 45, TRUE),
('Hair Coloring', 'Professional hair coloring service', 'coloring', 50.00, 90, TRUE),
('Beard Trim', 'Professional beard trimming and shaping', 'shaving', 15.00, 20, TRUE),
('Hot Towel Shave', 'Traditional hot towel shave experience', 'shaving', 35.00, 40, TRUE),
('Hair Treatment', 'Deep conditioning hair treatment', 'treatment', 40.00, 60, TRUE);

-- Link stylists to services
INSERT INTO stylist_services (stylist_id, service_id) VALUES
(1, 1), (1, 2), (1, 4), (1, 5),
(2, 1), (2, 3), (2, 6);

-- Insert sample working hours for stylists
INSERT INTO working_hours (stylist_id, day_of_week, start_time, end_time) VALUES
(1, 'Monday', '09:00:00', '17:00:00'),
(1, 'Tuesday', '09:00:00', '17:00:00'),
(1, 'Wednesday', '09:00:00', '17:00:00'),
(1, 'Thursday', '09:00:00', '17:00:00'),
(1, 'Friday', '09:00:00', '18:00:00'),
(1, 'Saturday', '10:00:00', '16:00:00'),
(2, 'Tuesday', '10:00:00', '18:00:00'),
(2, 'Wednesday', '10:00:00', '18:00:00'),
(2, 'Thursday', '10:00:00', '18:00:00'),
(2, 'Friday', '10:00:00', '19:00:00'),
(2, 'Saturday', '09:00:00', '17:00:00');
