# Couch Remote

A small native Mac app that turns a game controller into a couch-friendly mouse and keyboard. Built and tested with the 8BitDo Ultimate 2 Wireless controller.

Open **Couch Remote** from Applications or Spotlight. On first launch, enable it in **System Settings → Privacy & Security → Accessibility**. It notices the permission automatically. Close the controls window when ready; the controller icon stays in the menu bar.

| Controller | Action |
| --- | --- |
| Left stick | Move the pointer |
| Right stick up / down | Scroll vertically |
| Right stick left / right | Left / Right arrow keys; hold to repeat |
| A (bottom face button) | Left click; hold to drag |
| B (right face button) | Right click |
| X (left face button) | Space |
| Y (top face button) | Return |
| LB / RB | A / D |
| D-pad up / down | System volume up / down |
| D-pad left / right | G / H |
| Press left stick | Hold Command; release to select an app in the switcher |
| Press right stick | Tab; click repeatedly while holding left stick to cycle apps |
| LT | Hold for slow, precise pointer movement |
| RT | Fn / Globe key |
| Select / View | Escape |
| Start / Menu | Pause or resume the remote |

Button assignments and pointer speed can be changed in the controls window and are saved automatically. “Open automatically when I log in” is optional. A disconnected controller reconnects automatically while the app is open. Quit from the menu-bar icon to stop it entirely.

The right stick uses its dominant direction: mostly vertical movement scrolls, while mostly horizontal movement sends arrow keys. Returning to center or switching to vertical movement releases the arrow key.

System volume controls behave like the Mac’s own volume keys. Some HDMI televisions manage volume only on the TV; the G/H assignments still send those keys to your active app. The Fn action follows the behavior selected for the Globe key in macOS Keyboard settings. Holding left-stick click and clicking right-stick click opens the macOS app switcher (Command–Tab); release the left-stick click to choose the highlighted app.

## Troubleshooting controller detection

If Bluetooth shows the controller connected but Couch Remote cannot detect it, inspect the logs for `GameControllerConfigService`. A confirmed failure was a stale controller-profile reference: the helper logged `Error loading device personality`, `No such file or directory`, and a matching `com.8BitDo.Ultimate2WirelessController.BLE` definition without a compatible personality.

For that specific failure, restarting the configuration helper and then the controller daemon restored detection without rebooting:

```sh
sudo killall -KILL GameControllerConfigService
sudo killall -TERM gamecontrollerd
```

macOS restarts these services automatically. Quit and reopen Couch Remote afterward. Verify a fresh `$TMPDIR/couch-remote-status.json` reports `connected`, `accessibility`, and `enabled` as `true`, then move a stick or press a button to confirm live input. Restarting the controller daemon alone did not fix the stale configuration helper.

The [controller-detection runbook](docs/controller-detection.md) preserves the diagnostic evidence, unsuccessful attempts, and verification procedure. Recurrence prevention is queued in [TODO.md](TODO.md); the service restart above is the confirmed manual recovery.

## Build

Requires the Apple command-line developer tools and Node with TypeScript support. Run `node build.ts` from this directory. The build reads `.env.local`, compiles the native Swift app, generates its icon, signs it locally, and runs the non-interactive core checks. The result is `build/Couch Remote.app`; `node build.ts --install` installs it in the main `/Applications` folder.

Builds are signed with a self-signed “Couch Remote Local Signing” certificate in the login keychain. Because every build carries the same signing identity, macOS keeps the Accessibility approval across updates. On a new Mac, run `node signing-identity.ts` once before building; it creates the certificate and does nothing if it already exists. Recreating the certificate changes the identity, so Accessibility must be approved again once afterward. Keychain Access lists the certificate as untrusted; that is expected and does not affect local signing.

Native AppKit and GameController APIs provide background controller input, a normal menu-bar app, and macOS mouse/keyboard events without a browser or a running terminal. The app uses only the connected 8BitDo controller and does not require network access. It uses the sticks, not motion aiming; macOS does not expose motion sensors for this controller connection.
