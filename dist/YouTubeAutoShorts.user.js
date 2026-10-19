// ==UserScript==
// @name         YouTube Shorts 자동 넘김 (순정 설정 연동)
// @namespace    https://autoshorts.youtube.local
// @version      1.0.0
// @description  유튜브 쇼츠 영상이 끝까지 재생되면 반복 재생되지 않고 자동으로 다음 쇼츠로 넘어갑니다. 화면을 가리는 버튼 없이 유튜브 설정(⋮) 메뉴 안에서 켜고 끌 수 있습니다.
// @author       AutoShorts
// @match        *://*.youtube.com/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(function () {
  "use strict";

  const STORAGE_KEY_ENABLED = "yt_autoshorts_enabled_v1";
  const STORAGE_KEY_PAUSE_COMMENTS = "yt_autoshorts_pause_comments_v1";

  const state = {
    enabled: localStorage.getItem(STORAGE_KEY_ENABLED) !== "false",
    pauseOnComments: localStorage.getItem(STORAGE_KEY_PAUSE_COMMENTS) !== "false",
    lastScrollAt: 0,
    maxRatioForCurrentVideo: 0,
    lastVideoSrc: ""
  };

  function setEnabled(val) {
    state.enabled = Boolean(val);
    localStorage.setItem(STORAGE_KEY_ENABLED, String(state.enabled));
  }

  function setPauseOnComments(val) {
    state.pauseOnComments = Boolean(val);
    localStorage.setItem(STORAGE_KEY_PAUSE_COMMENTS, String(state.pauseOnComments));
  }

  function isShortsPage() {
    return location.pathname.startsWith("/shorts");
  }

  function isCommentsOpen() {
    if (!state.pauseOnComments) return false;

    const desktopOpen = document.querySelector(
      'ytd-engagement-panel-section-list-renderer[visibility="ENGAGEMENT_PANEL_VISIBILITY_EXPANDED"]'
    );
    if (desktopOpen) return true;

    const mobileOpen = document.querySelector(
      "ytm-engagement-panel-section-list-renderer, .engagement-panel-container"
    );
    if (mobileOpen && mobileOpen.offsetParent !== null) return true;

    return false;
  }

  function advanceToNextShort() {
    const now = Date.now();
    if (now - state.lastScrollAt < 1400) return;
    if (isCommentsOpen()) return;

    state.lastScrollAt = now;
    state.maxRatioForCurrentVideo = 0;

    // 1. 데스크톱/모바일 다음 쇼츠 버튼
    const nextBtn =
      document.querySelector("#navigation-button-down button") ||
      document.querySelector('button[aria-label*="다음 동영상"]') ||
      document.querySelector('button[aria-label*="Next video"]');
    if (nextBtn) {
      nextBtn.click();
      return;
    }

    // 2. 모바일(iPhone) Shorts 스크롤 컨테이너에서 다음 슬라이드로 부드럽게 이동
    const activeSlide =
      document.querySelector("ytm-reel-item-renderer.reel-item-active") ||
      document.querySelector("ytd-reel-video-renderer[is-active]") ||
      document.querySelector(".reel-player-overlay-main-content")?.closest("ytm-reel-item-renderer");

    if (activeSlide && activeSlide.nextElementSibling) {
      activeSlide.nextElementSibling.scrollIntoView({ behavior: "smooth", block: "center" });
      return;
    }

    // 3. 모바일 쇼츠 피드 컨테이너 강제 스크롤 (1 화면 높이만큼 아래로)
    const reelSequence =
      document.querySelector("#shorts-container") ||
      document.querySelector("ytm-reel-shelf-renderer") ||
      document.scrollingElement ||
      document.documentElement;
    if (reelSequence) {
      reelSequence.scrollBy({ top: window.innerHeight, behavior: "smooth" });
    }

    // 4. 키보드 ArrowDown 이벤트 폴백
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

  function bindShortsVideo() {
    if (!isShortsPage()) return;

    const videos = Array.from(document.querySelectorAll("video"));
    const video =
      videos.find((v) => !v.paused && v.readyState >= 2 && v.offsetParent !== null) || videos[0];
    if (!video) return;

    if (state.enabled && video.hasAttribute("loop")) {
      video.removeAttribute("loop");
      video.loop = false;
    }

    if (video.dataset.ytAutoShortsBound === "1") return;
    video.dataset.ytAutoShortsBound = "1";

    video.addEventListener("timeupdate", () => {
      if (!state.enabled || !isShortsPage()) return;
      const dur = video.duration;
      const cur = video.currentTime;
      if (!dur || !isFinite(dur) || dur <= 0.4) return;

      if (video.currentSrc !== state.lastVideoSrc) {
        state.lastVideoSrc = video.currentSrc;
        state.maxRatioForCurrentVideo = 0;
      }

      const ratio = cur / dur;
      const reachedEnd = ratio >= 0.985;
      const loopedBack = state.maxRatioForCurrentVideo >= 0.85 && ratio < 0.12;

      if (reachedEnd || loopedBack) {
        advanceToNextShort();
        return;
      }

      if (ratio > state.maxRatioForCurrentVideo) {
        state.maxRatioForCurrentVideo = ratio;
      }
    });

    video.addEventListener("ended", () => {
      if (!state.enabled || !isShortsPage()) return;
      advanceToNextShort();
    });
  }

  // 유튜브 내 설정 메뉴(⋮ 바텀시트 / 설정 리스트)가 열렸을 때만 내부에 '쇼츠 자동 넘김' 토글 항목 주입
  function injectSettingsMenuItem() {
    const menus = document.querySelectorAll(
      "tp-yt-paper-listbox#items, .menu-content, ytm-menu-popup-renderer ul, bottom-sheet-layout"
    );

    menus.forEach((menu) => {
      if (menu.querySelector(".yt-autoshorts-menu-row")) return;

      const row = document.createElement("div");
      row.className = "yt-autoshorts-menu-row";
      row.style.cssText =
        "display:flex;align-items:center;justify-content:space-between;padding:12px 16px;cursor:pointer;font-size:14px;color:#f1f1f1;border-top:1px solid rgba(255,255,255,0.1);";

      const titleSpan = document.createElement("span");
      titleSpan.textContent = "쇼츠 자동 넘김 (반복 재생 방지)";

      const badgeSpan = document.createElement("span");
      badgeSpan.style.cssText = "font-weight:700;margin-left:12px;";

      const updateBadge = () => {
        badgeSpan.textContent = state.enabled ? "켜짐 (ON)" : "꺼짐 (OFF)";
        badgeSpan.style.color = state.enabled ? "#3ea6ff" : "#888888";
      };
      updateBadge();

      row.appendChild(titleSpan);
      row.appendChild(badgeSpan);

      row.addEventListener("click", (e) => {
        e.stopPropagation();
        setEnabled(!state.enabled);
        updateBadge();
      });

      menu.appendChild(row);
    });
  }

  setInterval(() => {
    bindShortsVideo();
    injectSettingsMenuItem();
  }, 250);
})();

