#!/usr/bin/env node
/*
 * SNUH Bundle — self-built gateway.
 * Serves the OpenAI *Responses* API to Codex, translates to *Chat Completions*
 * for an upstream OpenAI-compatible endpoint, and normalizes messages so the
 * system message is always FIRST (fixes vLLM "System message must be at the
 * beginning" for models like qwen3-5-397b-a17b).
 *
 * TLS to the upstream is handled by Node (honors NODE_EXTRA_CA_CERTS), so the
 * khdp incomplete-chain problem is solved here — Codex talks plain HTTP to us.
 *
 * Env:
 *   GW_UPSTREAM   upstream base, e.g. https://your-llm-server/v1   (required)
 *   GW_PORT       listen port (default 4600)
 *   GW_DEBUG      if set, log translated payloads to stderr
 * The client (Codex) sends Authorization: Bearer <key>; we pass it upstream.
 */
"use strict";
const http = require("http");
const crypto = require("crypto");

const UPSTREAM = (process.env.GW_UPSTREAM || "").replace(/\/+$/, "");
const PORT = parseInt(process.env.GW_PORT || "4600", 10);
const DEBUG = !!process.env.GW_DEBUG;
if (!UPSTREAM) { console.error("[gw] GW_UPSTREAM required"); process.exit(1); }

const rid = (p) => p + crypto.randomBytes(16).toString("hex");
const dbg = (...a) => { if (DEBUG) console.error("[gw]", ...a); };

// ---- Responses request -> Chat Completions request -------------------------
function textOf(content) {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content.map((c) =>
      typeof c === "string" ? c : (c && (c.text ?? c.input_text ?? c.output_text)) || ""
    ).join("");
  }
  return "";
}

function toChat(body) {
  const sysParts = [];
  const rest = [];
  if (body.instructions) sysParts.push(textOf(body.instructions));

  let input = body.input;
  if (typeof input === "string") input = [{ type: "message", role: "user", content: input }];
  if (!Array.isArray(input)) input = [];

  for (const it of input) {
    const t = it.type || "message";
    if (t === "message") {
      const role = it.role || "user";
      const text = textOf(it.content);
      if (role === "system" || role === "developer") sysParts.push(text);   // hoist -> front
      else rest.push({ role, content: text });
    } else if (t === "function_call") {
      rest.push({
        role: "assistant", content: null,
        tool_calls: [{ id: it.call_id || it.id, type: "function",
          function: { name: it.name, arguments: it.arguments || "{}" } }],
      });
    } else if (t === "function_call_output") {
      rest.push({ role: "tool", tool_call_id: it.call_id,
        content: typeof it.output === "string" ? it.output : JSON.stringify(it.output) });
    } // reasoning / other -> skip
  }

  const messages = [];
  if (sysParts.length) messages.push({ role: "system", content: sysParts.join("\n\n") }); // FIRST
  for (const m of rest) messages.push(m);

  const tools = Array.isArray(body.tools) ? body.tools.map((tl) => {
    if (tl.type === "function") {
      // Responses function tools are flat: {type,name,description,parameters}
      const fn = tl.function || { name: tl.name, description: tl.description, parameters: tl.parameters };
      return { type: "function", function: { name: fn.name, description: fn.description || "",
        parameters: fn.parameters || { type: "object", properties: {} } } };
    }
    return null; // non-function (e.g. local_shell) can't map to chat tools
  }).filter(Boolean) : undefined;

  const chat = { model: body.model, messages, stream: true };
  if (tools && tools.length) chat.tools = tools;
  if (body.tool_choice && body.tool_choice !== "auto") chat.tool_choice = body.tool_choice;
  if (body.temperature != null) chat.temperature = body.temperature;
  if (body.max_output_tokens != null) chat.max_tokens = body.max_output_tokens;
  return chat;
}

// ---- SSE helpers -----------------------------------------------------------
function sse(res, type, data) { res.write(`event: ${type}\ndata: ${JSON.stringify({ ...data, type })}\n\n`); }

