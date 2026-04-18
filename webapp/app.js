// ── MSAL Configuration ────────────────────────────────────────────────────────
// Replace these values after completing docs/04-configure-entra.md
const msalConfig = {
  auth: {
    // Your Entra External ID tenant ID (format: <tenant-name>.onmicrosoft.com)
    authority: "https://<YOUR_TENANT>.ciamlogin.com/<YOUR_TENANT>.onmicrosoft.com",
    clientId: "<YOUR_APP_CLIENT_ID>",
    redirectUri: window.location.origin + "/index.html",
    postLogoutRedirectUri: window.location.origin + "/index.html",
  },
  cache: {
    cacheLocation: "sessionStorage",
    storeAuthStateInCookie: false,
  },
};

const loginRequest = {
  scopes: ["openid", "profile", "email"],
};

const msalInstance = new msal.PublicClientApplication(msalConfig);

// ── Handle redirect response on page load ────────────────────────────────────
msalInstance.handleRedirectPromise().then((response) => {
  if (response) {
    renderProfile(response.account, response.idTokenClaims);
  } else {
    const accounts = msalInstance.getAllAccounts();
    if (accounts.length > 0) {
      renderProfile(accounts[0], parseIdToken(accounts[0].idTokenClaims));
    }
  }
}).catch((err) => {
  console.error("MSAL redirect error:", err);
});

function signIn() {
  msalInstance.loginRedirect(loginRequest);
}

function signOut() {
  msalInstance.logoutRedirect();
}

function renderProfile(account, claims) {
  document.getElementById("landing").classList.add("hidden");
  document.getElementById("profile").classList.remove("hidden");

  const name = account.name || claims?.name || "User";
  const email = account.username || claims?.email || "";
  const initials = name.split(" ").map(n => n[0]).join("").toUpperCase().slice(0, 2);

  document.getElementById("display-name").textContent = `Welcome, ${name}`;
  document.getElementById("user-email").textContent = email;
  document.getElementById("avatar").textContent = initials;

  const displayClaims = {
    sub: claims?.sub,
    email: claims?.email,
    name: claims?.name,
    given_name: claims?.given_name,
    family_name: claims?.family_name,
    // idp shows the federated identity provider Entra used (should be Keycloak)
    idp: claims?.idp,
    iss: claims?.iss,
    aud: claims?.aud,
    iat: claims?.iat ? new Date(claims.iat * 1000).toISOString() : undefined,
    exp: claims?.exp ? new Date(claims.exp * 1000).toISOString() : undefined,
  };

  document.getElementById("claims-box").textContent =
    JSON.stringify(displayClaims, null, 2);
}

function parseIdToken(claims) {
  return claims || {};
}

// ── Canvas background animation ───────────────────────────────────────────────
(function initBgCanvas() {
  const canvas = document.getElementById("bg-canvas");
  const ctx = canvas.getContext("2d");
  let particles = [];
  const COUNT = 60;

  function resize() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
  }
  window.addEventListener("resize", resize);
  resize();

  for (let i = 0; i < COUNT; i++) {
    particles.push({
      x: Math.random() * canvas.width,
      y: Math.random() * canvas.height,
      r: Math.random() * 2 + 0.5,
      dx: (Math.random() - 0.5) * 0.4,
      dy: (Math.random() - 0.5) * 0.4,
      alpha: Math.random() * 0.5 + 0.2,
    });
  }

  function draw() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Draw connection lines between nearby particles
    for (let i = 0; i < particles.length; i++) {
      for (let j = i + 1; j < particles.length; j++) {
        const dx = particles[i].x - particles[j].x;
        const dy = particles[i].y - particles[j].y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < 140) {
          ctx.beginPath();
          ctx.strokeStyle = `rgba(88,101,242,${(1 - dist / 140) * 0.3})`;
          ctx.lineWidth = 0.5;
          ctx.moveTo(particles[i].x, particles[i].y);
          ctx.lineTo(particles[j].x, particles[j].y);
          ctx.stroke();
        }
      }
    }

    // Draw particles
    for (const p of particles) {
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(88,101,242,${p.alpha})`;
      ctx.fill();

      p.x += p.dx;
      p.y += p.dy;
      if (p.x < 0 || p.x > canvas.width) p.dx *= -1;
      if (p.y < 0 || p.y > canvas.height) p.dy *= -1;
    }

    requestAnimationFrame(draw);
  }
  draw();
})();

// ── Logo canvas ───────────────────────────────────────────────────────────────
(function initLogoCanvas() {
  const canvas = document.getElementById("logo-canvas");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const cx = 40, cy = 40, r = 30;

  const grad = ctx.createRadialGradient(cx - 8, cy - 8, 4, cx, cy, r);
  grad.addColorStop(0, "#7c8af7");
  grad.addColorStop(1, "#5865f2");

  ctx.beginPath();
  ctx.arc(cx, cy, r, 0, Math.PI * 2);
  ctx.fillStyle = grad;
  ctx.fill();

  // Lock icon
  ctx.strokeStyle = "#fff";
  ctx.lineWidth = 2.5;
  ctx.lineCap = "round";

  // Shackle
  ctx.beginPath();
  ctx.arc(cx, cy - 4, 9, Math.PI, 0);
  ctx.stroke();

  // Body
  ctx.fillStyle = "rgba(255,255,255,0.9)";
  ctx.beginPath();
  ctx.roundRect(cx - 10, cy + 2, 20, 14, 3);
  ctx.fill();

  // Keyhole
  ctx.fillStyle = "#5865f2";
  ctx.beginPath();
  ctx.arc(cx, cy + 9, 3, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillRect(cx - 1.5, cy + 9, 3, 5);
})();
