package com.example.tatis_barbershop

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Replace the launch intent so a later OAuth/recovery VIEW is not
        // confused with the first deep link that started this singleTask activity.
        setIntent(intent)
    }
}
