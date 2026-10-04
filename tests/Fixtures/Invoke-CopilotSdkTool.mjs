// Runs commands through the preToolUse pipeline of the Copilot SDK runtime that
// VS Code bundles, without a model. The runtime gets its own COPILOT_HOME, so it
// loads only the workspace's .github/hooks; the user's hooks and sessions stay
// out. The session is unauthenticated and offers no tools, so a command the hooks
// allow fails as an unknown tool instead of running.
//
// Usage: node Invoke-CopilotSdkTool.mjs <sdk package root> <copilot home> <workspace>
// Standard input: a JSON array of command strings.
// Standard output: a JSON array of { command, resultType, textResultForLlm, preToolUseHookCount }.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [packageRoot, copilotHome, workspace] = process.argv.slice(2);
if (!packageRoot || !copilotHome || !workspace) {
    console.error('usage: node Invoke-CopilotSdkTool.mjs <sdk package root> <copilot home> <workspace>');
    process.exit(2);
}

const commands = JSON.parse(readFileSync(0, 'utf8'));
const watchdog = setTimeout(() => {
    console.error('The Copilot SDK runtime did not finish within 120 seconds.');
    process.exit(3);
}, 120000);

const { CopilotClient, RuntimeConnection, approveAll } = await import(
    pathToFileURL(join(packageRoot, 'copilot-sdk', 'index.js')).href
);
const runtimeName = process.platform === 'win32' ? 'copilot-runtime.exe' : 'copilot-runtime';
const client = new CopilotClient({
    connection: RuntimeConnection.forStdio({
        path: join(packageRoot, 'prebuilds', `${process.platform}-${process.arch}`, runtimeName),
    }),
    baseDirectory: copilotHome,
    useLoggedInUser: false,
    logLevel: 'error',
    workingDirectory: workspace,
});

let exitCode = 0;
try {
    const session = await client.createSession({ workingDirectory: workspace, onPermissionRequest: approveAll });
    let preToolUseHookCount = 0;
    session.on((event) => {
        if (event.type === 'hook.end' && event.data?.hookType === 'preToolUse') {
            preToolUseHookCount++;
        }
    });

    const results = [];
    for (const command of commands) {
        preToolUseHookCount = 0;
        const result = await session.rpc.tools.execute({
            name: 'powershell',
            arguments: { command, description: 'Copilot Atelier hook probe' },
        });
        await new Promise((resolve) => setTimeout(resolve, 250));
        results.push({
            command,
            resultType: result.resultType,
            textResultForLlm: result.textResultForLlm,
            preToolUseHookCount,
        });
    }

    await session.disconnect();
    process.stdout.write(JSON.stringify(results));
} catch (error) {
    console.error(error?.stack ?? String(error));
    exitCode = 1;
} finally {
    await client.stop();
    clearTimeout(watchdog);
}

process.exit(exitCode);