// ---- main handler ----------------------------------------------------------
async function handleResponses(req, res, body) {
  const auth = req.headers["authorization"] || "";
  let parsed; try { parsed = JSON.parse(body); } catch { res.writeHead(400).end('{"error":"bad json"}'); return; }
  if (DEBUG) dbg("incoming tools:", JSON.stringify((parsed.tools || []).map((t) => t.type + ":" + (t.name || (t.function && t.function.name) || "?"))));
  const chat = toChat(parsed);
  dbg("chat.messages roles:", chat.messages.map((m) => m.role).join(","), "| tools:", (chat.tools || []).length);
  if (DEBUG) dbg("chat body:", JSON.stringify(chat).slice(0, 800));

  let up;
  try {
    up = await fetch(`${UPSTREAM}/chat/completions`, {
      method: "POST",
      headers: { "Authorization": auth, "Content-Type": "application/json" },
      body: JSON.stringify(chat),
    });
  } catch (e) {
    res.writeHead(502, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: { message: "gateway upstream connect failed: " + e.message } }));
    return;
  }
  if (!up.ok) {
    const errText = await up.text();
    dbg("upstream error", up.status, errText.slice(0, 300));
    res.writeHead(up.status, { "Content-Type": "application/json" });
    res.end(errText || JSON.stringify({ error: { message: "upstream " + up.status } }));
    return;
  }

  res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", "Connection": "keep-alive" });
  const respId = rid("resp_");
  const msgId = rid("msg_");
  const model = parsed.model;
  sse(res, "response.created", { response: { id: respId, model, status: "in_progress" } });

  let itemOpened = false;
  let fullText = "";
  // tool-call accumulation (by index) — emitted after stream if present
  const toolAcc = {}; // idx -> {id,name,args}
  let buf = "";

  const openItem = () => {
    if (itemOpened) return;
    itemOpened = true;
    sse(res, "response.output_item.added", {
      output_index: 0,
      item: { id: msgId, type: "message", role: "assistant", status: "in_progress", content: [] },
    });
  };

  const reader = up.body.getReader();
  const dec = new TextDecoder();
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    let nl;
    while ((nl = buf.indexOf("\n")) >= 0) {
      let line = buf.slice(0, nl); buf = buf.slice(nl + 1);
      line = line.replace(/\r$/, "");
      if (!line.startsWith("data:")) continue;
      const payload = line.slice(5).trim();
      if (payload === "[DONE]") continue;
      let chunk; try { chunk = JSON.parse(payload); } catch { continue; }
      const d = chunk.choices && chunk.choices[0] && chunk.choices[0].delta;
      if (!d) continue;
      if (d.content) {
        openItem();
        fullText += d.content;
        sse(res, "response.output_text.delta", { output_index: 0, item_id: msgId, delta: d.content });
      }
      if (Array.isArray(d.tool_calls)) {
        for (const tc of d.tool_calls) {
          const i = tc.index ?? 0;
          const a = (toolAcc[i] = toolAcc[i] || { id: tc.id || rid("call_"), name: "", args: "" });
          if (tc.id) a.id = tc.id;
          if (tc.function && tc.function.name) a.name = tc.function.name;
          if (tc.function && tc.function.arguments) a.args += tc.function.arguments;
        }
      }
    }
  }

  const outputItems = [];
  if (itemOpened) {
    const item = { id: msgId, type: "message", role: "assistant", status: "completed",
      content: [{ type: "output_text", text: fullText }] };
    sse(res, "response.output_item.done", { output_index: 0, item });
    outputItems.push(item);
  }
  // emit accumulated tool calls as function_call output items
  let oidx = outputItems.length;
  for (const i of Object.keys(toolAcc)) {
    const a = toolAcc[i];
    const fcId = rid("fc_");
    sse(res, "response.output_item.added", { output_index: oidx,
      item: { id: fcId, type: "function_call", status: "in_progress", name: a.name, call_id: a.id, arguments: "" } });
    sse(res, "response.function_call_arguments.delta", { output_index: oidx, item_id: fcId, delta: a.args });
    sse(res, "response.function_call_arguments.done", { output_index: oidx, item_id: fcId, arguments: a.args });
    const fcItem = { id: fcId, type: "function_call", status: "completed", name: a.name, call_id: a.id, arguments: a.args };
    sse(res, "response.output_item.done", { output_index: oidx, item: fcItem });
    outputItems.push(fcItem);
    oidx++;
  }

  sse(res, "response.completed", {
    response: { id: respId, model, status: "completed", output: outputItems,
      usage: { input_tokens: 0, output_tokens: 0, total_tokens: 0 } },
  });
  res.end();
}

async function proxyModels(req, res) {
  try {
    const up = await fetch(`${UPSTREAM}/models`, { headers: { "Authorization": req.headers["authorization"] || "" } });
    const t = await up.text();
    res.writeHead(up.status, { "Content-Type": "application/json" }); res.end(t);
  } catch (e) { res.writeHead(502).end(JSON.stringify({ error: e.message })); }
}

const server = http.createServer((req, res) => {
  const url = req.url.split("?")[0];
  if (req.method === "GET" && url.endsWith("/models")) return proxyModels(req, res);
  if (req.method === "POST" && url.endsWith("/responses")) {
    let b = ""; req.on("data", (c) => (b += c)); req.on("end", () => handleResponses(req, res, b).catch((e) => {
      dbg("handler error", e); try { res.writeHead(500).end(JSON.stringify({ error: { message: e.message } })); } catch {}
    }));
    return;
  }
  res.writeHead(404).end("not found");
});
server.listen(PORT, "127.0.0.1", () => console.error(`[gw] listening on 127.0.0.1:${PORT} -> ${UPSTREAM}`));
