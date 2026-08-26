# External Win32 executable capture

Use this workflow when the target is an existing or third-party executable and
you cannot add a self-capturing mode. It was validated against a classic Win32
editor with Scintilla controls and native `#32770` dialogs.

## Contents

- [Build deterministic scenes](#build-deterministic-scenes)
- [Discover stable controls](#discover-stable-controls)
- [Wait for ready UI](#wait-for-ready-ui)
- [Drive controls across processes](#drive-controls-across-processes)
- [Capture and validate pixels](#capture-and-validate-pixels)
- [Restore state and clean up](#restore-state-and-clean-up)
- [Failure patterns](#failure-patterns)

## Build deterministic scenes

1. Record executable path, product name, and file version.
2. Use a synthetic, nonprivate sample whose content and filename trigger the
   desired application behavior.
3. Inventory live menus, shortcuts, window classes, control IDs, and built-in
   help before writing documentation. Treat the running executable as the
   source of truth for that version.
4. Define a small named scene list. Each scene has an action, a ready
   condition, an expected window, and a PNG path.
5. Size the main window with `SetWindowPos` so captures are comparable.

Do not capture user documents, recent-file lists, account names, or unrelated
desktop content.

## Discover stable controls

Prefer interfaces in this order:

1. Application-specific automation or command-line API.
2. UI Automation properties and patterns.
3. Win32 command IDs, control IDs, window ownership, class, and title.
4. Keyboard input scoped to the known target window.
5. Mouse coordinates only when no stable semantic interface exists.

Scope top-level windows by process ID. A title alone can match another
application; the foreground window can be the launching terminal.

For classic Win32 applications:

- `GetMenu` + `GetMenuItemCount` + `GetMenuString` inventories commands.
- `EnumWindows` + `GetWindowThreadProcessId` finds process-owned windows.
- `EnumChildWindows`, `GetClassName`, and `GetDlgCtrlID` reveal controls.
- `WM_COMMAND` invokes a known menu or toolbar command without screen
  coordinates.

## Wait for ready UI

`WaitForInputIdle` proves that a GUI thread reached an input-idle state. It
does not prove that a posted dialog exists or that its controls have painted.

Use a bounded event wait:

1. Scan for the expected process-owned window.
2. Register `SetWinEventHook` for `EVENT_OBJECT_SHOW` (`0x8002`), scoped to the
   target process. For `WINEVENT_OUTOFCONTEXT`, callback delivery occurs on the
   registering thread, which must pump messages.
3. Use a dedicated hook thread/runspace with a message loop, or a message-aware
   wait such as `MsgWaitForMultipleObjectsEx` that dispatches pending messages.
   Do not block the registering thread in `WaitOne` or
   `ManualResetEventSlim.Wait` without a message pump.
4. Scan again after hook registration to close the race between the first scan
   and the hook. After every signal, re-evaluate process, owner, class, title,
   and expected state because unrelated show events can wake the hook.
5. After the top-level dialog appears, require expected child text/state such
   as the `OK` label, primary edit value, or selected tab. Visibility proves
   creation, not that pixels have painted.
6. Force or request redraw where supported, capture, and validate content. If
   validation fails, perform a bounded message-aware wait and retry the full
   state-plus-capture predicate; never substitute a fixed sleep.
7. Keep the callback delegate alive until `UnhookWinEvent` completes.

Top-level discovery, child state, and valid rendered pixels are three separate
gates. A dialog can render its frame and title while the client area is black.

## Drive controls across processes

Send text with UI Automation or `WM_SETTEXT` (`SendMessageW`). `SetWindowText`
on a wrapper such as `ComboBox` may succeed without changing the nested edit
field. Locate the child `Edit` control with `FindWindowEx` and target it.

For owner-drawn, Chromium, WinUI, or custom controls, standard Win32 messages
may not work. Use the framework API or UI Automation instead.

When source is unavailable, application state can still be driven through
document content and app-specific controls. For Scintilla, for example, margin
messages can set a temporary line-number width without changing the user's
persistent preference.

## Capture and validate pixels

For CPU/GDI windows, capture the exact handle with
`PrintWindow(PW_RENDERFULLCONTENT)`. Check the Boolean return, then validate
the image itself; the API can return success for an unpainted frame.

Apply all relevant gates:

- expected width and height
- expected scene count and filename
- minimum file size
- non-uniform sampled pixels
- scene-aware dark-pixel ratio
- an expected landmark or control region
- human visual review of every final frame

Do not use a universal black-pixel threshold for dark themes. Calibrate the
content check to the expected scene or use landmark matching. A threshold that
rejects more than 50 percent near-black pixels is reasonable only for an
expected light-theme dialog.

Validate that each Markdown image target exists and that the documentation
does not embed stale captures from an earlier run.

## Restore state and clean up

Before changing a toggle, margin, zoom, or other view option, capture its
current value. Keep the original `System.Diagnostics.Process` object as the
ownership token instead of reacquiring a process by PID. In `finally`:

1. Restore every changed option to its original value.
2. Close modal dialogs with `WM_CLOSE` or the application's close action.
3. Close the main window gracefully.
4. Kill only the process started by the driver, and only after a bounded
   graceful-close timeout.
5. Dispose bitmaps, graphics contexts, event hooks, and process objects.
6. Assert that no started target process remains.

Never terminate pre-existing instances owned by the user. Check `HasExited` on
the original process object before each operation. If a single-instance
launcher exits after forwarding to an existing process, stop or treat that
instance as user-owned; do not adopt it from a title or reused PID.

Run revised `Add-Type` P/Invoke code in a clean `pwsh` process. A .NET type
already loaded into a persistent session cannot be replaced by a later
definition with the same full name.

## Failure patterns

| Symptom | Likely cause | Correction |
| --- | --- | --- |
| Dialog title over black client area | Frame exists but content pixels are not ready | Require expected child state, then retry capture validation within a bound |
| Search value does not appear | Text sent to a combo wrapper | Target its child `Edit` with `WM_SETTEXT` |
| Wrong window captured | Foreground or title-only discovery | Scope by started process plus class/title/owner |
| Capture passes size check but is blank | `PrintWindow` success treated as content proof | Add pixel and landmark validation plus visual review |
| Settings remain changed after capture | Toggle used without preserving initial state | Snapshot first and restore in `finally` |
| New P/Invoke method is missing | Old `Add-Type` type remains loaded | Execute the revised script in a clean process |
