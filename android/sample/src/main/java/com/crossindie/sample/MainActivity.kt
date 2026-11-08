package com.crossindie.sample

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log
import com.crossindie.sdk.Ad
import com.crossindie.sdk.CrossIndie
import com.crossindie.sdk.CrossIndieBannerListener
import com.crossindie.sdk.CrossIndieBannerView

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        CrossIndie.apiBase = BuildConfig.API_BASE // optional; defaults to https://api.crossindie.com
        CrossIndie.debugLogging = true
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        findViewById<CrossIndieBannerView>(R.id.banner).listener = object : CrossIndieBannerListener {
            override fun onAdLoaded(ad: Ad) { Log.i("Sample", "loaded ${ad.name}") }
            override fun onNoFill() { Log.i("Sample", "no fill") }
            override fun onImpression(ad: Ad) { Log.i("Sample", "impression ${ad.name}") }
            override fun onClick(ad: Ad) { Log.i("Sample", "click ${ad.name}") }
        }
        findViewById<android.view.View>(R.id.open_compose).setOnClickListener {
            startActivity(Intent(this, ComposeActivity::class.java))
        }
    }
}
