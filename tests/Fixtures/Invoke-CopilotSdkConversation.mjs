// Drives sessions of the Copilot SDK runtime that VS Code bundles against a fake,
// local OpenAI-compatible model, and records every request the runtime sends to
// that model. A request body is exactly what a real model would read, so a
// marker that a hook emits can be traced into the model's context without a
// model, an account, or network access beyond the loopback interface.
//
// The runtime gets its own COPILOT_HOME, so it loads only the hooks staged under
// <copilot home>/hooks and the workspace; the user's hooks and sessions stay out.
// Each session offers one tool, probe_tool, which always succeeds, so the
// runtime's postToolUse pipeline runs on every call the fake model makes.
//
// Usage: node Invoke-CopilotSdkConversation.mjs <sdk package root> <copilot home> <workspace> [runtime path]
// The optional runtime path replaces the bundled copilot-runtime, for example
// with a standalone Copilot CLI binary, which the SDK starts the same way.
// Standard input: a JSON array of steps, run in order:
//   { "op": "newSession" }                         starts a session; later steps use it
//   { "op": "send", "prompt": "..." }              one user turn; the fake model calls
//                                                  probe_tool once, then answers in text
//   { "op": "compact" }                            history.compact with trigger manual
//   { "op": "writeFile", "path": "...", "content": "..." }
//   { "op": "removeFile", "path": "..." }
//   { "op": "disconnect" }
// Standard output: one JSON object { requests, events, steps }.

