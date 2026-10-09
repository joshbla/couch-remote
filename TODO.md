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

## Verify the stable-signing update with the controller

The update with right-stick arrow keys, change-only status writes, and the new
"Couch Remote Local Signing" certificate is installed. Changing from ad-hoc to
certificate signing requires one final Accessibility re-approval, which the user
will grant. Next: confirm live status reports `accessibility: true`, sideways
right-stick movement sends arrow keys, vertical movement still scrolls, and that
approval survives the next rebuild and reinstall without another reset.
