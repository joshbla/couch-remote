# Controller detection: stale macOS profile references

This is ongoing troubleshooting reference documentation. Future prevention work
is tracked in root `TODO.md`. The confirmed recovery below restored operation;
no prevention change has been implemented in Couch Remote.

## User-visible failure

The 8BitDo Ultimate 2 Wireless had worked, then Couch Remote stopped detecting it
while macOS Bluetooth still showed it connected. Power-cycling the controller
and restarting the app did not restore detection. The app remained enabled and
had valid Accessibility permission, but reported `connected: false`.

## Confirmed diagnosis

The failure was in Apple's controller-profile configuration helper,
`GameControllerConfigService`. It held a matching controller definition but could
not load the associated profile files.

Evidence collected before recovery:

- Bluetooth and `hidutil` both saw the controller over Bluetooth Low Energy.
- HID identity: vendor `11720` (`0x2dc8`), product `24594` (`0x6012`), revision `1`;
  usage page `1`, usage `5` (gamepad).
- A separate GameController probe returned **zero controllers**, demonstrating
  that the app's vendor-name filter was not causing this failure.
- The on-disk Apple controller database contained an exact identity match and
  profiles for `com.8BitDo.Ultimate2WirelessController.BLE`.
- Despite those files being present, the running configuration helper logged:

  ```text
  Error loading device personality
  Invalid device personality
  No such file or directory
  Found matching device definition com.8BitDo.Ultimate2WirelessController.BLE
  ... but did not find a compatible personality.
  ```

  The error's underlying file path was privacy-redacted in the system log.
  The helper reported the custom mapping bundle as version `10.5.2`; the
  inspected on-disk bundle reported version `17.6.1`.

After restarting the configuration helper and controller daemon, the new helper
refreshed its configuration assets. The daemon logged that the device **was a
supported game controller**, initiated rematching, and prepared the physical
device. An independent probe then returned **one controller**, named
`8BitDo Ultimate 2 Wireless`, with an extended gamepad profile.

This supports stale profile references as the immediate cause. The exact event
that left those references stale, including whether an asset update was involved,
has not been established. Long uptime alone is not a diagnosis.

## Diagnose this specific failure

1. Confirm Couch Remote is actually running and its status snapshot is fresh:

   ```sh
   pgrep -fl CouchRemote
   stat -f '%Sm' "$TMPDIR/couch-remote-status.json"
   ```

   Inspect that JSON for `connected`, `accessibility`, `enabled`, `buttonPresses`,
   and `lastInput`. A stopped app leaves an old file behind; an old snapshot is
   not evidence of the current connection or permissions.

2. Check whether the controller exists below the GameController framework:

   ```sh
   hidutil list --matching '{"VendorID":11720,"ProductID":24594}'
   ```

   This identity is specific to the confirmed Ultimate 2 Wireless BLE connection.

3. Inspect the configuration helper's logs, not just the controller daemon's:

   ```sh
   /usr/bin/log show --last 10m --info --debug --style compact \
     --predicate 'process == "GameControllerConfigService" OR process == "gamecontrollerd"'
   ```

   Look for the matching BLE definition together with the missing-profile errors
   above. Use `/usr/bin/log` explicitly: the shell's unqualified `log` command
   resolved differently during diagnosis and obscured useful output.

## Verified manual recovery

For the confirmed missing-profile error, run these commands with administrator
authorization, in this order:

```sh
sudo killall -KILL GameControllerConfigService
sudo killall -TERM gamecontrollerd
```

macOS relaunched both services automatically during the verified recovery.
The configuration helper survived a `TERM` signal, so verify that its process ID
changes; successfully sending a signal does not prove it restarted.

```sh
pgrep -fl 'GameControllerConfigService|/usr/libexec/gamecontrollerd'
```

Then quit Couch Remote and reopen `/Applications/Couch Remote.app`. Confirm the
old app process has exited before reopening it: launching while the old process
is still terminating can leave no running app and a stale status file.

Verify all of the following before reporting success:

- The app has a live process and the status file is being updated.
- `connected`, `accessibility`, and `enabled` are all `true`.
- Moving the left stick produces `Receiving left stick · pointer moving`.
- A button press increments `buttonPresses` and updates `lastInput`.

The completed recovery was verified with all three flags true, three received
button presses, and live left-stick pointer movement. It required no rebuild,
Accessibility reset, WindowServer restart, or Mac reboot.

## Unsuccessful attempts and corrected conclusions

- Controller power-cycles and app restarts did not fix the stale profile helper.
- Restarting `gamecontrolleragentd` did not restore detection.
- Restarting `gamecontrollerd` alone left the old configuration helper alive and
  still unable to load the profiles.
- Wireless controller discovery in the independent probe returned no controllers
  while the helper remained stale.
- `launchctl kickstart` was blocked by System Integrity Protection, including
  with administrator authorization. The verified recovery used process signals.
- `IOBluetoothDevice.closeConnection()` returned success but did not actually
  remove this BLE HID device; its registry IDs stayed unchanged. It was not a
  verified disconnect/reconnect.
- WindowServer/controller-daemon reconnect messages initially led to an incorrect
  WindowServer-wedge diagnosis. Those messages were not sufficient to establish
  the root cause. The configuration helper's missing-file errors were decisive,
  and the successful recovery did not restart WindowServer.

These are recorded to avoid repeating the unsuccessful path. Manual service
recovery does not establish that the problem cannot recur; durable prevention
remains an outstanding task in `TODO.md`.
