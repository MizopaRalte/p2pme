// Cloudflare Pages Function: /api/hub/announce
// Zero-Knowledge 24/7 Server Hub Announcement Endpoint

const memoryStore = new Map();
const TTL_MS = 15 * 60 * 1000; // 15 minutes TTL

export async function onRequestOptions() {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, X-P2Pme-Version',
      'Access-Control-Max-Age': '86400',
    },
  });
}

export async function onRequestPost({ request, env }) {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-P2Pme-Version',
    'Content-Type': 'application/json',
  };

  try {
    const data = await request.json();
    const { hub_id, public_ip, public_port, local_ip, local_port, device_name, upnp_active } = data;

    // Validation: hub_id must be a 64-character hex string (SHA-256 hash of secret key)
    if (!hub_id || typeof hub_id !== 'string' || hub_id.length !== 64) {
      return new Response(
        JSON.stringify({ error: 'Invalid hub_id. Must be 64-character SHA-256 hex string.' }),
        { status: 400, headers: corsHeaders }
      );
    }

    // Determine client's public IP from Cloudflare header if not supplied or mismatched
    const cfConnectingIp = request.headers.get('cf-connecting-ip') || '';
    const resolvedPublicIp = (public_ip && public_ip.trim().length > 0) ? public_ip.trim() : cfConnectingIp;
    const resolvedPublicPort = Number(public_port) || 45455;

    const record = {
      hub_id,
      public_ip: resolvedPublicIp,
      public_port: resolvedPublicPort,
      local_ip: local_ip || '',
      local_port: Number(local_port) || 45455,
      device_name: (device_name || 'Server Hub').substring(0, 64),
      upnp_active: Boolean(upnp_active),
      updated_at: Date.now(),
      expires_at: Date.now() + TTL_MS,
    };

    // Store in global memory map
    memoryStore.set(hub_id, record);

    // If Cloudflare KV is bound, also persist to KV
    if (env && env.HUB_REGISTRY) {
      try {
        await env.HUB_REGISTRY.put(`hub:${hub_id}`, JSON.stringify(record), {
          expirationTtl: 900, // 15 minutes
        });
      } catch (kvErr) {
        console.warn('KV write error (falling back to memory):', kvErr);
      }
    }

    return new Response(
      JSON.stringify({
        status: 'announced',
        hub_id,
        resolved_public_ip: resolvedPublicIp,
        resolved_public_port: resolvedPublicPort,
        expires_in_seconds: 900,
      }),
      { status: 200, headers: corsHeaders }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message || 'Malformed JSON payload' }),
      { status: 400, headers: corsHeaders }
    );
  }
}
