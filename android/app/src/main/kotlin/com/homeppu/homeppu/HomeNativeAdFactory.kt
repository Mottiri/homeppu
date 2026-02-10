package com.homeppu.homeppu

import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class HomeNativeAdFactory(
    private val layoutInflater: LayoutInflater,
) : GoogleMobileAdsPlugin.NativeAdFactory {

    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?,
    ): NativeAdView {
        val adView = layoutInflater.inflate(
            R.layout.native_feed_ad,
            null,
        ) as NativeAdView

        val headlineView = adView.findViewById<TextView>(R.id.ad_headline)
        val bodyView = adView.findViewById<TextView>(R.id.ad_body)
        val advertiserView = adView.findViewById<TextView>(R.id.ad_advertiser)
        val callToActionView = adView.findViewById<Button>(R.id.ad_call_to_action)
        val iconView = adView.findViewById<ImageView>(R.id.ad_icon)
        val mediaView =
            adView.findViewById<com.google.android.gms.ads.nativead.MediaView>(R.id.ad_media)

        adView.headlineView = headlineView
        adView.bodyView = bodyView
        adView.advertiserView = advertiserView
        adView.callToActionView = callToActionView
        adView.iconView = iconView
        adView.mediaView = mediaView

        headlineView.text = nativeAd.headline

        val body = nativeAd.body
        if (body.isNullOrEmpty()) {
            bodyView.visibility = View.GONE
        } else {
            bodyView.text = body
            bodyView.visibility = View.VISIBLE
        }

        val advertiser = nativeAd.advertiser
        if (advertiser.isNullOrEmpty()) {
            advertiserView.visibility = View.GONE
        } else {
            advertiserView.text = advertiser
            advertiserView.visibility = View.VISIBLE
        }

        val icon = nativeAd.icon
        if (icon == null) {
            iconView.visibility = View.GONE
        } else {
            iconView.setImageDrawable(icon.drawable)
            iconView.visibility = View.VISIBLE
        }

        val cta = nativeAd.callToAction
        if (cta.isNullOrEmpty()) {
            callToActionView.visibility = View.GONE
        } else {
            callToActionView.text = cta
            callToActionView.visibility = View.VISIBLE
        }

        mediaView.setMediaContent(nativeAd.mediaContent)
        adView.setNativeAd(nativeAd)
        return adView
    }
}
