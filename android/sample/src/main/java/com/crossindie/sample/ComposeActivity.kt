package com.crossindie.sample

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import android.util.Log
import com.crossindie.sdk.Ad
import com.crossindie.sdk.BannerFormat
import com.crossindie.sdk.CrossIndieBannerListener
import com.crossindie.sdk.compose.CrossIndieBanner

class ComposeActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val appId = stringResource(R.string.ci_app_id)
            LazyColumn(
                Modifier.fillMaxSize().background(Color(0xFF0B0A09)).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                item { CrossIndieBanner(appId = appId, modifier = Modifier.fillMaxWidth()) }
                items(20) { Text("Row $it", color = Color.White, modifier = Modifier.padding(16.dp)) }
                // Below the fold: counted only once scrolled >= 50 % into view.
                item {
                    CrossIndieBanner(
                        appId = appId,
                        format = BannerFormat.CARD,
                        modifier = Modifier.fillMaxWidth(),
                        listener = object : CrossIndieBannerListener {
                            override fun onAdLoaded(ad: Ad) { Log.i("Sample", "compose card loaded ${ad.name}") }
                            override fun onImpression(ad: Ad) { Log.i("Sample", "compose card impression") }
                        },
                    )
                }
            }
        }
    }
}
