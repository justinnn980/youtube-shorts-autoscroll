package com.autoshorts.youtube

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * 스마트폰에 설치된 '진짜 공식 YouTube 어플(com.google.android.youtube)'에서
 * 하단 [Shorts(쇼츠)] 탭을 눌렀을 때 영상이 끝나면 자동으로 다음 쇼츠로 넘겨주는 서비스.
 */
class ShortsAutoScrollService : AccessibilityService() {

    companion object {
        private const val TAG = "ShortsAutoScroll"
        private const val YOUTUBE_PACKAGE = "com.google.android.youtube"

        private const val SCROLL_COOLDOWN_MS = 1600L
        private const val END_THRESHOLD_RATIO = 0.98f
        private const val LOOP_HIGH_WATERMARK = 0.80f
        private const val LOOP_RESET_THRESHOLD = 0.18f
    }

    private val handler = Handler(Looper.getMainLooper())
    private var lastScrollTimeMs = 0L
    private var lastProgressRatio = 0f
    private var currentReelSignature: String = ""
    private var reelEnteredTimeMs = 0L

    private val pollRunnable = object : Runnable {
        override fun run() {
            try {
                checkShortsProgressAndScroll()
            } catch (e: Exception) {
                Log.w(TAG, "Error in Shorts poll", e)
            } finally {
                if (PrefsManager.isAutoScrollEnabled(this@ShortsAutoScrollService)) {
                    handler.postDelayed(this, 140L)
                }
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.i(TAG, "Connected to official YouTube app AccessibilityService")
        handler.post(pollRunnable)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (event.packageName?.toString() != YOUTUBE_PACKAGE) return
        if (!PrefsManager.isAutoScrollEnabled(this)) return

        if (event.eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED) {
            val now = SystemClock.uptimeMillis()
            if (now - lastScrollTimeMs > 600L) {
                lastProgressRatio = 0f
                reelEnteredTimeMs = now
            }
        }

        checkShortsProgressAndScroll()
    }

    private fun checkShortsProgressAndScroll() {
        if (!PrefsManager.isAutoScrollEnabled(this)) return

        val now = SystemClock.uptimeMillis()
        if (now - lastScrollTimeMs < SCROLL_COOLDOWN_MS) return

        val rootNode = rootInActiveWindow ?: return
        if (rootNode.packageName?.toString() != YOUTUBE_PACKAGE) return
        rootNode.refresh()

        // 1. 현재 화면이 공식 유튜브 앱의 [Shorts(쇼츠)] 탭/플레이어 화면인지 판별
        if (!isShortsPlayerScreen(rootNode)) {
            currentReelSignature = ""
            lastProgressRatio = 0f
            reelEnteredTimeMs = 0L
            return
        }

        // 2. 댓글창이나 바텀시트가 열려 있으면 일시정지
        if (PrefsManager.isPauseOnCommentsEnabled(this) && isCommentOrSheetOpen(rootNode)) {
            return
        }

        // 3. 현재 재생 중인 쇼츠 식별자 추적
        val signature = extractCurrentReelSignature(rootNode)
        if (signature.isNotEmpty() && signature != currentReelSignature) {
            currentReelSignature = signature
            lastProgressRatio = 0f
            reelEnteredTimeMs = now
        } else if (reelEnteredTimeMs == 0L) {
            reelEnteredTimeMs = now
        }

        // 4. 진행바(ProgressBar / SeekBar / 시간 텍스트)에서 진행률(0.0 ~ 1.0) 추출
        val progressRatio = findShortsProgressRatio(rootNode)

        if (progressRatio != null) {
            val reachedEnd = progressRatio >= END_THRESHOLD_RATIO
            val loopedAround = (lastProgressRatio >= LOOP_HIGH_WATERMARK && progressRatio < LOOP_RESET_THRESHOLD)

            if (reachedEnd || loopedAround) {
                Log.d(TAG, "Shorts video ended (ratio=$progressRatio, prev=$lastProgressRatio) -> swiping up!")
                lastProgressRatio = 0f
                triggerNextShort(rootNode)
                return
            }

            if (progressRatio > lastProgressRatio || progressRatio < 0.2f) {
                lastProgressRatio = progressRatio
            }
        } else {
            // 진행바 노드가 노출되지 않는 쇼츠의 경우 설정된 시간 후 자동 스와이프
            val fallbackMs = PrefsManager.getFallbackShortSeconds(this) * 1000L
            if (reelEnteredTimeMs > 0L && (now - reelEnteredTimeMs) >= fallbackMs) {
                reelEnteredTimeMs = now
                triggerNextShort(rootNode)
            }
        }
    }

    /**
     * 공식 유튜브 앱에서 사용자가 'Shorts(쇼츠)' 탭을 보고 있는지 다중 방식으로 정확히 감지
     */
    private fun isShortsPlayerScreen(root: AccessibilityNodeInfo): Boolean {
        // 방식 A: View ID 기반 확인
        val shortsViewIds = listOf(
            "$YOUTUBE_PACKAGE:id/reel_recycler",
            "$YOUTUBE_PACKAGE:id/reel_watch_fragment_root",
            "$YOUTUBE_PACKAGE:id/reel_player_page_container",
            "$YOUTUBE_PACKAGE:id/reel_progress_bar",
            "$YOUTUBE_PACKAGE:id/reel_time_bar"
        )
        for (id in shortsViewIds) {
            val nodes = root.findAccessibilityNodeInfosByViewId(id)
            if (!nodes.isNullOrEmpty()) return true
        }

        // 방식 B: 하단 탭바에서 'Shorts' 또는 '쇼츠' 탭이 선택(isSelected)되어 있거나
        // 쇼츠 전용 버튼('리믹스' / 'Remix')이 화면에 표시되어 있는지 트리 탐색
        return detectShortsNodesRecursive(root, 0)
    }

    private fun detectShortsNodesRecursive(node: AccessibilityNodeInfo?, depth: Int): Boolean {
        if (node == null || depth > 14) return false

        val text = node.text?.toString() ?: ""
        val desc = node.contentDescription?.toString() ?: ""

        // 하단 네비게이션 탭 중 'Shorts' / '쇼츠' 탭이 선택된 상태인지 확인
        if (node.isSelected && (
                text.equals("Shorts", ignoreCase = true) ||
                text == "쇼츠" ||
                desc.contains("Shorts", ignoreCase = true) ||
                desc.contains("쇼츠")
            )
        ) {
            return true
        }

        // 쇼츠 우측 하단 고유 버튼인 '리믹스(Remix)' 또는 '이 사운드 사용' 버튼이 보이는지 확인
        if (node.isVisibleToUser && (
                text == "리믹스" ||
                text.equals("Remix", ignoreCase = true) ||
                desc.contains("리믹스") ||
                desc.contains("Remix", ignoreCase = true)
            )
        ) {
            return true
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            if (detectShortsNodesRecursive(child, depth + 1)) return true
        }
        return false
    }

    private fun isCommentOrSheetOpen(root: AccessibilityNodeInfo): Boolean {
        val sheetIds = listOf(
            "$YOUTUBE_PACKAGE:id/engagement_panel_wrapper",
            "$YOUTUBE_PACKAGE:id/design_bottom_sheet",
            "$YOUTUBE_PACKAGE:id/bottom_sheet_container"
        )
        for (id in sheetIds) {
            val nodes = root.findAccessibilityNodeInfosByViewId(id)
            if (!nodes.isNullOrEmpty() && nodes.any { it.isVisibleToUser }) return true
        }
        return false
    }

    private fun extractCurrentReelSignature(root: AccessibilityNodeInfo): String {
        val sb = StringBuilder()
        collectVisibleTexts(root, sb, 0)
        return sb.toString().take(120)
    }

    private fun collectVisibleTexts(node: AccessibilityNodeInfo?, sb: StringBuilder, depth: Int) {
        if (node == null || depth > 8 || sb.length > 120) return
        val t = node.text?.toString()
        if (!t.isNullOrBlank() && t.startsWith("@")) {
            sb.append(t).append("|")
        }
        for (i in 0 until node.childCount) {
            collectVisibleTexts(node.getChild(i), sb, depth + 1)
        }
    }

    private fun findShortsProgressRatio(root: AccessibilityNodeInfo): Float? {
        val progressIds = listOf(
            "$YOUTUBE_PACKAGE:id/reel_progress_bar",
            "$YOUTUBE_PACKAGE:id/reel_time_bar"
        )
        for (id in progressIds) {
            val nodes = root.findAccessibilityNodeInfosByViewId(id)
            if (!nodes.isNullOrEmpty()) {
                for (node in nodes) {
                    val ratio = extractRatioFromNode(node)
                    if (ratio != null) return ratio
                }
            }
        }
        return findRangeRatioRecursive(root, 0)
    }

    private fun extractRatioFromNode(node: AccessibilityNodeInfo): Float? {
        val range = node.rangeInfo
        if (range != null && range.max > range.min) {
            return ((range.current - range.min) / (range.max - range.min)).coerceIn(0f, 1f)
        }

        val combined = listOfNotNull(
            node.contentDescription?.toString(),
            node.text?.toString()
        ).joinToString(" ")

        if (combined.isNotEmpty()) {
            // "0:14 / 0:15" 형식 파싱
            val timeMatch = Regex("""(\d+):(\d{2})\s*/\s*(\d+):(\d{2})""").find(combined)
            if (timeMatch != null) {
                val curSec = timeMatch.groupValues[1].toInt() * 60 + timeMatch.groupValues[2].toInt()
                val totSec = timeMatch.groupValues[3].toInt() * 60 + timeMatch.groupValues[4].toInt()
                if (totSec > 0) return (curSec.toFloat() / totSec.toFloat()).coerceIn(0f, 1f)
            }
            // "14초 / 15초" 형식 파싱
            val korSecMatch = Regex("""(\d+)\s*초\s*/\s*(\d+)\s*초""").find(combined)
            if (korSecMatch != null) {
                val curSec = korSecMatch.groupValues[1].toFloat()
                val totSec = korSecMatch.groupValues[2].toFloat()
                if (totSec > 0f) return (curSec / totSec).coerceIn(0f, 1f)
            }
            // "98%" 형식 파싱
            val pctMatch = Regex("""(\d{1,3})\s*%""").find(combined)
            if (pctMatch != null) {
                val pct = pctMatch.groupValues[1].toFloatOrNull()
                if (pct != null) return (pct / 100f).coerceIn(0f, 1f)
            }
        }
        return null
    }

    private fun findRangeRatioRecursive(node: AccessibilityNodeInfo?, depth: Int): Float? {
        if (node == null || depth > 14) return null
        val cls = node.className?.toString() ?: ""
        if (node.rangeInfo != null || cls.contains("ProgressBar") || cls.contains("SeekBar") || cls.contains("TimeBar")) {
            val ratio = extractRatioFromNode(node)
            if (ratio != null) return ratio
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val ratio = findRangeRatioRecursive(child, depth + 1)
            if (ratio != null) return ratio
        }
        return null
    }

    private fun triggerNextShort(root: AccessibilityNodeInfo) {
        lastScrollTimeMs = SystemClock.uptimeMillis()
        reelEnteredTimeMs = lastScrollTimeMs

        val recyclerNodes = root.findAccessibilityNodeInfosByViewId("$YOUTUBE_PACKAGE:id/reel_recycler")
        if (!recyclerNodes.isNullOrEmpty()) {
            val recycler = recyclerNodes.firstOrNull { it.isScrollable }
            if (recycler != null && recycler.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)) {
                return
            }
        }

        val dm = resources.displayMetrics
        val centerX = dm.widthPixels * 0.5f
        val startY = dm.heightPixels * 0.76f
        val endY = dm.heightPixels * 0.20f

        val swipePath = Path().apply {
            moveTo(centerX, startY)
            lineTo(centerX, endY)
        }

        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(swipePath, 0L, 200L))
            .build()

        dispatchGesture(gesture, null, null)
    }

    override fun onInterrupt() {
        handler.removeCallbacks(pollRunnable)
    }

    override fun onDestroy() {
        handler.removeCallbacks(pollRunnable)
        super.onDestroy()
    }
}
