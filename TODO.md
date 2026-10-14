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
