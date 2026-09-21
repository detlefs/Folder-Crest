// Theme, language, hero stage and scroll reveal. No build step, no framework.
(function () {
  "use strict";
  var root = document.documentElement;
  root.classList.add("js");
  var reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;

  function store(key, value) {
    try { value == null ? localStorage.removeItem(key) : localStorage.setItem(key, value); }
    catch (e) { console.warn("localStorage unavailable:", e); }
  }

  // Language toggle
  document.getElementById("lang-toggle").addEventListener("click", function () {
    var next = root.lang === "de" ? "en" : "de";
    root.lang = next;
    store("fc-lang", next);
    document.querySelectorAll("[data-release]").forEach(function (a) {
      a.textContent = next === "de" ? "Herunterladen" : "Download";
    });
  });

  // Theme toggle: auto -> light -> dark
  var themeBtn = document.querySelector(".theme-label");
  var modes = ["auto", "light", "dark"];
  function applyMode(mode) {
    if (mode === "auto") delete root.dataset.theme; else root.dataset.theme = mode;
    themeBtn.dataset.mode = mode;
    themeBtn.textContent = { auto: "Auto", light: "Light", dark: "Dark" }[mode];
    store("fc-theme", mode === "auto" ? null : mode);
  }
  applyMode(root.dataset.theme || "auto");
  themeBtn.parentElement.addEventListener("click", function () {
    applyMode(modes[(modes.indexOf(themeBtn.dataset.mode) + 1) % 3]);
  });

  // Initial button label in German
  if (root.lang === "de") {
    document.querySelectorAll("[data-release]").forEach(function (a) { a.textContent = "Herunterladen"; });
  }

  // Tint demo: hue-rotate stands in for the app's tint
  var preview = document.getElementById("tint-preview");
  document.querySelectorAll(".sw").forEach(function (sw) {
    sw.addEventListener("click", function () {
      document.querySelectorAll(".sw").forEach(function (o) { o.setAttribute("aria-pressed", String(o === sw)); });
      preview.style.setProperty("--hue", sw.dataset.hue + "deg");
    });
  });

  if (reduce) return;

  // Hero: icon rotation (state change) and pointer tilt (feedback)
  var slides = document.querySelectorAll(".slide"), i = 0;
  setInterval(function () {
    slides[i].classList.remove("is-on");
    i = (i + 1) % slides.length;
    slides[i].classList.add("is-on");
  }, 3200);

  var stage = document.getElementById("stage");
  stage.parentElement.addEventListener("pointermove", function (e) {
    var r = stage.getBoundingClientRect();
    var x = (e.clientX - r.left) / r.width - 0.5, y = (e.clientY - r.top) / r.height - 0.5;
    stage.style.setProperty("--rx", (x * 14).toFixed(2) + "deg");
    stage.style.setProperty("--ry", (-y * 14).toFixed(2) + "deg");
  });
  stage.parentElement.addEventListener("pointerleave", function () {
    stage.style.setProperty("--rx", "0deg");
    stage.style.setProperty("--ry", "0deg");
  });

  // Scroll reveal: shows each feature as it enters, in reading order
  window.addEventListener("load", function () {
    if (!window.gsap || !window.ScrollTrigger) {
      document.querySelectorAll(".reveal").forEach(function (el) { el.style.cssText = "opacity:1;transform:none"; });
      return;
    }
    gsap.registerPlugin(ScrollTrigger);
    ScrollTrigger.batch(".reveal", {
      start: "top 88%", once: true,
      onEnter: function (els) { gsap.to(els, { opacity: 1, y: 0, duration: .9, ease: "expo.out", stagger: .12 }); }
    });
  });
})();
