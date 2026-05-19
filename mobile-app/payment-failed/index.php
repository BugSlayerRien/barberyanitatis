<?php
// Simple landing page for payment failure/expired redirects from PayMongo
?><!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>Payment Not Completed</title>
  <style>body{font-family:Arial,Helvetica,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#fff6f6} .card{max-width:640px;padding:32px;border-radius:8px;background:#fff;box-shadow:0 6px 24px rgba(20,30,50,.06);text-align:center} a.button{display:inline-block;margin-top:18px;padding:10px 18px;background:#e02424;color:#fff;border-radius:6px;text-decoration:none}</style>
</head>
<body>
  <div class="card">
    <h1>Payment Not Completed</h1>
    <p>The payment was not completed or was expired. You can retry from the app.</p>
    <p id="info"></p>
    <a class="button" href="#" id="returnButton" onclick="tryDeepLink();return false;">Return to App</a>
  </div>
  <script>
    const params = new URLSearchParams(window.location.search);
    if (params.toString()) {
      document.getElementById('info').textContent = 'Details: ' + params.toString();
    }

    function tryDeepLink() {
      const q = params.toString();
      const scheme = 'tatisapp://payment-return' + (q ? ('?' + q) : '');
      const isAndroid = /Android/i.test(navigator.userAgent);
      const isIOS = /iPhone|iPad|iPod/i.test(navigator.userAgent);

      if (isAndroid || isIOS) {
        try {
          if (isAndroid) {
            window.location = scheme;
          } else {
            const iframe = document.createElement('iframe');
            iframe.style.display = 'none';
            iframe.src = scheme;
            document.body.appendChild(iframe);
          }
        } catch (e) {}

        setTimeout(() => {
          document.getElementById('info').textContent = 'If your app did not open automatically, return to the app manually.';
        }, 800);
      } else {
        document.getElementById('info').textContent = 'Open the installed mobile app to continue. If you are on the web, return to the app manually.';
      }
    }

    window.addEventListener('load', () => setTimeout(tryDeepLink, 300));
  </script>
</body>
</html>
