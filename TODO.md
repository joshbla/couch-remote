# Couch Remote — To Do

## Prevent controller-profile failures from leaving the remote unusable

Queued by the user for future work; documentation only for now. The controller
became invisible to Apple's GameController framework while Bluetooth and HID
still saw it. The confirmed cause, diagnostic evidence, unsuccessful attempts,
and verified recovery are in [the detection runbook](docs/controller-detection.md).

Next step: investigate why `GameControllerConfigService` retained references to
missing profile files, then design a durable prevention or recovery mechanism.
An app reconnect loop alone cannot repair this failure. Evaluate how the app can
distinguish a powered-off controller from a connected HID device that the
framework cannot load, and make the supported recovery clear to the user.

Completion requires verification of the confirmed failure scenario, normal
Bluetooth reconnects, live stick/button input, and Accessibility permission.
The successful manual service restart is recovery evidence, not a permanent fix.

## Fix excessive temp-file writes from status refresh

While diagnosing a controller-detection failure, macOS filed a microstackshot
(`CouchRemote_*.diag`, action: none) reporting that CouchRemote wrote ~2 GB of
file-backed memory over ~22 hours and exceeded the system's disk-write limit
(~24.86 KB/s over 86400s).

Cause: `refreshStatus()` runs about once per second from `tick()` and rewrites
`$TMPDIR/couch-remote-status.json` with `.atomic` on every call, including when
none of the reported values have changed.

Next step: only write the snapshot when the payload actually changes (or throttle
to a much longer interval), so the app is not writing to disk continuously.
