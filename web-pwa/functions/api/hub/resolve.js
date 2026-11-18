// Cloudflare Pages Function: /api/hub/resolve
// Zero-Knowledge 24/7 Server Hub Resolution Endpoint

const memoryStore = new Map();

export async function onRequestOptions() {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, X-P2Pme-Version',
      'Access-Control-Max-Age': '86400',
    },
  });
}

export async function onRequestGet({ request, env }) {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-P2Pme-Version',
    'Content-Type': 'application/json',
  };

  const url = new URL(request.url);
  const hub_id = url.searchParams.get('hub_id') || url.searchParams.get('id');

  if (!hub_id || typeof hub_id !== 'string' || hub_id.length !== 64) {
    return new Response(
      JSON.stringify({ error: 'Missing or invalid hub_id parameter. Must be 64-character SHA-256 hex string.' }),
      { status: 400, headers: corsHeaders }
    );
  }

  let record = null;

  // 1. Check Cloudflare KV first if bound
  if (env && env.HUB_REGISTRY) {
    try {
      const kvData = await env.HUB_REGISTRY.get(`hub:${hub_id}`);
      if (kvData) {
        record = JSON.parse(kvData);
      }
    } catch (kvErr) {
      console.warn('KV read error:', kvErr);
    }
  }

  // 2. Fall back to memoryStore
  if (!record && memoryStore.has(hub_id)) {
    const memRecord = memoryStore.get(hub_id);
    if (Date.now() < memRecord.expires_at) {
      record = memRecord;
    } else {
      memoryStore.delete(hub_id);
    }
  }

  if (!record) {
    return new Response(
      JSON.stringify({
        status: 'not_found',
        hub_id,
        message: 'No active server hub found with this ID or announcement expired.',
      }),
      { status: 404, headers: corsHeaders }
    );
  }

  return new Response(
    JSON.stringify({
      status: 'active',
      hub_id: record.hub_id,
      public_ip: record.public_ip,
      public_port: record.public_port,
      local_ip: record.local_ip,
      local_port: record.local_port,
      device_name: record.device_name,
      upnp_active: record.upnp_active,
      updated_at: record.updated_at,
      age_seconds: Math.floor((Date.now() - record.updated_at) / 1000),
    }),
    { status: 200, headers: corsHeaders }
  );
}
