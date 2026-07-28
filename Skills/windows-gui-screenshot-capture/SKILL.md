---
name: windows-gui-screenshot-capture
description: >-
  Captures Windows GUI screenshots from modifiable apps and existing or
  third-party executables, then assembles screenshot-embedded Markdown
  manuals. Selects the correct API for WPF,
  WinForms, Win32/GDI, WebView2, Avalonia, and WinUI 3; covers external-process
  driving, event-based readiness, GPU black frames, native dialogs, state
  restoration, and content validation.
  USE FOR: capture Windows GUI screenshot, automate app screenshots,
  screenshot-based user manual, screenshot-driven docs, document existing
  Windows exe, third-party desktop app screenshots, closed-source Win32 app,
  external process screenshot, WPF, WinForms, Win32, WebView2, Avalonia,
  WinUI 3, PrintWindow black, SetWinEventHook, RenderTargetBitmap,
  DrawToBitmap, CapturePreviewAsync, Windows.Graphics.Capture, MessageBox
  #32770 capture, STA GUI PowerShell.
  DO NOT USE FOR: cross-platform or mobile screenshots, screen-video capture,
  general desktop RPA without screenshot-documentation intent, generic GUI
  tutorials.
---

# Windows GUI Screenshot Capture

Capture screenshots of a Windows desktop GUI programmatically - using the capture API each
rendering engine actually supports - and assemble them into a Markdown user manual with embedded
images. Generalises the technique proven in the `D:\guitest` proof-of-concept to real apps, so the
recipes below reference that repo as the worked example rather than being tied to it.

## When to use

- "Automate screenshots of my WPF / WinForms / Win32 / WebView2 / Avalonia / WinUI 3 app."
- "Generate a user manual with real screenshots, unattended (CI-friendly)."
- "`PrintWindow` returns a black image for my WebView2 / WinUI 3 window."
- "Capture a MessageBox / native dialog to PNG from PowerShell."
- "My GUI script blocks the terminal and never exits when capturing."

## Outcome

One PNG per predefined UI state, captured with the correct per-engine API into
`docs/images/<framework>/`, plus a Markdown manual that embeds them - all produced by a single
orchestrator run with no manual clicking and no persistent change to user settings.

## Dependencies

- PowerShell 7+ on Windows, run **STA** (a detached `pwsh` is STA by default; guard and relaunch
  if the host is MTA).
- .NET assemblies: `PresentationFramework` (WPF); `System.Windows.Forms` + `System.Drawing`
  (WinForms); `user32.dll` / `gdi32.dll` P/Invoke (Win32 + native dialogs).
- `dotnet` SDK for compiled engines; the Edge **WebView2 runtime**; `Avalonia.Skia` +
  `Avalonia.Headless`; the **Windows App SDK** for WinUI 3.
- Process-scoped native-dialog helper with checked capture/close results:
  [`scripts/DialogCapture.ps1`](scripts/DialogCapture.ps1).
- Short per-engine recipes: [`references/engine-recipes.md`](references/engine-recipes.md).

## Step 1 - Pick the capture API by rendering engine

The single most important decision. Each engine has one capture method that works; the wrong one
yields a black or clipped image.

| Rendering engine | Typical host | Capture API | Note |
|---|---|---|---|
| WPF (DirectX / Milcore) | PowerShell + `Add-Type` | `RenderTargetBitmap` | In-process; ignores focus / z-order |
| WinForms (GDI+) | PowerShell | `Control.DrawToBitmap` | Renders whole window - size bitmap to `Form.Size` |
| Win32 / GDI (CPU) | PowerShell + P/Invoke | `PrintWindow` (`PW_RENDERFULLCONTENT`) | Works off-screen |
| WebView2 (Chromium / GPU) | dotnet WinForms host | `CoreWebView2.CapturePreviewAsync` | `PrintWindow` returns black |
| Avalonia (Skia) | dotnet headless | `Window.CaptureRenderedFrame` | No visible window needed |
| WinUI 3 (Composition / GPU) | dotnet + Windows App SDK | `RenderTargetBitmap.RenderAsync` **or** `Windows.Graphics.Capture` | `PrintWindow` returns black |

A two-to-three-line snippet per engine, each pointing to the full POC implementation, is in
[`references/engine-recipes.md`](references/engine-recipes.md).

## Step 2 - Apply the GPU-composited rule

`PrintWindow` / `BitBlt` read the window's CPU-side surface. **GPU-composited content returns
solid black**: WebView2 (Chromium), WinUI 3, and UWP. For those, capture with the framework API
(`CapturePreviewAsync`, `RenderTargetBitmap.RenderAsync`) or the OS-level
`Windows.Graphics.Capture` (Windows 10 1803+), which is the general fallback for composited or
external windows. Use `PrintWindow` for Win32/GDI, `DrawToBitmap` for in-process WinForms, and
`RenderTargetBitmap` for an in-process WPF visual; do not infer external WPF reliability from the
Win32 result.

## Step 3 - Choose how to drive scenes

Choose the branch by source ownership. Do not assume every executable can be modified.

### Apps you can modify

Give the app two modes so it runs unattended and never blocks the terminal:

