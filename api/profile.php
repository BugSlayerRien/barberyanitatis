<?php
error_reporting(E_ALL);
ini_set('display_errors', '0');
ini_set('log_errors', '1');

header('Content-Type: application/json');

require_once __DIR__ . '/db.php';

require_method('POST');

$data = get_json_input();
$userID = $data['userID'] ?? ($_POST['userID'] ?? null);

if (!$userID) {
    http_response_code(400);
    echo json_encode(['error' => 'userID is required']);
    exit;
}

try {
    $pdo = get_db_connection();
    
    // Fetch user profile plus completed haircut count.
    // Use a subquery to avoid GROUP BY issues on PostgreSQL.
    $stmt = $pdo->prepare('
        SELECT 
            u.user_id,
            u.email,
            u.full_name,
            u.phone,
            u.gender,
            NULL::text AS hair_texture,
            NULL::text AS profile_image_url,
            u.created_at,
            COALESCE(ac.haircuts_done, 0) AS haircuts_done
        FROM users u
        LEFT JOIN (
            SELECT user_id, COUNT(*)::int AS haircuts_done
            FROM appointments
            WHERE status = ?
            GROUP BY user_id
        ) ac ON ac.user_id = u.user_id
        WHERE u.user_id = ?
    ');
    
    if (!$stmt) {
        throw new Exception('Prepared statement failed: ' . $pdo->errorInfo()[2]);
    }
    
    $success = $stmt->execute(['completed', $userID]);
    if (!$success) {
        throw new Exception('Query execution failed: ' . $stmt->errorInfo()[2]);
    }
    
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$row) {
        http_response_code(404);
        echo json_encode(['error' => 'User not found']);
        exit;
    }
    
    $createdDate = new DateTime($row['created_at']);
    $now = new DateTime();
    $accountAgeDays = $now->diff($createdDate)->days;
    
    json_response([
        'profile' => [
            'userID' => $row['user_id'],
            'email' => $row['email'],
            'fullName' => $row['full_name'],
            'phone' => $row['phone'] ?? '',
            'gender' => $row['gender'] ?? '',
            'hairTexture' => $row['hair_texture'] ?? '',
            'profileImage' => $row['profile_image_url'] ?? '',
            'accountAge' => $accountAgeDays . ' days',
            'haircutsDone' => (int)$row['haircuts_done'] ?? 0
        ]
    ], 200);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Database error: ' . $e->getMessage()]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Error: ' . $e->getMessage()]);
}
?>
