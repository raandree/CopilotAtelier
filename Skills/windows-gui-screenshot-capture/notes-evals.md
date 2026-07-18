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
4. "How do I capture a MessageBox to an image from PowerShell?" -> expect `FindWindow('#32770',
   title)` + `PrintWindow` + the capture-then-dismiss timer, not `GetForegroundWindow`.
5. "Automate screenshots of an Avalonia app for docs." -> expect headless `CaptureRenderedFrame`
   with a real font (`WithInterFont`, `UseHeadlessDrawing = false`).
6. "Capture a WinUI 3 window - RenderTargetBitmap or is there an OS-level API?" -> expect
   `RenderTargetBitmap.RenderAsync` and `Windows.Graphics.Capture` as the general fallback.

## Decoys (skill should NOT fire)

- "Take a screenshot of my iPhone app's login screen." -> mobile; out of scope.
- "Record a screen video / GIF of my app demo." -> screen-video capture; out of scope.
- "Teach me how to build a WinForms form with a button and a textbox." -> generic GUI tutorial,
  no capture/doc intent; out of scope.

## Baseline gaps (without the skill)

- Model reaches for `PrintWindow` universally and produces black frames for WebView2 / WinUI 3.
- Model captures `GetForegroundWindow` and grabs the launching console instead of the dialog.
- Model sizes the WinForms bitmap to `ClientSize` and clips the border.
- Model leaves the GUI blocking the terminal (no self-terminating capture mode).