- **Interactive (default):** `ShowDialog()` / `Application.Run()` - a human uses it.
- **Capture:** a `-CaptureDir <dir>` (PowerShell) or `--capture <dir>` (dotnet) switch. A timer
  steps through predefined *scenes* (named UI states), renders each to `<scene>.png`, and
  **self-terminates** after the last one.

Why a timer: it fires on the UI dispatcher after layout, so the visual is measured before you
render it; and it keeps ticking through modal dialog loops (Step 5).

```powershell
$scenes = @(
    @{ Name = 'app-01-start';    Action = { <# set UI to state 1 #> } }
    @{ Name = 'app-02-selected'; Action = { <# set UI to state 2 #> } }
)
$script:i = 0
& $scenes[0].Action
$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(500)
$timer.Add_Tick({
    $scene = $scenes[$script:i]
    Save-VisualScreenshot -Visual $root -Path (Join-Path $CaptureDir "$($scene.Name).png")
    if (++$script:i -ge $scenes.Count) { $timer.Stop(); $window.Close() }
    else { & $scenes[$script:i].Action }
})
$window.Add_ContentRendered({ $timer.Start() })
$app = [System.Windows.Application]::new(); [void]$app.Run($window)
```

Full versions: `D:\guitest\src\Wpf\Show-CapitalFinder.ps1` (PowerShell), and the `--capture` mode
in `src\WebView2\Program.cs` and `src\Avalonia\Program.cs` (dotnet).

### Existing or third-party executables

Use an external driver when source is unavailable:

1. Record the executable version and open a deterministic, nonprivate sample file or fixture.
2. Launch with `ProcessStartInfo.ArgumentList`; use `WaitForInputIdle` only for initial startup.
3. Scope every window by process ID plus stable identity (owner, class, title, or control).
4. Drive scenes through UI Automation, command/control IDs, or app-specific APIs - never mouse
  coordinates when a stable interface exists.
5. Wait for the top-level window and known child state through UI Automation or a message-pumping
  WinEvent hook; a visible dialog and child control can still be unpainted.
6. Snapshot every changed option, restore it in `finally`, close each dialog, and terminate only
  the process the driver started.

For the full external-process workflow, cross-process control handling, race-free event wait,
and validation gates, read
[`references/external-win32-executables.md`](references/external-win32-executables.md).

## Step 4 - Name scenes consistently across engines

Use identical scene names in every engine (`app-01-start`, `app-02-selected`, ...). Consistent
names let one manual template embed any framework's image folder, and make cross-engine
comparison trivial - the same scene rendered by each engine side by side (as in the POC's
`docs/RenderingTechnologies.md`).

## Step 5 - Capture native dialogs (MessageBox `#32770`)

A `MessageBox` is a separate OS window that `RenderTargetBitmap` / `DrawToBitmap` cannot reach.
Capture it with the native helper [`scripts/DialogCapture.ps1`](scripts/DialogCapture.ps1)
(origin: `D:\guitest\src\Common\DialogCapture.ps1`):

1. Retain the original `Process` object and target the dialog by process + owner +
  **class `#32770`** + title, never by foreground window.
2. For an in-process app, use its UI timer so capture continues during the modal loop.
3. For an external executable, use UI Automation events or register
  `SetWinEventHook(EVENT_OBJECT_SHOW, WINEVENT_OUTOFCONTEXT)` on a thread that pumps messages.
  A blocking wait on the registering thread can prevent callback delivery.
4. Scan before and after hook registration and after each wake; unrelated show events can wake the
  hook, so always re-evaluate the complete process/owner/class/title predicate.
5. After the top-level dialog appears, require expected child text/state, then run a bounded
  capture-validation retry. Control visibility proves creation, not painted pixels.
6. Use the helper as `Get-DialogWindowHandle -Process $process ...`,
  `Save-WindowImage -Process $process ...`, and `Send-WindowClose -Process $process ...`; it
  rejects cross-process handles and failed `GetWindowRect`, `PrintWindow`, or `PostMessage` calls.

The timer keeps firing *during* the modal loop - that is how capture-then-dismiss works.
**Never** capture the foreground window (`GetForegroundWindow`) to "find" the dialog: it may be
the launching console. Always target the specific `#32770` window by class + title.

## Step 6 - Assemble the manual and verify

1. One orchestrator runs each scene source through its ownership branch: invoke `-CaptureDir` or
  `--capture` for modifiable apps; launch and drive the recorded process ID for external
  executables. Apply bounded readiness and shutdown timeouts in both branches. A modifiable app's
  capture mode self-exits; an external driver owns and closes only the process it started.
2. Collect the PNGs into `docs/images/<framework>/`.
3. Write the Markdown manual: intro, then a per-scene section with the user steps and
   `![alt](images/<framework>/<scene>.png)`.
4. Verify (below) before declaring done.

## Gotchas

