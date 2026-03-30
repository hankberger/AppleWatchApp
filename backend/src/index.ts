export interface Env {
  AUDIO_BUCKET: R2Bucket;
}

const MAX_FILE_SIZE = 25 * 1024 * 1024; // 25MB

const ALLOWED_CONTENT_TYPES = new Set([
  "audio/mpeg",
  "audio/wav",
  "audio/x-wav",
  "audio/mp4",
  "audio/m4a",
  "audio/x-m4a",
  "audio/aac",
  "audio/ogg",
  "audio/webm",
  "audio/x-caf",
]);

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/upload" && request.method === "POST") {
      return handleUpload(request, env);
    }

    if (url.pathname === "/link-account" && request.method === "POST") {
      return handleLinkAccount(request, env);
    }

    if (url.pathname === "/recordings" && request.method === "GET") {
      return handleListRecordings(request, env);
    }

    if (url.pathname === "/health" && request.method === "GET") {
      return Response.json({ status: "ok" });
    }

    return Response.json({ error: "Not found" }, { status: 404 });
  },
} satisfies ExportedHandler<Env>;

async function handleUpload(request: Request, env: Env): Promise<Response> {
  const contentType = request.headers.get("content-type") ?? "";
  const contentLength = parseInt(request.headers.get("content-length") ?? "0", 10);

  if (!ALLOWED_CONTENT_TYPES.has(contentType)) {
    return Response.json(
      { error: `Unsupported content type: ${contentType}` },
      { status: 400 }
    );
  }

  if (contentLength > MAX_FILE_SIZE) {
    return Response.json(
      { error: `File too large. Max size is ${MAX_FILE_SIZE / 1024 / 1024}MB` },
      { status: 413 }
    );
  }

  const userId = request.headers.get("x-user-id") ?? "";
  if (!userId || !/^[a-zA-Z0-9.-]+$/.test(userId)) {
    return Response.json(
      { error: "Missing or invalid X-User-ID header" },
      { status: 400 }
    );
  }

  if (!request.body) {
    return Response.json({ error: "No body provided" }, { status: 400 });
  }

  const extension = getExtension(contentType);
  const recordingId = crypto.randomUUID();
  const key = `${userId}/${recordingId}/audio${extension}`;

  const object = await env.AUDIO_BUCKET.put(key, request.body, {
    httpMetadata: { contentType },
    customMetadata: {
      uploadedAt: new Date().toISOString(),
    },
  });

  return Response.json(
    {
      key: object.key,
      size: object.size,
      uploaded: object.uploaded.toISOString(),
    },
    { status: 201 }
  );
}

async function handleLinkAccount(request: Request, env: Env): Promise<Response> {
  let body: { oldUserId?: string; newUserId?: string };
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { oldUserId, newUserId } = body;
  if (!oldUserId || !newUserId) {
    return Response.json(
      { error: "Missing oldUserId or newUserId" },
      { status: 400 }
    );
  }

  if (!/^[a-zA-Z0-9.-]+$/.test(oldUserId) || !/^[a-zA-Z0-9.-]+$/.test(newUserId)) {
    return Response.json({ error: "Invalid user ID format" }, { status: 400 });
  }

  // List all objects under the old user's folder
  const listed = await env.AUDIO_BUCKET.list({ prefix: `${oldUserId}/` });

  let moved = 0;
  for (const obj of listed.objects) {
    // Copy each object to the new user's folder, preserving subfolder structure
    const newKey = obj.key.replace(`${oldUserId}/`, `${newUserId}/`);
    const source = await env.AUDIO_BUCKET.get(obj.key);
    if (!source) continue;

    await env.AUDIO_BUCKET.put(newKey, source.body, {
      httpMetadata: source.httpMetadata,
      customMetadata: source.customMetadata,
    });
    await env.AUDIO_BUCKET.delete(obj.key);
    moved++;
  }

  return Response.json({ moved, newUserId });
}

function getExtension(contentType: string): string {
  const map: Record<string, string> = {
    "audio/mpeg": ".mp3",
    "audio/wav": ".wav",
    "audio/x-wav": ".wav",
    "audio/mp4": ".m4a",
    "audio/m4a": ".m4a",
    "audio/x-m4a": ".m4a",
    "audio/aac": ".aac",
    "audio/ogg": ".ogg",
    "audio/webm": ".webm",
    "audio/x-caf": ".caf",
  };
  return map[contentType] ?? "";
}
