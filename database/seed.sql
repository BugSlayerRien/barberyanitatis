-- Seed future time slots (50-minute spacing: 35-min cut + 15-min buffer)
WITH RECURSIVE days AS (
  SELECT 0 AS d
  UNION ALL SELECT d + 1 FROM days WHERE d < 13
),
times AS (
  SELECT 0 AS t, TIME('09:00:00') AS slot_time
  UNION ALL
  SELECT t + 1, ADDTIME('09:00:00', SEC_TO_TIME((t + 1) * 50 * 60))
  FROM times
  WHERE t < 9
)
INSERT IGNORE INTO time_slots (barber_id, slot_date, slot_time, duration, status)
SELECT b.barber_id,
       DATE_ADD(CURDATE(), INTERVAL d DAY) AS slot_date,
       slot_time,
       35,
       'Available'
FROM barbers b
JOIN days
JOIN times
WHERE b.is_active = 1;
