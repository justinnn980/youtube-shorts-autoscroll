document.addEventListener("DOMContentLoaded", () => {
  const toggleAutoScroll = document.getElementById("toggleAutoScroll");
  const togglePauseComments = document.getElementById("togglePauseComments");

  if (typeof chrome !== "undefined" && chrome.storage && chrome.storage.local) {
    chrome.storage.local.get(
      {
        autoScrollEnabled: true,
        pauseOnComments: true
      },
      (res) => {
        toggleAutoScroll.checked = Boolean(res.autoScrollEnabled);
        togglePauseComments.checked = Boolean(res.pauseOnComments);
      }
    );

    toggleAutoScroll.addEventListener("change", () => {
      chrome.storage.local.set({ autoScrollEnabled: toggleAutoScroll.checked });
    });

    togglePauseComments.addEventListener("change", () => {
      chrome.storage.local.set({ pauseOnComments: togglePauseComments.checked });
    });
  }
});

