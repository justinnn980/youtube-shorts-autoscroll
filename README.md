# YouTube Shorts 자동 넘김 (iOS & Android 순정 유튜브 앱 연동)

사용자가 원래 쓰던 **순정 YouTube 공식 앱**을 그대로 사용하면서, **쇼츠 영상이 끝까지 재생되면(반복 재생 직전) 자동으로 다음 쇼츠로 넘겨주는** 크로스플랫폼 프로젝트입니다.

* **순정 UI 100% 유지**: 유튜브 영상 화면 위에 거슬리는 플로팅 버튼을 절대 띄우지 않습니다.
* **설정(Settings)에서 ON/OFF**: 설정 화면에 들어가서 `쇼츠 자동 넘김`과 `댓글창 열람 시 일시정지`를 깔끔하게 켜고 끌 수 있습니다.
* **정확한 영상 종료 시점 감지**: 진행바(`reel_progress_bar` / `currentVideoMediaTime`)가 98.8% 이상 도달하거나 루프(되감기)되는 시점을 포착해 다음 쇼츠로 스크롤합니다.

---

## 📂 프로젝트 구조

1. **[`android/`](./android)** — **안드로이드 순정 YouTube 앱 연동 네이티브 앱 (Kotlin)**
   * [`ShortsAutoScrollService.kt`](./android/app/src/main/java/com/autoshorts/youtube/ShortsAutoScrollService.kt): 공식 유튜브 앱(`com.google.android.youtube`)의 쇼츠 플레이어와 진행바(`reel_progress_bar`)를 실시간 감지하여 영상이 끝날 때 자동으로 다음 쇼츠로 넘깁니다.
   * [`MainActivity.kt`](./android/app/src/main/java/com/autoshorts/youtube/MainActivity.kt): 유튜브 다크모드 디자인과 동일한 **설정(Settings) 전용 화면**입니다.
2. **[`ios-tweak/`](./ios-tweak)** — **아이폰 순정 YouTube 앱 내부 탑재 트윅 (Objective-C / Logos)**
   * [`Tweak.x`](./ios-tweak/Tweak.x): 아이폰 순정 유튜브 앱(`com.google.ios.youtube`)의 `YTReelPlayerViewController`와 `YTSettingsViewController`를 직접 후킹하여, **유튜브 앱 내부 설정 화면에 `[쇼츠 자동 넘김]` 토글을 추가**하고 영상 종료 시 다음 쇼츠로 스크롤합니다.
   * [`build-ipa.sh`](./ios-tweak/build-ipa.sh): `YouTube.ipa`에 트윅(`.dylib`)을 주입하여 Sideloadly / AltStore / SideStore로 순정 아이폰에 설치할 수 있는 패키징 스크립트입니다.
3. **[`ios-extension/`](./ios-extension)** — **아이폰 Safari 웹 확장 프로그램 & 크롬 확장 프로그램**
   * [`content.js`](./ios-extension/content.js) / [`popup.html`](./ios-extension/popup.html): 사이드로딩 없이 앱스토어/웹스토어로 배포할 수 있는 확장 모듈입니다.
4. **[`simulator/index.html`](./simulator/index.html)** — **즉시 테스트 가능한 순정 유튜브 앱 & 설정 시뮬레이터**
   * 브라우저에서 바로 열어서 유튜브 내 **[⚙️ 설정]** 진입 후 ON/OFF 스위치 조작, 쇼츠 100% 재생 시 자동 넘김, 댓글창 열람 시 일시정지 동작을 확인할 수 있습니다.

