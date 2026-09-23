# Couch Remote

A small native Mac app that turns a game controller into a couch-friendly mouse and keyboard. Built and tested with the 8BitDo Ultimate 2 Wireless controller.

Open **Couch Remote** from Applications or Spotlight. On first launch, enable it in **System Settings → Privacy & Security → Accessibility**. It notices the permission automatically. Close the controls window when ready; the controller icon stays in the menu bar.

| Controller | Action |
| --- | --- |
| Left stick | Move the pointer |
| Right stick | Scroll |
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

System volume controls behave like the Mac’s own volume keys. Some HDMI televisions manage volume only on the TV; the G/H assignments still send those keys to your active app. The Fn action follows the behavior selected for the Globe key in macOS Keyboard settings. Holding left-stick click and clicking right-stick click opens the macOS app switcher (Command–Tab); release the left-stick click to choose the highlighted app.

## Build

Requires the Apple command-line developer tools and Node with TypeScript support. Run `node build.ts` from this directory. The build reads `.env.local`, compiles the native Swift app, generates its icon, signs it locally, and runs the non-interactive core checks. The result is `build/Couch Remote.app`; `node build.ts --install` installs it in the main `/Applications` folder.

Native AppKit and GameController APIs provide background controller input, a normal menu-bar app, and macOS mouse/keyboard events without a browser or a running terminal. The app uses only the connected 8BitDo controller and does not require network access. It uses the sticks, not motion aiming; macOS does not expose motion sensors for this controller connection.
