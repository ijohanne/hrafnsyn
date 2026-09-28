(() => {
  const setTheme = (theme) => {
    if (theme === "system") {
      localStorage.removeItem("phx:theme");
      document.documentElement.removeAttribute("data-theme");
    } else {
      localStorage.setItem("phx:theme", theme);
      document.documentElement.setAttribute("data-theme", theme);
    }
  };

  if (!document.documentElement.hasAttribute("data-theme")) {
    setTheme(localStorage.getItem("phx:theme") || "system");
  }

  window.addEventListener("storage", (event) => {
    if (event.key === "phx:theme") setTheme(event.newValue || "system");
  });
  window.addEventListener("phx:set-theme", (event) => setTheme(event.target.dataset.phxTheme));
})();
