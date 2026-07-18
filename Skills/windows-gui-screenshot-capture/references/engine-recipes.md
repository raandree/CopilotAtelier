# Windows GUI capture recipes (per rendering engine)

Short, ready-to-adapt capture snippets for each Windows rendering engine. Each recipe names the
API, shows the minimal call, and points to the full working implementation in the `D:\guitest`
proof-of-concept. For the decision matrix, the GPU-composited rule, the self-capturing scene
mode, and the orchestration/verification pipeline, see [`../SKILL.md`](../SKILL.md).

## Contents

- [WPF - RenderTargetBitmap](#wpf---rendertargetbitmap)
- [WinForms - Control.DrawToBitmap](#winforms---controldrawtobitmap)
- [Win32 GDI - PrintWindow](#win32-gdi---printwindow)
- [WebView2 - CapturePreviewAsync](#webview2---capturepreviewasync)
- [Avalonia - headless CaptureRenderedFrame](#avalonia---headless-capturerenderedframe)
- [WinUI 3 - RenderTargetBitmap.RenderAsync / Windows.Graphics.Capture](#winui-3---rendertargetbitmaprenderasync--windowsgraphicscapture)

## WPF - RenderTargetBitmap

Renders the WPF visual tree directly, so window focus and z-order are irrelevant. In capture
mode set `window.SizeToContent = 'Height'` first so a fixed-size window is not clipped.

```powershell
$rtb = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(
    [int][math]::Ceiling($visual.ActualWidth),   # $visual = window content root
    [int][math]::Ceiling($visual.ActualHeight),
    96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
$rtb.Render($visual)
$enc = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
$enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
$fs = [System.IO.File]::Create($path)
try { $enc.Save($fs) } finally { $fs.Dispose() }
```

Full implementation: `D:\guitest\src\Wpf\Capture.ps1` (`Save-VisualScreenshot`).

## WinForms - Control.DrawToBitmap

`DrawToBitmap` on a `Form` renders the **whole** window (title bar + border), so size the bitmap
to `Form.Size`, not `ClientSize`, or the bottom and right edges are clipped. Build the form
DPI-unaware (`[System.Windows.Forms.Application]::SetHighDpiMode('DpiUnaware')`) so a scaled
display does not clip text.

```powershell
$bmp = [System.Drawing.Bitmap]::new($form.Width, $form.Height)
$form.DrawToBitmap($bmp, [System.Drawing.Rectangle]::new(0, 0, $form.Width, $form.Height))
$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
```

Full implementation: `D:\guitest\src\WinForms\Capture.ps1` (`Save-FormImage`).

## Win32 GDI - PrintWindow

`PW_RENDERFULLCONTENT` (`0x2`) captures the window even when it is not on top. Needs the
`user32.dll` P/Invoke declarations - use the ready-made helper in
[`../scripts/DialogCapture.ps1`](../scripts/DialogCapture.ps1) (`Save-WindowImage`).

```powershell
$bmp = [System.Drawing.Bitmap]::new($width, $height)      # from GetWindowRect
$g   = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[void][GuiDoc.WindowCapture]::PrintWindow($hwnd, $hdc, [uint32]2)
$g.ReleaseHdc($hdc); $g.Dispose()
$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
```

Full app (native WndProc + GDI paint): `D:\guitest\src\Win32\Show-CapitalFinder.ps1`.

## WebView2 - CapturePreviewAsync

Chromium content is GPU-composited, so `PrintWindow` / `BitBlt` return black. Use the WebView2
API. Drive UI state with `ExecuteScriptAsync` before each capture.

```csharp
using var fs = new FileStream(path, FileMode.Create, FileAccess.Write);
await wv.CoreWebView2.CapturePreviewAsync(
    CoreWebView2CapturePreviewImageFormat.Png, fs);
```

Full implementation: `D:\guitest\src\WebView2\Program.cs` (`CaptureScene`).

## Avalonia - headless CaptureRenderedFrame

Offscreen Skia capture; no visible window required. A real font must be registered
(`WithInterFont()`) with `UseHeadlessDrawing = false`, otherwise text renders blank.

```csharp
AppBuilder.Configure<App>().UseSkia().WithInterFont()
    .UseHeadless(new AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false })
    .SetupWithoutStarting();
var win = new MainWindow();
win.Show();
Dispatcher.UIThread.RunJobs();                 // let layout settle before capture
win.CaptureRenderedFrame().Save(path);
```

Full implementation: `D:\guitest\src\Avalonia\Program.cs` (`Capture`).

## WinUI 3 - RenderTargetBitmap.RenderAsync / Windows.Graphics.Capture

Composition/DirectX content is GPU-composited, so `PrintWindow` returns black. Two working
options: the in-framework `RenderTargetBitmap.RenderAsync`, or the OS-level
`Windows.Graphics.Capture` (Windows 10 1803+), which captures any composited window and is the
general answer for WinUI 3 / UWP.

```csharp
var rtb = new Microsoft.UI.Xaml.Media.Imaging.RenderTargetBitmap();
await rtb.RenderAsync(rootElement);
var pixels = await rtb.GetPixelsAsync();       // encode to PNG with a BitmapEncoder
```

Reference build (requires the Windows App SDK runtime): `D:\guitest\src\WinUI3\README.md`.
