# Evaluation prompts - windows-gui-screenshot-capture

Trigger + behaviour evals for the skill, following the `skill-creator` evaluation-driven loop.
Run each in a fresh chat; confirm the skill is named on the PRE-FLIGHT line (trigger), then check
the response against the expected behaviour (quality).

## Intended triggers (skill should fire)

1. "Write a script that opens my WinForms app and saves a screenshot of each screen to PNG,
   unattended." -> expect the self-capturing scene mode + `DrawToBitmap` sized to `Form.Size`.
2. "My WebView2 screenshot comes out completely black when I use PrintWindow. Why?" -> expect the
   GPU-composited rule + `CapturePreviewAsync`.
3. "Generate a user manual with real screenshots for my WPF app." -> expect
   `RenderTargetBitmap` + `SizeToContent` + the capture -> images folder -> Markdown pipeline.
4. "How do I capture a MessageBox to an image from PowerShell?" -> expect process-scoped
   owner/class/title discovery + checked `PrintWindow` + capture-then-dismiss, never global
   `FindWindow` or `GetForegroundWindow`.
5. "Automate screenshots of an Avalonia app for docs." -> expect headless `CaptureRenderedFrame`
   with a real font (`WithInterFont`, `UseHeadlessDrawing = false`).
6. "Capture a WinUI 3 window - RenderTargetBitmap or is there an OS-level API?" -> expect
   `RenderTargetBitmap.RenderAsync` and `Windows.Graphics.Capture` as the general fallback.
7. "Create screenshot-based documentation for this existing Win32 EXE; I do not have its
   source." -> expect the external-driver branch, deterministic sample, process-scoped control
   discovery, event-based readiness, state restoration, and process cleanup.

## Regression cases from a real external-EXE run

1. "The native Settings dialog handle exists, but PrintWindow captures a title bar over a black
   client area." -> expect separate top-level and child-control readiness gates using
   `SetWinEventHook`, not a fixed sleep or `WaitForInputIdle` alone.
2. "PrintWindow returned true and the PNG is 2 KB. Is that enough validation?" -> expect no:
   validate dimensions, non-uniform pixels, scene-aware dark ratio, an expected landmark, and
   visual review.
3. "Populate a Find/Replace combo in another process before the screenshot." -> expect UI
   Automation or `WM_SETTEXT` to the nested `Edit` control, not `SetWindowText` on the combo.
4. "Turn on whitespace markers and line numbers for the screenshots." -> expect original state
   capture and restoration in `finally`, plus cleanup of only the process started by the driver.
5. "I used WINEVENT_OUTOFCONTEXT and then WaitOne, but the callback never runs." -> expect a
   message-pumping hook thread/runspace or `MsgWaitForMultipleObjectsEx`, repeated predicate
   checks after wakes, and a bounded timeout.
6. "Two processes show the same #32770 caption. Capture and close only the dialog from the process
   I launched." -> expect the original `Process` object plus process/owner/class/title discovery;
   never global `FindWindow`, foreground discovery, or PID-only cleanup.
7. "PrintWindow returned false but my script saved the bitmap anyway." -> expect a terminating
   capture failure before save, followed by bounded fallback/retry only when explicitly designed.
8. "This valid dark-theme application screenshot is mostly black." -> expect scene-aware landmark
   or region validation; a universal dark-pixel threshold must not reject it.

## Decoys (skill should NOT fire)

- "Take a screenshot of my iPhone app's login screen." -> mobile; out of scope.
- "Record a screen video / GIF of my app demo." -> screen-video capture; out of scope.
- "Teach me how to build a WinForms form with a button and a textbox." -> generic GUI tutorial,
  no capture/doc intent; out of scope.
- "Automate invoice entry in a desktop ERP." -> general RPA without screenshot-documentation
   intent; out of scope.

## Baseline gaps (without the skill)

- Model reaches for `PrintWindow` universally and produces black frames for WebView2 / WinUI 3.
- Model captures `GetForegroundWindow` and grabs the launching console instead of the dialog.
- Model sizes the WinForms bitmap to `ClientSize` and clips the border.
- Model leaves the GUI blocking the terminal (no self-terminating capture mode).
- Model assumes source access and offers no workflow for an existing executable.
- Model captures a top-level dialog before its child controls paint.
- Model treats `PrintWindow` success and file size as proof of usable content.
- Model changes persistent view settings and does not restore them.
- Model blocks the WinEvent registration thread without pumping messages.
- Model uses global `FindWindow` or a reacquired PID as the ownership boundary.
- Model discards the Boolean result from `PrintWindow`.
