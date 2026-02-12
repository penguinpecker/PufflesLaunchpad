export async function onRequest(context) {
  const url = new URL(context.request.url);
  const path = url.pathname;

  // /launch → serve launch.html
  if (path === "/launch" || path === "/launch/") {
    const res = await context.env.ASSETS.fetch(new URL("/launch.html", url));
    return new Response(res.body, { status: res.status, headers: res.headers });
  }

  // /mint or /mint/{slug} → serve mint.html
  if (path === "/mint" || path === "/mint/" || path.startsWith("/mint/")) {
    const res = await context.env.ASSETS.fetch(new URL("/mint.html", url));
    return new Response(res.body, { status: res.status, headers: res.headers });
  }

  // /collection or /collection/{slug} → serve collection.html
  if (path === "/collection" || path === "/collection/" || path.startsWith("/collection/")) {
    const res = await context.env.ASSETS.fetch(new URL("/collection.html", url));
    return new Response(res.body, { status: res.status, headers: res.headers });
  }

  // Everything else → pass through to static assets
  return context.next();
}
