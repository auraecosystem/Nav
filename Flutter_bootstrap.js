const STATE = {
  LOADING: "loading",
  READY: "ready",
  ERROR: "error"
};

function setState(state, msg) {
  const status = document.getElementById("status");
  const loader = document.getElementById("loader");

  if (status) status.innerText = msg;

  if (state === STATE.READY && loader) {
    loader.style.display = "none";
  }

  if (state === STATE.ERROR && loader) {
    loader.style.borderColor = "red";
  }
}

// Service Worker
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("service-worker.js")
    .catch(() => setState(STATE.ERROR, "Offline system failed"));
}

window.addEventListener("load", async () => {
  setState(STATE.LOADING, "Booting Web4 runtime...");

  try {
    if (!window._flutter?.loader) {
      throw new Error("Flutter runtime missing");
    }

    _flutter.loader.loadEntrypoint({
      onEntrypointLoaded: async (engineInitializer) => {
        const appRunner = await engineInitializer.initializeEngine();
        await appRunner.runApp();

        setState(STATE.READY, "System Online");
      }
    });

  } catch (err) {
    console.error(err);
    setState(STATE.ERROR, "Boot failed");
  }
});

// Voice hook (upgrade path)
function toggleVoice() {
  if (!("speechSynthesis" in window)) {
    alert("Voice not supported in this browser");
    return;
  }

  const msg = new SpeechSynthesisUtterance("AI Voice system activated");
  speechSynthesis.speak(msg);
}
