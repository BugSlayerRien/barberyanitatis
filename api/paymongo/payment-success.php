<?php
declare(strict_types=1);
header('Content-Type: text/html; charset=utf-8');

// Forward every incoming query parameter (the purpose=ai_credits/appointment
// marker set when the payment/purchase was created, plus whatever PayMongo
// itself appends, e.g. source_id) into the deep link. This used to be a bare
// "status=success" with nothing else, so on the rare path where
// PaymentResultPage ends up handling the return itself (see
// PaymentReturnGuard in the app), its own status poll had no resource id to
// check and sat on "Verifying your payment..." forever -- even though the
// payment had already succeeded.
$incoming = $_GET;
unset($incoming['status']);
$query = http_build_query(array_merge(['status' => 'success'], $incoming));
$target = 'tatisapp://payment-return?' . $query;
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="0;url=<?php echo htmlspecialchars($target, ENT_QUOTES, 'UTF-8'); ?>">
  <title>Payment successful</title>
</head>
<body>
  <p>Payment received. You can return to the Tatis app.</p>
  <p><a href="<?php echo htmlspecialchars($target, ENT_QUOTES, 'UTF-8'); ?>">Open the app</a></p>
</body>
</html>
