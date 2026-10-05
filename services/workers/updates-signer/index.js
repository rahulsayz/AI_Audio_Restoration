// Cloudflare Worker: updates-signer
// Intercepts /beta/appcast.xml, fetches pages feed, and dynamically signs R2 enclosure URLs on-the-fly.

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    
    // 1. Intercept /beta/appcast.xml
    if (url.pathname === '/beta/appcast.xml') {
      const response = await fetch(`https://updates.sangeet.app/beta/appcast-static.xml`);
      if (!response.ok) {
        return new Response("Base appcast feed not found", { status: 404 });
      }
      
      let xmlText = await response.text();
      
      // Generate secure presigned URL for Cloudflare R2 object
      const r2SignedUrl = await generateR2PresignedUrl(
        env.R2_ACCOUNT_ID,
        env.R2_ACCESS_KEY_ID,
        env.R2_SECRET_ACCESS_KEY,
        "sangeet-builds-beta",
        "SangeetAI-1.0.0-Beta.dmg",
        3600 // 1 hour expiry
      );
      
      // Swap placeholder URL with the freshly signed R2 secure URL
      xmlText = xmlText.replace(
        /url="https:\/\/updates\.sangeet\.app\/beta\/builds\/SangeetAI-1.0.0-Beta.dmg"/g,
        `url="${escapeXml(r2SignedUrl)}"`
      );
      
      return new Response(xmlText, {
        headers: {
          "Content-Type": "application/rss+xml; charset=utf-8",
          "Cache-Control": "public, max-age=60" // Cache signed feed for 60 seconds max
        }
      });
    }
    
    return fetch(request);
  }
};

function escapeXml(unsafe) {
  return unsafe.replace(/[<>&'"]/g, (c) => {
    switch (c) {
      case '<': return '&lt;';
      case '>': return '&gt;';
      case '&': return '&amp;';
      case '\'': return '&apos;';
      case '"': return '&quot;';
      default: return c;
    }
  });
}

// Pure Web Crypto V4 S3 Signer for Cloudflare Workers
async function generateR2PresignedUrl(accountId, accessKey, secretKey, bucket, objectKey, expiresInSeconds) {
  const host = `${bucket}.${accountId}.r2.cloudflarestorage.com`;
  const endpoint = `https://${host}/${objectKey}`;
  const now = new Date();
  
  const amzDate = now.toISOString().replace(/[:-]/g, "").split(".")[0] + "Z";
  const datestamp = amzDate.substring(0, 8);
  
  const credentialScope = `${datestamp}/us-east-1/s3/aws4_request`;
  
  const queryParams = {
    "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
    "X-Amz-Credential": `${accessKey}/${credentialScope}`,
    "X-Amz-Date": amzDate,
    "X-Amz-Expires": expiresInSeconds.toString(),
    "X-Amz-SignedHeaders": "host"
  };
  
  const sortedQueryString = Object.keys(queryParams)
    .sort()
    .map(key => `${encodeURIComponent(key)}=${encodeURIComponent(queryParams[key])}`)
    .join("&");
    
  const canonicalRequest = [
    "GET",
    `/${encodeURIComponent(objectKey)}`,
    sortedQueryString,
    `host:${host}\n`,
    "host",
    "UNSIGNED-PAYLOAD"
  ].join("\n");
  
  const canonicalRequestHash = await sha256(canonicalRequest);
  
  const stringToSign = [
    "AWS4-HMAC-SHA256",
    amzDate,
    credentialScope,
    canonicalRequestHash
  ].join("\n");
  
  const signature = await getSignature(secretKey, datestamp, "us-east-1", "s3", stringToSign);
  
  return `${endpoint}?${sortedQueryString}&X-Amz-Signature=${signature}`;
}

async function sha256(message) {
  const msgBuffer = new TextEncoder().encode(message);
  const hashBuffer = await crypto.subtle.digest("SHA-256", msgBuffer);
  return Array.from(new Uint8Array(hashBuffer))
    .map(b => b.toString(16).padStart(2, "0"))
    .join("");
}

async function hmac(key, message) {
  const keyBuffer = typeof key === "string" ? new TextEncoder().encode(key) : key;
  const msgBuffer = typeof message === "string" ? new TextEncoder().encode(message) : message;
  
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyBuffer,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  
  const signature = await crypto.subtle.sign("HMAC", cryptoKey, msgBuffer);
  return new Uint8Array(signature);
}

async function getSignature(secretKey, date, region, service, stringToSign) {
  const kDate = await hmac(`AWS4${secretKey}`, date);
  const kRegion = await hmac(kDate, region);
  const kService = await hmac(kRegion, service);
  const kSigning = await hmac(kService, "aws4_request");
  const signature = await hmac(kSigning, stringToSign);
  
  return Array.from(signature)
    .map(b => b.toString(16).padStart(2, "0"))
    .join("");
}