| Symptom | Cause | Fix |
|---|---|---|
| WPF result area clipped in the shot | Fixed-size window | Set `window.SizeToContent = 'Height'` in capture mode |
| WinForms bottom / right edge cut off | `DrawToBitmap` renders the *whole* window | Size the bitmap to `Form.Size`, not `ClientSize` |
| WinForms fonts scaled / clipped on a 150% display | DPI scaling | `Application.SetHighDpiMode('DpiUnaware')` before building the form |
| Avalonia headless text is blank | No real font registered | `.WithInterFont()` + `AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false }` (Skia) |
| WebView2 / WinUI 3 shot is solid black | GPU-composited surface | Use the framework API or `Windows.Graphics.Capture` |
| Dialog title renders but client area is black | Frame appeared before content painted | Wait for expected child state, then retry capture and content validation within a bound |
| Cross-process combo remains empty | Text was sent to the combo wrapper | Find its child `Edit` control and send `WM_SETTEXT`, or use UI Automation |
| Revised `Add-Type` definition is ignored | The type is already loaded in the session | Run the capture script in a clean `pwsh` process while iterating P/Invoke code |
| Apartment-state error / self-relaunch loop | UI needs STA | Run STA (`pwsh` detached is STA); guard and relaunch only if MTA |
| Terminal never returns | GUI is blocking | Capture mode must self-terminate; orchestrator waits with a timeout |

## Anti-rationalization

| Rationalization | Reality |
|---|---|
| "I'll just `PrintWindow` everything, it's simpler." | Returns black for WebView2 / WinUI 3. Match the API to the engine or the screenshot is unusable. |
| "I'll capture the foreground window to get the dialog." | The foreground window may be the launching console. Use the started `Process` plus owner, class, and title. |
| "`ClientSize` is close enough for the WinForms bitmap." | `DrawToBitmap` renders the whole window; `ClientSize` clips the border. Use `Form.Size`. |
| "I'll paste the screenshots in by hand this once." | Manual capture is not reproducible and rots. The scene mode + orchestrator must regenerate them. |
| "The GUI opened, so capture works - ship it." | Layout may be incomplete or the wrong window captured. Verify each PNG exists and is non-trivial. |
| "`PrintWindow` returned true, so the image is valid." | A successful call can still capture an unpainted black client area. Validate image content and expected landmarks. |
| "A short sleep will let the dialog settle." | Fixed delays are flaky across machines. Wait for the specific window and ready control event. |
| "Changing a few view options is harmless." | External apps can persist them. Snapshot and restore every modified option in `finally`. |

## Red flags - stop if you catch yourself

- About to report "screenshots generated" without checking the PNGs exist and are non-empty.
- Using foreground or global title-only discovery instead of the started `Process` plus
  owner/class/title identity.
- Capturing a WebView2 / WinUI 3 window with `PrintWindow` and accepting a black image.
- Writing a capture script that needs a human to click or to close it - it must self-terminate.
- Sizing a WinForms capture bitmap to `ClientSize`.
- Driving a third-party executable through screen coordinates when stable controls are available.
- Capturing immediately after a dialog handle appears without checking a ready child control.
- Leaving the target app running or its view settings changed after the orchestrator exits.

## Verification

Confirm before reporting done:

- Every expected PNG exists, exceeds the minimum dimensions/size, and has non-uniform pixels.
  File size alone is insufficient: a 2 KB image can contain a title bar over a black client area.
- Pixel checks are scene-aware: reject mostly black frames only when the expected scene is not a
  dark theme, and verify at least one expected visual landmark or control region.
- Visually inspect every final frame for blank, clipped, stale, private, or wrong-window content.
- Scene count per framework matches the app's scene list.
- All capture scripts parse clean:
  `[System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$errs)` -> 0
  errors (the POC wraps this in `tools/Test-Syntax.ps1`).
- The manual renders with every `![...](images/...)` resolving to a file that exists.
- The orchestrator leaves no target process it started and restores every changed setting.
- Cleanup retains the original `Process` object, checks `HasExited`, and never adopts an existing
  single-instance process merely because a short-lived launcher forwarded the request.

## Worked example

`D:\guitest` implements the same **Capital Finder** app across all six engines, plus a
WPF / WinForms **Setup Wizard** whose final step raises the `#32770` completion dialog. Read it for
full, working implementations:

- Capture helpers: `src/Common/DialogCapture.ps1`, `src/Wpf/Capture.ps1`,
  `src/WinForms/Capture.ps1`.
- Self-capturing apps: `src/Wpf/Show-CapitalFinder.ps1`, `src/Wpf/Start-SetupWizard.ps1`,
  `src/Win32/Show-CapitalFinder.ps1`, `src/WebView2/Program.cs`, `src/Avalonia/Program.cs`,
  `src/WinUI3/README.md`.
- Orchestration + verify: `docs/Generate-Screenshots.ps1`, `tools/Test-Syntax.ps1`.
- Assembled manuals: `docs/UserManual.md`, `docs/UserManual.WinForms.md`,
  `docs/RenderingTechnologies.md`.

## See also

- Per-engine capture snippets: [`references/engine-recipes.md`](references/engine-recipes.md).
- Ready-to-use native-dialog helper: [`scripts/DialogCapture.ps1`](scripts/DialogCapture.ps1).
- Eval prompts: [`notes-evals.md`](notes-evals.md).
