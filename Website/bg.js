// Abstract background: a slow field of faceted wireframe solids in the accent color.
// Loaded as a module after page load; the page works without it.
import * as T from "./vendor/three.min.js";

const canvas = document.getElementById("bg");
const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;

let renderer;
try {
  renderer = new T.WebGLRenderer({ canvas, alpha: true, antialias: true });
} catch (e) {
  console.warn("WebGL unavailable, background skipped:", e);
  canvas.remove();
}

if (renderer) {
  renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
  const scene = new T.Scene();
  const camera = new T.PerspectiveCamera(50, 1, 0.1, 100);
  camera.position.z = 14;

  // Fixed seed-like layout so the composition is stable between reloads
  const geos = [new T.IcosahedronGeometry(1, 0), new T.OctahedronGeometry(1, 0), new T.TorusGeometry(1, 0.32, 8, 14)];
  const lineMat = new T.LineBasicMaterial({ transparent: true, opacity: 0.5 });
  const fillMat = new T.MeshBasicMaterial({ transparent: true, opacity: 0.05 });
  const group = new T.Group();
  const items = [];
  for (let i = 0; i < 16; i++) {
    const g = geos[i % geos.length];
    const s = 0.7 + ((i * 37) % 10) / 6;
    const mesh = new T.Mesh(g, fillMat);
    mesh.add(new T.LineSegments(new T.EdgesGeometry(g), lineMat));
    mesh.scale.setScalar(s);
    mesh.position.set(((i * 53) % 29) - 14, ((i * 31) % 19) - 9, -((i * 17) % 12) - 1);
    mesh.rotation.set(i, i * 2, 0);
    mesh.userData = { spin: 0.04 + (i % 5) * 0.012, bob: i * 1.3 };
    group.add(mesh);
    items.push(mesh);
  }
  scene.add(group);

  // Follow the page theme: read the accent token whenever the theme changes
  function tint() {
    const c = new T.Color(getComputedStyle(document.documentElement).getPropertyValue("--accent").trim());
    lineMat.color.copy(c); fillMat.color.copy(c);
    const dark = getComputedStyle(document.documentElement).colorScheme === "dark";
    lineMat.opacity = dark ? 0.45 : 0.3;
  }
  tint();
  new MutationObserver(tint).observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", tint);

  function resize() {
    const w = innerWidth, h = innerHeight;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }
  addEventListener("resize", resize);
  resize();

  let mx = 0, my = 0;
  addEventListener("pointermove", (e) => {
    mx = e.clientX / innerWidth - 0.5;
    my = e.clientY / innerHeight - 0.5;
  });

  let last = performance.now(), t = 0, raf = 0;
  function frame(now) {
    const dt = Math.min((now - last) / 1000, 0.1);
    last = now; t += dt;
    for (const m of items) {
      m.rotation.x += m.userData.spin * dt;
      m.rotation.y += m.userData.spin * 1.4 * dt;
      m.position.y += Math.sin(t * 0.25 + m.userData.bob) * 0.15 * dt;
    }
    // Depth parallax: pointer and page scroll move the camera, not the objects
    camera.position.x += (mx * 3 - camera.position.x) * 0.03;
    const targetY = -my * 2 - (scrollY / Math.max(document.body.scrollHeight, 1)) * 10;
    camera.position.y += (targetY - camera.position.y) * 0.03;
    camera.lookAt(0, camera.position.y * 0.5, 0);
    renderer.render(scene, camera);
    raf = requestAnimationFrame(frame);
  }

  if (reduce) {
    renderer.render(scene, camera);
  } else {
    raf = requestAnimationFrame(frame);
    document.addEventListener("visibilitychange", () => {
      cancelAnimationFrame(raf);
      if (!document.hidden) { last = performance.now(); raf = requestAnimationFrame(frame); }
    });
  }
}
