// Share links for the web editor, served at play.legalese.com/session.
//
// The API is the one the old jl4-websessions service had:
//   POST /session            body: the program as a JSON string  →  its new id as a JSON string
//   GET  /session?id=<uuid>  →  the program as a JSON string (404 when unknown)
//
// Only CloudFront can call it: it adds the ORIGIN_SECRET header. A POST must
// also come from the editor's origin with a Cloudflare Turnstile token, so
// scripts can't fill the bucket. Programs are immutable once stored.
import { randomUUID, timingSafeEqual } from "node:crypto";
import {
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import { GetParameterCommand, SSMClient } from "@aws-sdk/client-ssm";

const {
  SESSIONS_BUCKET,
  ORIGIN_SECRET,
  ALLOWED_ORIGIN,
  TURNSTILE_HOSTNAME,
  TURNSTILE_SECRET_PARAM,
} = process.env;

const MAX_BODY_BYTES = 1024 * 1024;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SITEVERIFY_URL =
  "https://challenges.cloudflare.com/turnstile/v0/siteverify";

const s3 = new S3Client({});
const ssm = new SSMClient({});

// Read from SSM again after a few minutes, or straight away once Cloudflare
// rejects it, so a new secret takes effect without waiting for warm containers
// to recycle.
const SECRET_MAX_AGE_MS = 5 * 60 * 1000;
let turnstileSecret;
let turnstileSecretReadAt = 0;

async function getTurnstileSecret() {
  if (
    !turnstileSecret ||
    Date.now() - turnstileSecretReadAt > SECRET_MAX_AGE_MS
  ) {
    const { Parameter } = await ssm.send(
      new GetParameterCommand({
        Name: TURNSTILE_SECRET_PARAM,
        WithDecryption: true,
      }),
    );
    turnstileSecret = Parameter.Value;
    turnstileSecretReadAt = Date.now();
  }
  return turnstileSecret;
}

function json(statusCode, value, cacheControl = "no-store") {
  return {
    statusCode,
    headers: {
      "content-type": "application/json",
      "cache-control": cacheControl,
    },
    body: JSON.stringify(value),
  };
}

function hasOriginSecret(headers) {
  const given = Buffer.from(headers["x-origin-secret"] ?? "");
  const expected = Buffer.from(ORIGIN_SECRET);
  return given.length === expected.length && timingSafeEqual(given, expected);
}

async function passesTurnstile(token) {
  if (!token) return false;
  const secret = await getTurnstileSecret();

  const response = await fetch(SITEVERIFY_URL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ secret, response: token }),
  });
  if (!response.ok) return false;
  const result = await response.json();
  if (result["error-codes"]?.includes("invalid-input-secret")) {
    console.error(
      "Cloudflare rejected the Turnstile secret; reading it again next time",
    );
    turnstileSecret = undefined;
  }
  return (
    result.success === true &&
    result.hostname === TURNSTILE_HOSTNAME &&
    result.action === "share"
  );
}

async function createSession(event) {
  const headers = event.headers ?? {};
  if (headers.origin !== ALLOWED_ORIGIN) {
    return json(403, { error: "origin not allowed" });
  }
  if (!(await passesTurnstile(headers["x-turnstile-token"]))) {
    return json(403, { error: "turnstile check failed" });
  }

  const raw = event.isBase64Encoded
    ? Buffer.from(event.body ?? "", "base64").toString("utf8")
    : (event.body ?? "");
  if (Buffer.byteLength(raw, "utf8") > MAX_BODY_BYTES) {
    return json(413, { error: "program is larger than 1 MB" });
  }
  let program;
  try {
    program = JSON.parse(raw);
  } catch {
    program = undefined;
  }
  if (typeof program !== "string") {
    return json(400, { error: "body must be the program as a JSON string" });
  }

  const id = randomUUID();
  await s3.send(
    new PutObjectCommand({
      Bucket: SESSIONS_BUCKET,
      Key: `sessions/${id}.json`,
      Body: JSON.stringify(program),
      ContentType: "application/json",
      IfNoneMatch: "*",
    }),
  );
  return json(200, id);
}

async function readSession(event) {
  const id = event.queryStringParameters?.id ?? "";
  if (!UUID_PATTERN.test(id)) {
    return json(400, { error: "id must be a UUID" });
  }
  try {
    const object = await s3.send(
      new GetObjectCommand({
        Bucket: SESSIONS_BUCKET,
        Key: `sessions/${id.toLowerCase()}.json`,
      }),
    );
    return {
      statusCode: 200,
      headers: {
        "content-type": "application/json",
        // Programs never change, so CloudFront keeps them for a year. Browsers
        // only keep them for an hour: a program taken down (README.md) stops
        // loading once its object is deleted and the edge copy invalidated.
        "cache-control": "public, max-age=3600, s-maxage=31536000",
      },
      // Stored as the JSON string the editor expects, so it goes out as is.
      body: await object.Body.transformToString(),
    };
  } catch (error) {
    if (error.name === "NoSuchKey") {
      return json(404, { error: "no such session" });
    }
    throw error;
  }
}

export async function handler(event) {
  if (!hasOriginSecret(event.headers ?? {})) {
    return json(403, { error: "forbidden" });
  }
  switch (event.requestContext?.http?.method) {
    case "GET":
    case "HEAD":
      return readSession(event);
    case "POST":
      return createSession(event);
    default: {
      const response = json(405, { error: "method not allowed" });
      response.headers.allow = "GET, HEAD, POST";
      return response;
    }
  }
}
