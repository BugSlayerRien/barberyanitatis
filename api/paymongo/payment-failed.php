<?php
declare(strict_types=1);
header('Content-Type: text/html; charset=utf-8');
$target = 'tatisapp://payment-return?status=failed';
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="refresh" content="0;url=<?php echo htmlspecialchars($target, ENT_QUOTES, 'UTF-8'); ?>">
  <title>Payment not completed</title>
</head>
<body>
  <p>Payment was not completed. You can return to the Tatis app and retry.</p>
  <p><a href="<?php echo htmlspecialchars($target, ENT_QUOTES, 'UTF-8'); ?>">Open the app</a></p>
</body>
</html>
