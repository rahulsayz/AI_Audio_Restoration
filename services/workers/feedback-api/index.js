// Cloudflare Worker: feedback-api
// Listens at https://feedback.sangeet.app/api/submit
// Receives JSON or Multipart feedback forms and dispatches premium HTML notifications via Resend.

export default {
  async fetch(request, env) {
    // Enable CORS preflight support
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type",
          "Access-Control-Max-Age": "86400"
        }
      });
    }

    if (request.method !== "POST") {
      return new Response("Method Not Allowed", { status: 405 });
    }

    try {
      const contentType = request.headers.get("content-type") || "";
      let name, email, category, subject, message, diagnostics;
      let yamlFile = null, audioFile = null;

      if (contentType.includes("application/json")) {
        const payload = await request.json();
        name = payload.name;
        email = payload.email;
        category = payload.category;
        subject = payload.subject;
        message = payload.message;
        diagnostics = payload.diagnostics;
      } else if (contentType.includes("multipart/form-data")) {
        const formData = await request.formData();
        name = formData.get("name");
        email = formData.get("email");
        category = formData.get("category");
        subject = formData.get("subject");
        message = formData.get("message");
        
        const appVersion = formData.get("app_version");
        const macosVersion = formData.get("macos_version");
        const macModel = formData.get("mac_model");
        const totalRam = formData.get("total_ram");
        
        if (macosVersion || macModel || totalRam || appVersion) {
          diagnostics = {
            "app_version": appVersion || "1.0.0 Beta (Build 1)",
            "macos_version": macosVersion || "Unknown",
            "mac_model": macModel || "Unknown",
            "total_ram": totalRam || "Unknown"
          };
        }
        
        yamlFile = formData.get("yaml");
        audioFile = formData.get("audio");
      } else {
        return new Response("Unsupported Content Type", { 
          status: 415,
          headers: { "Access-Control-Allow-Origin": "*" }
        });
      }

      // 1. Validation
      if (!name || !email || !category || !message) {
        return new Response(JSON.stringify({ error: "Missing required fields (name, email, category, message)." }), {
          status: 400,
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
        });
      }

      // 2. Build premium HTML email template using Sangeet AI's theme system
      const htmlContent = buildHtmlEmail(name, email, category, subject, message, diagnostics);

      // 3. Process attachments if present
      const attachments = [];

      if (yamlFile && yamlFile instanceof File) {
        const base64Content = await fileToBase64(yamlFile);
        attachments.push({
          filename: yamlFile.name || "analysis.yaml",
          content: base64Content,
          content_type: yamlFile.type || "text/yaml"
        });
      }

      if (audioFile && audioFile instanceof File) {
        const base64Content = await fileToBase64(audioFile);
        attachments.push({
          filename: audioFile.name || "restored_audio.wav",
          content: base64Content,
          content_type: audioFile.type || "audio/wav"
        });
      }

      // 4. Dispatch via Resend API
      const resendApiKey = env.RESEND_API_KEY;
      if (!resendApiKey) {
        return new Response(JSON.stringify({ error: "Server Configuration Error: Resend API Key is missing." }), {
          status: 500,
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
        });
      }

      const resendRequestBody = {
        from: "Sangeet AI Beta <beta@sangeet.app>",
        to: ["beta@sangeet.app"],
        reply_to: email,
        subject: `[Beta Feedback] [${category}] ${subject || "No Subject"}`,
        html: htmlContent
      };

      if (attachments.length > 0) {
        resendRequestBody.attachments = attachments;
      }

      const resendResponse = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${resendApiKey}`
        },
        body: JSON.stringify(resendRequestBody)
      });

      if (!resendResponse.ok) {
        const resendError = await resendResponse.text();
        return new Response(JSON.stringify({ error: `Resend Dispatch Failed: ${resendError}` }), {
          status: resendResponse.status,
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
        });
      }

      return new Response(JSON.stringify({ message: "Feedback submitted successfully!" }), {
        status: 200,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
      });

    } catch (e) {
      return new Response(JSON.stringify({ error: `Internal Server Error: ${e.message}` }), {
        status: 500,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
      });
    }
  }
};

async function fileToBase64(file) {
  const arrayBuffer = await file.arrayBuffer();
  let binary = "";
  const bytes = new Uint8Array(arrayBuffer);
  const len = bytes.byteLength;
  for (let i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

function buildHtmlEmail(name, email, category, subject, message, diagnostics) {
  const saffronHex = "#F2A626";
  const spaceBg = "#0E0E14";
  const cardBg = "#171724";
  
  let diagnosticsHtml = "";
  if (diagnostics) {
    diagnosticsHtml = `
      <h3 style="color:${saffronHex}; font-family: sans-serif; font-size: 14px; margin-top: 24px; margin-bottom: 8px;">SYSTEM DIAGNOSTICS</h3>
      <table style="width: 100%; border-collapse: collapse; font-family: monospace; font-size: 11px; background-color: #0c0c12; border: 1px solid #222233;">
        ${Object.entries(diagnostics).map(([key, value]) => `
          <tr style="border-bottom: 1px solid #222233;">
            <td style="padding: 6px 12px; color: #888899; font-weight: bold; width: 140px;">${escapeHtml(key)}</td>
            <td style="padding: 6px 12px; color: #eeeeff;">${escapeHtml(String(value))}</td>
          </tr>
        `).join("")}
      </table>
    `;
  }

  return `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Sangeet AI Beta Feedback</title>
    </head>
    <body style="background-color: ${spaceBg}; margin: 0; padding: 20px; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #eeeeff;">
      <div style="max-width: 600px; margin: 0 auto; background-color: ${cardBg}; border: 1px solid #222233; border-top: 4px solid ${saffronHex}; border-radius: 8px; overflow: hidden; padding: 24px;">
        <div style="margin-bottom: 20px;">
          <span style="font-size: 10px; font-weight: bold; background-color: ${saffronHex}; color: #000000; padding: 2px 6px; border-radius: 3px; vertical-align: middle; text-transform: uppercase;">BETA PROGRAM</span>
          <h2 style="color: #ffffff; display: inline-block; font-size: 20px; font-weight: bold; margin: 0 0 0 8px; vertical-align: middle; letter-spacing: 1px;">SANGEET AI FEEDBACK</h2>
        </div>
        
        <table style="width: 100%; border-collapse: collapse; font-size: 13px; margin-bottom: 20px;">
          <tr style="border-bottom: 1px solid #222233;">
            <td style="padding: 8px 0; color: #888899; font-weight: bold; width: 100px;">From:</td>
            <td style="padding: 8px 0; color: #ffffff;">${escapeHtml(name)} (<a href="mailto:${escapeHtml(email)}" style="color: ${saffronHex}; text-decoration: none;">${escapeHtml(email)}</a>)</td>
          </tr>
          <tr style="border-bottom: 1px solid #222233;">
            <td style="padding: 8px 0; color: #888899; font-weight: bold;">Category:</td>
            <td style="padding: 8px 0; color: #ffffff;"><span style="background-color: #2b2b3c; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: bold;">${escapeHtml(category)}</span></td>
          </tr>
          <tr style="border-bottom: 1px solid #222233;">
            <td style="padding: 8px 0; color: #888899; font-weight: bold;">Subject:</td>
            <td style="padding: 8px 0; color: #ffffff; font-weight: bold;">${escapeHtml(subject || "No Subject Specified")}</td>
          </tr>
        </table>
        
        <h3 style="color:${saffronHex}; font-family: sans-serif; font-size: 14px; margin-bottom: 8px;">USER MESSAGE</h3>
        <div style="background-color: #0c0c12; border: 1px solid #222233; border-radius: 6px; padding: 16px; font-size: 13px; line-height: 1.6; color: #ddddff; white-space: pre-wrap; font-family: inherit;">
${escapeHtml(message)}
        </div>
        
        ${diagnosticsHtml}
        
        <div style="margin-top: 32px; border-top: 1px solid #222233; padding-top: 12px; font-size: 10px; color: #555566; text-align: center;">
          Sangeet AI Beta Distribution Console • Localized Audio Restoration for Indian Acoustic Signatures
        </div>
      </div>
    </body>
    </html>
  `;
}

function escapeHtml(unsafe) {
  return unsafe.replace(/[&<>"']/g, (c) => {
    switch (c) {
      case '&': return '&amp;';
      case '<': return '&lt;';
      case '>': return '&gt;';
      case '"': return '&quot;';
      case '\'': return '&apos;';
      default: return c;
    }
  });
}
