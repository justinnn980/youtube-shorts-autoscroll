package com.autoshorts.youtube

import android.content.Context
import android.content.SharedPreferences

/**
 * 설정(Settings) 화면에서 변경한 값을 백그라운드 서비스와 실시간 공유하는 매니저
 */
object PrefsManager {
    private const val PREFS_NAME = "youtube_shorts_autoscroll_prefs"

    const val KEY_ENABLED = "auto_scroll_enabled"
    const val KEY_PAUSE_ON_COMMENTS = "pause_on_comments"
    const val KEY_FALLBACK_SHORT_SECONDS = "fallback_short_seconds"
    const val KEY_SKIP_SPONSORED = "skip_sponsored_ads"

    private fun prefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    /** 쇼츠 자동 넘김 ON/OFF (기본값: ON) */
    fun isAutoScrollEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENABLED, true)

    fun setAutoScrollEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    /** 댓글창이나 설명창을 열어둔 동안 자동 넘김 일시정지 (기본값: ON) */
    fun isPauseOnCommentsEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_PAUSE_ON_COMMENTS, true)

    fun setPauseOnCommentsEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_PAUSE_ON_COMMENTS, enabled).apply()
    }

    /** 광고(Sponsored) 쇼츠 감지 시 즉시 넘김 (기본값: OFF) */
    fun isSkipSponsoredEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_SKIP_SPONSORED, false)

    fun setSkipSponsoredEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_SKIP_SPONSORED, enabled).apply()
    }

    /** 하단 진행바가 없는 초단편 쇼츠(5초 미만)일 때 자동 넘김 대기 초 (기본값: 5초) */
    fun getFallbackShortSeconds(context: Context): Int =
        prefs(context).getInt(KEY_FALLBACK_SHORT_SECONDS, 5)

    fun setFallbackShortSeconds(context: Context, seconds: Int) {
        prefs(context).edit().putInt(KEY_FALLBACK_SHORT_SECONDS, seconds.coerceIn(3, 30)).apply()
    }
}

