export async function onRequestGet({ request }) {
  try {
    const url = new URL(request.url);
    const pin = (url.searchParams.get("pin") || "").trim();
    if (!pin || pin.length !== 6) {
      return new Response(JSON.stringify({ error: "Invalid 6-digit PIN" }), {
        status: 400,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      });
    }

    const cacheKey = new URL(`/api/drop/resolve?pin=${pin}`, request.url);
    const cached = await caches.default.match(cacheKey.toString());
    if (cached) {
      return cached;
    }

    return new Response(JSON.stringify({ status: "not_found", message: "Drop session expired or not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  }
}

export async function onRequestOptions() {
  return new Response(null, {
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    },
  });
}
