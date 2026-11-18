// Spike-only fake Messages API on 127.0.0.1. Never forwards anywhere.
// MODE file (re-read per request): ok | slow | 429 | bash:<command>
import http from 'node:http';
import fs from 'node:fs';

const port = Number(process.argv[2]);
const dir = process.argv[3];
const log = (o) => fs.appendFileSync(`${dir}/api.jsonl`, JSON.stringify(o) + '\n');
const mode = () => { try { return fs.readFileSync(`${dir}/MODE`, 'utf8').trim(); } catch { return 'ok'; } };

function sse(res, blocks, stop) {
  res.writeHead(200, { 'content-type': 'text/event-stream' });
  const ev = (t, d) => res.write(`event: ${t}\ndata: ${JSON.stringify({ type: t, ...d })}\n\n`);
  ev('message_start', { message: { id: 'msg_fake', type: 'message', role: 'assistant', model: 'claude-fake', content: [], stop_reason: null, usage: { input_tokens: 10, output_tokens: 1 } } });
  blocks.forEach((b, i) => {
    if (b.type === 'text') {
      ev('content_block_start', { index: i, content_block: { type: 'text', text: '' } });
      ev('content_block_delta', { index: i, delta: { type: 'text_delta', text: b.text } });
    } else {
      ev('content_block_start', { index: i, content_block: { type: 'tool_use', id: b.id, name: b.name, input: {} } });
      ev('content_block_delta', { index: i, delta: { type: 'input_json_delta', partial_json: JSON.stringify(b.input) } });
    }
    ev('content_block_stop', { index: i });
  });
  ev('message_delta', { delta: { stop_reason: stop }, usage: { output_tokens: 5 } });
  ev('message_stop', {});
  res.end();
}

http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', async () => {
    let j = {};
    try { j = JSON.parse(body); } catch {}
    const m = mode();
    const last = JSON.stringify(j.messages?.at(-1) ?? null);
    log({ t: Date.now(), method: req.method, url: req.url, mode: m, last: last.slice(0, 4000) });
    if (req.url.startsWith('/v1/messages')) fs.writeFileSync(`${dir}/last-body.json`, body);
    if (!req.url.startsWith('/v1/messages') || req.url.includes('count_tokens')) {
      res.writeHead(200, { 'content-type': 'application/json' });
      return res.end(req.url.includes('count_tokens') ? '{"input_tokens":10}' : '{}');
    }
    if (/^\d{3}/.test(m)) {
      const [code, hdr] = m.split(' ');
      const type = code === '429' ? 'rate_limit_error' : code === '529' ? 'overloaded_error' : 'api_error';
      const h = { 'content-type': 'application/json', 'retry-after': '0' };
      // optional "unified" header names Claude Code documents for subscription limits are NOT used;
      // hdr lets a spike add one arbitrary header as name=value
      if (hdr) { const [k, v] = hdr.split('='); h[k] = v; }
      res.writeHead(Number(code), h);
      return res.end(JSON.stringify({ type: 'error', error: { type, message: `fake ${code}` } }));
    }
    if (m === 'slow') await new Promise((r) => setTimeout(r, 6000));
    const hadToolResult = last.includes('tool_result');
    if (m.startsWith('bash:') && !hadToolResult && j.tools?.length) {
      return sse(res, [{ type: 'tool_use', id: 'toolu_fake1', name: 'Bash', input: { command: m.slice(5), description: 'spike' } }], 'tool_use');
    }
    sse(res, [{ type: 'text', text: 'fake reply' }], 'end_turn');
  });
}).listen(port, '127.0.0.1', () => console.log('listening', port));
