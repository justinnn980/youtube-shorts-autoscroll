/**
 * YouTube Shorts 자동 넘김 엔진 (iOS Safari Extension & Desktop/Mobile YouTube)
 *
 * - 영상 화면 위에 거슬리는 플로팅 버튼을 절대 띄우지 않습니다 (순정 UI 100% 보존).
 * - 설정(Settings) 화면 또는 유튜브 내 설정 메뉴(⋮ / 설정 페이지)에서만 깔끔하게 ON/OFF 합니다.
 * - 쇼츠 영상이 끝까지 재생되면(반복 재생 직전) 자동으로 다음 쇼츠로 넘깁니다.
 * - 댓글창이나 설명창이 열려 있을 때는 자동으로 일시정지합니다.
 */
(function () {
  "use strict";

  const state = {
    enabled: true,
    pauseOnComments: true,
    skipSponsored: false,
    lastScrollAt: 0,
    maxRatioForCurrentVideo: 0,
    lastVideoSrc: ""
  };

  // 설정값 불러오기 및 실시간 반영
  function loadSettings() {
    if (typeof chrome !== "undefined" && chrome.storage && chrome.storage.local) {
      chrome.storage.local.get(
        {
          autoScrollEnabled: true,
          pauseOnComments: true,
          skipSponsored: false
        },
        (res) => {
          state.enabled = Boolean(res.autoScrollEnabled);
          state.pauseOnComments = Boolean(res.pauseOnComments);
          state.skipSponsored = Boolean(res.skipSponsored);
        }
      );

      chrome.storage.onChanged.addListener((changes) => {
        if (changes.autoScrollEnabled) state.enabled = Boolean(changes.autoScrollEnabled.newValue);
        if (changes.pauseOnComments) state.pauseOnComments = Boolean(changes.pauseOnComments.newValue);
        if (changes.skipSponsored) state.skipSponsored = Boolean(changes.skipSponsored.newValue);
      });
    } else {
      const saved = localStorage.getItem("yt_autoshorts_enabled");
      if (saved !== null) state.enabled = saved === "true";
    }
  }

  function saveEnabledState(val) {
    state.enabled = Boolean(val);
    localStorage.setItem("yt_autoshorts_enabled", String(state.enabled));
    if (typeof chrome !== "undefined" && chrome.storage && chrome.storage.local) {
      chrome.storage.local.set({ autoScrollEnabled: state.enabled });
    }
  }

  function isShortsPage() {
    return location.pathname.startsWith("/shorts");
  }

  // 댓글창이나 설명창이 열려 있는지 감지
  function isCommentsOrPanelOpen() {
    if (!state.pauseOnComments) return false;

    // 데스크톱 유튜브 댓글 패널
    const desktopPanels = document.querySelectorAll(
      'ytd-engagement-panel-section-list-renderer[visibility="ENGAGEMENT_PANEL_VISIBILITY_EXPANDED"]'
    );
    if (desktopPanels.length > 0) return true;

    // 모바일(iOS) 유튜브 댓글 바텀시트
    const mobilePanel = document.querySelector(
      "ytm-engagement-panel-section-list-renderer, .engagement-panel-container, [aria-Modal='true']"
    );
    if (mobilePanel && mobilePanel.offsetParent !== null) return true;

    return false;
  }

  // 다음 쇼츠로 자연스럽게 스크롤
  function goToNextShort() {
    const now = Date.now();
    if (now - state.lastScrollAt < 1400) return;
    if (isCommentsOrPanelOpen()) return;

    state.lastScrollAt = now;
    state.maxRatioForCurrentVideo = 0;

    // 1순위: 공식 '다음 동영상' 네비게이션 버튼 클릭
    const nextBtn =
      document.querySelector("#navigation-button-down button") ||
      document.querySelector('button[aria-label*="다음 동영상"]') ||
      document.querySelector('button[aria-label*="Next video"]');
    if (nextBtn) {
      nextBtn.click();
      return;
    }

    // 2순위: 모바일/iOS 쇼츠 활성 렌더러의 다음 요소로 부드럽게 스크롤
    const activeReel =
      document.querySelector("ytd-reel-video-renderer[is-active]") ||
      document.querySelector("ytm-reel-item-renderer.reel-item-active") ||
      document.querySelector("ytm-shorts-lockup-view-model");

    if (activeReel && activeReel.nextElementSibling) {
      activeReel.nextElementSibling.scrollIntoView({ behavior: "smooth", block: "center" });
      return;
    }

    // 3순위: 쇼츠 스크롤 컨테이너 또는 키보드 ArrowDown 이벤트 디스패치
    window.dispatchEvent(
      new KeyboardEvent("keydown", {
        key: "ArrowDown",
        code: "ArrowDown",
        keyCode: 40,
        which: 40,
        bubbles: true
      })
    );
  }

  // 현재 재생 중인 쇼츠 <video> 요소 바인딩
  function attachToActiveShortsVideo() {
    if (!isShortsPage()) return;

    const videos = Array.from(document.querySelectorAll("video"));
    const activeVideo = videos.find((v) => !v.paused && v.readyState >= 2 && v.offsetParent !== null) || videos[0];
    if (!activeVideo) return;

    // 설정이 켜져 있으면 기본 loop 속성을 해제하여 ended 이벤트 및 정밀 시점 감지가 가능하게 함
    if (state.enabled && activeVideo.hasAttribute("loop")) {
      activeVideo.removeAttribute("loop");
      activeVideo.loop = false;
    }

    if (activeVideo.dataset.autoShortsBound === "true") return;
    activeVideo.dataset.autoShortsBound = "true";

    activeVideo.addEventListener("timeupdate", () => {
      if (!state.enabled || !isShortsPage()) return;
      const dur = activeVideo.duration;
      const cur = activeVideo.currentTime;
      if (!dur || !isFinite(dur) || dur <= 0.5) return;

      if (activeVideo.currentSrc !== state.lastVideoSrc) {
        state.lastVideoSrc = activeVideo.currentSrc;
        state.maxRatioForCurrentVideo = 0;
      }

      const ratio = cur / dur;

      // (A) 98.8% 이상 재생 완료되었거나
      // (B) 85% 이상 재생 후 루프로 인해 12% 미만으로 되감긴 순간 다음 쇼츠로 이동
      const reachedEnd = ratio >= 0.988;
      const loopedBack = state.maxRatioForCurrentVideo >= 0.85 && ratio < 0.12;

      if (reachedEnd || loopedBack) {
        goToNextShort();
        return;
      }

      if (ratio > state.maxRatioForCurrentVideo) {
        state.maxRatioForCurrentVideo = ratio;
      }
    });

    activeVideo.addEventListener("ended", () => {
      if (!state.enabled || !isShortsPage()) return;
      goToNextShort();
    });
  }

  // 유튜브 순정 설정 메뉴(⋮ 메뉴 / 설정 시트)가 열렸을 때만 내부에 '쇼츠 자동 넘김' 항목 주입
  function injectIntoYouTubeSettingsMenu() {
    const menuLists = document.querySelectorAll(
      "tp-yt-paper-listbox#items, ytm-menu-item, .menu-content"
    );

    menuLists.forEach((menu) => {
      if (menu.querySelector(".yt-autoshorts-setting-item")) return;

      const item = document.createElement("div");
      item.className = "yt-autoshorts-setting-item";
      item.style.cssText =
        "display:flex;align-items:center;justify-content:space-between;padding:10px 16px;cursor:pointer;color:inherit;font-size:14px;border-top:1px solid rgba(255,255,255,0.08);";

      const label = document.createElement("span");
      label.textContent = "쇼츠 자동 넘김 (반복 재생 방지)";

      const status = document.createElement("span");
      status.style.cssText = "font-weight:600;margin-left:12px;";
      const renderStatus = () => {
        status.textContent = state.enabled ? "켜짐" : "꺼짐";
        status.style.color = state.enabled ? "#3ea6ff" : "#aaaaaa";
      };
      renderStatus();

      item.appendChild(label);
      item.appendChild(status);

      item.addEventListener("click", (e) => {
        e.stopPropagation();
        saveEnabledState(!state.enabled);
        renderStatus();
      });

      menu.appendChild(item);
    });
  }

  loadSettings();
  setInterval(() => {
    attachToActiveShortsVideo();
    injectIntoYouTubeSettingsMenu();
  }, 300);
})();

