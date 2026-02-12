export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    // Static files (anything with a dot/extension) → serve from assets
    if (/\.\w+$/.test(path)) {
      return env.ASSETS.fetch(request);
    }

    // / → marketplace home
    if (path === "/" || path === "") {
      return env.ASSETS.fetch(new Request(new URL("/index.html", url), request));
    }

    // /launch → launchpad portfolio
    if (path === "/launch" || path === "/launch/") {
      return env.ASSETS.fetch(new Request(new URL("/launch.html", url), request));
    }

    // /mint or /mint/{anything} → mint page
    if (path === "/mint" || path === "/mint/" || path.startsWith("/mint/")) {
      return env.ASSETS.fetch(new Request(new URL("/mint.html", url), request));
    }

    // /collection or /collection/{anything} → collection page
    if (path === "/collection" || path === "/collection/" || path.startsWith("/collection/")) {
      return env.ASSETS.fetch(new Request(new URL("/collection.html", url), request));
    }

    // Everything else → marketplace home
    return env.ASSETS.fetch(new Request(new URL("/index.html", url), request));
  },
};