import { createServer } from 'node:http';
import { readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [packageRoot, copilotHome, workspace, runtimeOverride] = process.argv.slice(2);
if (!packageRoot || !copilotHome || !workspace) {
    console.error('usage: node Invoke-CopilotSdkConversation.mjs <sdk package root> <copilot home> <workspace> [runtime path]');
    process.exit(2);
}

const steps = JSON.parse(readFileSync(0, 'utf8'));
const watchdog = setTimeout(() => {
    console.error('The Copilot SDK conversation did not finish within 600 seconds.');
    process.exit(3);
}, 600000);

const requests = [];
const events = [];
const stepResults = [];
let currentStep = -1;
let summaryMode = false;
let toolCallsThisStep = 0;

function textOf(content) {
    if (typeof content === 'string') {
        return content;
    }
    if (Array.isArray(content)) {
        return content.map((part) => (typeof part === 'string' ? part : part?.text ?? '')).join('');
    }
    return content == null ? '' : JSON.stringify(content);
}

function plan(body) {
    if (summaryMode) {
        return { text: '<overview>Probe summary of the conversation so far.</overview>' };
    }
    const toolNames = (body.tools ?? []).map((tool) => tool.function?.name ?? tool.name);
    if (toolNames.includes('probe_tool') && toolCallsThisStep === 0) {
        toolCallsThisStep++;
        return { toolCall: { id: `call_${currentStep}_${requests.length}`, name: 'probe_tool', arguments: '{"n":1}' } };
    }
    return { text: `Probe reply ${requests.length}.` };
}

function writeCompletion(response, body, reply) {
    const base = { id: `chatcmpl-${requests.length}`, created: 0, model: body.model ?? 'probe-model' };
    const usage = { prompt_tokens: 100, completion_tokens: 5, total_tokens: 105 };
    const message = reply.toolCall
        ? {
              role: 'assistant',
              content: null,
              tool_calls: [{ id: reply.toolCall.id, type: 'function', function: { name: reply.toolCall.name, arguments: reply.toolCall.arguments } }],
          }
        : { role: 'assistant', content: reply.text };
    const finishReason = reply.toolCall ? 'tool_calls' : 'stop';

    if (!body.stream) {
        response.writeHead(200, { 'content-type': 'application/json' });
        response.end(JSON.stringify({ ...base, object: 'chat.completion', choices: [{ index: 0, message, finish_reason: finishReason }], usage }));
        return;
    }

    response.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', connection: 'keep-alive' });
    const chunk = (choices, extra = {}) => response.write(`data: ${JSON.stringify({ ...base, object: 'chat.completion.chunk', choices, ...extra })}\n\n`);
    if (reply.toolCall) {
        chunk([{ index: 0, delta: { role: 'assistant', content: null, tool_calls: [{ index: 0, id: reply.toolCall.id, type: 'function', function: { name: reply.toolCall.name, arguments: '' } }] }, finish_reason: null }]);
        chunk([{ index: 0, delta: { tool_calls: [{ index: 0, function: { arguments: reply.toolCall.arguments } }] }, finish_reason: null }]);
    } else {
        chunk([{ index: 0, delta: { role: 'assistant', content: reply.text }, finish_reason: null }]);
    }
    chunk([{ index: 0, delta: {}, finish_reason: finishReason }]);
    chunk([], { usage });
    response.write('data: [DONE]\n\n');
    response.end();
}

const server = createServer((request, response) => {
    let raw = '';
    request.setEncoding('utf8');
    request.on('data', (part) => (raw += part));
    request.on('end', () => {
        if (request.method === 'GET' && request.url.endsWith('/models')) {
            response.writeHead(200, { 'content-type': 'application/json' });
            response.end(JSON.stringify({ object: 'list', data: [{ id: 'probe-model', object: 'model', created: 0, owned_by: 'probe' }] }));
            return;
        }
        let body = {};
        try {
            body = raw ? JSON.parse(raw) : {};
        } catch {
            body = { unparsable: raw.slice(0, 2000) };
        }
        const reply = plan(body);
        requests.push({
            step: currentStep,
            summaryMode,
            method: request.method,
            path: request.url,
            stream: Boolean(body.stream),
            toolNames: (body.tools ?? []).map((tool) => tool.function?.name ?? tool.name),
            messages: (body.messages ?? []).map((message) => ({
                role: message.role,
                text: textOf(message.content),
                toolCallId: message.tool_call_id,
                toolCalls: message.tool_calls?.map((call) => call.function?.name),
            })),
            reply: reply.toolCall ? `tool:${reply.toolCall.name}` : `text:${reply.text}`,
        });
        writeCompletion(response, body, reply);
    });
});

await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const baseUrl = `http://127.0.0.1:${server.address().port}/v1`;

const { CopilotClient, RuntimeConnection, approveAll } = await import(
    pathToFileURL(join(packageRoot, 'copilot-sdk', 'index.js')).href
);
const runtimeName = process.platform === 'win32' ? 'copilot-runtime.exe' : 'copilot-runtime';
const client = new CopilotClient({
    connection: RuntimeConnection.forStdio({
        path: runtimeOverride || join(packageRoot, 'prebuilds', `${process.platform}-${process.arch}`, runtimeName),
    }),
    baseDirectory: copilotHome,
    useLoggedInUser: false,
    logLevel: 'error',
    workingDirectory: workspace,
});

const probeTool = {
    name: 'probe_tool',
    description: 'Returns a fixed text. Used only by the hook probe.',
    parameters: { type: 'object', properties: { n: { type: 'number' } } },
    handler: async () => 'probe tool result',
    skipPermission: true,
    defer: 'never',
};

let exitCode = 0;
let session;
let sessionOrdinal = 0;
try {
    for (const [index, step] of steps.entries()) {
        currentStep = index;
        toolCallsThisStep = 0;
        const result = { step: index, op: step.op };
        switch (step.op) {
            case 'newSession': {
                sessionOrdinal++;
                const ordinal = sessionOrdinal;
                session = await client.createSession({
                    workingDirectory: workspace,
                    onPermissionRequest: approveAll,
                    model: 'gpt-4.1',
                    provider: { type: 'openai', wireApi: 'completions', baseUrl, apiKey: 'probe', modelId: 'gpt-4.1', wireModel: 'probe-model' },
                    tools: [probeTool],
                    availableTools: ['probe_tool'],
                    toolSearch: { enabled: false },
                });
                session.on((event) => {
                    if (!/^(hook\.|session\.(compaction|warning|error|start))|^tool\.execution_complete$/.test(event.type)) {
                        return;
                    }
                    events.push({
                        step: currentStep,
                        session: ordinal,
                        type: event.type,
                        hookType: event.data?.hookType,
                        success: event.data?.success,
                        output: event.data?.output,
                        error: event.data?.error,
                        input: event.type === 'hook.start' && event.data?.hookType !== 'postToolUse' ? event.data?.input : undefined,
                        trigger: event.data?.trigger,
                        messagesRemoved: event.data?.messagesRemoved,
                        message: event.data?.message,
                        toolResult: event.type === 'tool.execution_complete' ? event.data?.result : undefined,
                    });
                });
                result.sessionId = session.sessionId;
                break;
            }
            case 'send': {
                const reply = await session.sendAndWait({ prompt: step.prompt }, 180000);
                result.reply = reply?.data?.content;
                break;
            }
            case 'compact': {
                summaryMode = true;
                try {
                    const outcome = await session.rpc.history.compact({ trigger: 'manual' });
                    result.success = outcome.success;
                    result.messagesRemoved = outcome.messagesRemoved;
                } finally {
                    summaryMode = false;
                }
                break;
            }
            case 'writeFile':
                writeFileSync(step.path, step.content, 'utf8');
                break;
            case 'removeFile':
                rmSync(step.path, { force: true });
                break;
            case 'disconnect':
                await session.disconnect();
                session = undefined;
                break;
            default:
                throw new Error(`unknown step op: ${step.op}`);
        }
        // Hook events are delivered asynchronously; let them land before the next step.
        await new Promise((resolve) => setTimeout(resolve, 500));
        stepResults.push(result);
    }
    process.stdout.write(JSON.stringify({ requests, events, steps: stepResults }));
} catch (error) {
    console.error(error?.stack ?? String(error));
    process.stdout.write(JSON.stringify({ requests, events, steps: stepResults, failure: String(error?.message ?? error) }));
    exitCode = 1;
} finally {
    if (session) {
        await session.disconnect().catch(() => {});
    }
    await client.stop();
    server.close();
    clearTimeout(watchdog);
}

process.exit(exitCode);
