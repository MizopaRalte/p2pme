export async function onRequestPost({ request }) {
  try {
    const data = await request.json();
    const pin = (data.pin || "").toString().trim();
    if (!pin || pin.length !== 6) {
      return new Response(JSON.stringify({ error: "Invalid 6-digit PIN" }), {
        status: 400,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      });
    }

    const cacheKey = new URL(`/api/drop/resolve?pin=${pin}`, request.url);
    const payload = JSON.stringify({
      status: "ok",
      pin,
      drop_id: data.drop_id || "",
      node_id: data.node_id || "",
      direct_addresses: data.direct_addresses || [],
      ticket_payload: data.ticket_payload || "",
      announced_at: Date.now(),
    });

    const cacheResponse = new Response(payload, {
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "public, max-age=600", // 10 minutes TTL
        "Access-Control-Allow-Origin": "*",
      },
    });

    await caches.default.put(cacheKey.toString(), cacheResponse);

    return new Response(JSON.stringify({ status: "ok", pin }), {
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
