export async function onRequestPost({ request }) {
  try {
    const data = await request.json();
    const hubId = (data.hub_id || "").toString().trim();
    if (!hubId) {
      return new Response(JSON.stringify({ error: "Missing hub_id" }), {
        status: 400,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      });
    }

    // Auto-detect connecting client's public IP from Cloudflare header CF-Connecting-IP
    const clientIp = request.headers.get("CF-Connecting-IP") || request.headers.get("x-real-ip") || data.public_ip || "";

    const cacheKey = new URL(`/api/hub/resolve?hub_id=${hubId}`, request.url);
    const payload = JSON.stringify({
      status: "ok",
      hub_id: hubId,
      public_ip: clientIp,
      public_port: data.public_port || 45455,
      upnp_active: !!data.upnp_active,
      updated_at: Date.now(),
    });

    const cacheResponse = new Response(payload, {
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "public, max-age=3600", // 1 hour TTL
        "Access-Control-Allow-Origin": "*",
      },
    });

    await caches.default.put(cacheKey.toString(), cacheResponse);

    return new Response(JSON.stringify({ status: "ok", public_ip: clientIp, public_port: data.public_port || 45455 }), {
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
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    },
  });
}
