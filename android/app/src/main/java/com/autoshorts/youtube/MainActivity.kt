package com.autoshorts.youtube

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView

/**
 * 스마트폰에 설치된 '진짜 공식 YouTube 어플(com.google.android.youtube)'과 100% 연동되는 설정 화면.
 * 별도의 가짜 영상 플레이어를 띄우지 않으며, 오직 순정 유튜브 어플의 [Shorts] 탭을 자동 스크롤합니다.
 */
class MainActivity : Activity() {

    private lateinit var statusBannerText: TextView
    private lateinit var statusActionBtn: Button
    private lateinit var launchYouTubeBtn: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val rootScroll = ScrollView(this).apply {
            setBackgroundColor(Color.parseColor("#0F0F0F"))
            isFillViewport = true
        }

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val pad = dp(20)
            setPadding(pad, dp(32), pad, pad)
        }

        val headerTitle = TextView(this).apply {
            text = "YouTube 쇼츠 자동 넘김 설정"
            setTextColor(Color.WHITE)
            textSize = 22f
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
        }
        val headerSub = TextView(this).apply {
            text = "스마트폰에 깔려 있는 '진짜 YouTube 공식 어플'에서 하단 [Shorts] 탭을 눌렀을 때 영상이 끝나면 자동으로 다음 쇼츠로 넘겨줍니다."
            setTextColor(Color.parseColor("#AAAAAA"))
            textSize = 14f
            setPadding(0, dp(6), 0, dp(20))
        }
        container.addView(headerTitle)
        container.addView(headerSub)

        // 1. 순정 유튜브 어플 연동 상태 카드
        val bannerCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = roundedBg("#1F1F1F", dp(12))
            val p = dp(16)
            setPadding(p, p, p, p)
        }
        statusBannerText = TextView(this).apply {
            textSize = 14.5f
            setTextColor(Color.WHITE)
        }
        statusActionBtn = Button(this).apply {
            text = "1단계: 접근성에서 [YouTube 쇼츠 자동 넘김 연동] 켜기"
            setTextColor(Color.BLACK)
            background = roundedBg("#FFFFFF", dp(12))
            setOnClickListener {
                startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            }
        }
        launchYouTubeBtn = Button(this).apply {
            text = "▶ 진짜 YouTube 공식 어플 바로 열기"
            setTextColor(Color.WHITE)
            background = roundedBg("#FF0033", dp(12))
            setOnClickListener {
                val launchIntent = packageManager.getLaunchIntentForPackage("com.google.android.youtube")
                if (launchIntent != null) {
                    startActivity(launchIntent)
                } else {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://www.youtube.com/shorts")))
                }
            }
        }

        bannerCard.addView(statusBannerText)
        bannerCard.addView(statusActionBtn, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(12) })
        bannerCard.addView(launchYouTubeBtn, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(10) })
        container.addView(bannerCard)

        // 2. 설정(Settings) ON/OFF 스위치 카드
        val settingsCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = roundedBg("#1A1A1A", dp(12))
            val p = dp(16)
            setPadding(p, dp(8), p, dp(8))
        }

        settingsCard.addView(
            createSwitchRow(
                title = "쇼츠 자동 넘김 (반복 재생 방지)",
                subtitle = "유튜브 어플의 쇼츠 영상이 끝까지 재생되면 자동으로 다음 쇼츠로 넘깁니다.",
                initialChecked = PrefsManager.isAutoScrollEnabled(this)
            ) { checked ->
                PrefsManager.setAutoScrollEnabled(this, checked)
            }
        )

        settingsCard.addView(createDivider())

        settingsCard.addView(
            createSwitchRow(
                title = "댓글·설명창 열람 시 일시정지",
                subtitle = "댓글을 읽고 있는 동안에는 영상이 끝나도 넘어가지 않습니다.",
                initialChecked = PrefsManager.isPauseOnCommentsEnabled(this)
            ) { checked ->
                PrefsManager.setPauseOnCommentsEnabled(this, checked)
            }
        )

        container.addView(settingsCard, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(20) })

        rootScroll.addView(container)
        setContentView(rootScroll)
    }

    override fun onResume() {
        super.onResume()
        updateServiceStatusUI()
    }

    private fun updateServiceStatusUI() {
        val connected = isAccessibilityServiceEnabled()
        if (connected) {
            statusBannerText.text = "✅ 진짜 YouTube 공식 어플과 연동 완료!\n아래 빨간 버튼을 눌러 유튜브 어플을 켜고 하단 [Shorts] 탭을 눌러보세요."
            statusBannerText.setTextColor(Color.parseColor("#2BA640"))
            statusActionBtn.visibility = View.GONE
            launchYouTubeBtn.visibility = View.VISIBLE
        } else {
            statusBannerText.text = "⚠️ 먼저 아래 하얀 버튼을 눌러 [접근성 > 설치된 앱 > YouTube 쇼츠 자동 넘김 연동]을 켜주세요."
            statusBannerText.setTextColor(Color.parseColor("#FFCC00"))
            statusActionBtn.visibility = View.VISIBLE
            launchYouTubeBtn.visibility = View.VISIBLE
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val expectedComponent = ComponentName(this, ShortsAutoScrollService::class.java)
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabledServices)
        while (splitter.hasNext()) {
            val componentStr = splitter.next()
            val enabledComponent = ComponentName.unflattenFromString(componentStr)
            if (enabledComponent != null && enabledComponent == expectedComponent) {
                return true
            }
        }
        return false
    }

    private fun createSwitchRow(
        title: String,
        subtitle: String,
        initialChecked: Boolean,
        onChanged: (Boolean) -> Unit
    ): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(14), 0, dp(14))
        }

        val textCol = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                rightMargin = dp(12)
            }
        }

        val titleView = TextView(this).apply {
            text = title
            setTextColor(Color.WHITE)
            textSize = 16f
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        }

        val subView = TextView(this).apply {
            text = subtitle
            setTextColor(Color.parseColor("#AAAAAA"))
            textSize = 13f
            setPadding(0, dp(4), 0, 0)
        }

        textCol.addView(titleView)
        textCol.addView(subView)

        val toggle = Switch(this).apply {
            isChecked = initialChecked
            setOnCheckedChangeListener { _, isChecked -> onChanged(isChecked) }
        }

        row.addView(textCol)
        row.addView(toggle)
        return row
    }

    private fun createDivider(): View {
        return View(this).apply {
            setBackgroundColor(Color.parseColor("#2A2A2A"))
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1))
        }
    }

    private fun roundedBg(hexColor: String, radiusPx: Int): GradientDrawable {
        return GradientDrawable().apply {
            setColor(Color.parseColor(hexColor))
            cornerRadius = radiusPx.toFloat()
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }
}
