# Updating Couch Remote

The app is currently ad-hoc signed with `codesign -s -`. Rebuilding changes its code identity, so replacing and restarting the installed app can invalidate macOS Accessibility approval. In that state, controller input still reaches the app, but macOS blocks the generated mouse and keyboard events.

Keep the installed app running while building, testing, committing, and pushing. Replace and restart it only as the final step. Afterward, verify `accessibility` is `true` in `$TMPDIR/couch-remote-status.json`; do not infer success from controller detection alone.

If approval becomes stale, run `tccutil reset Accessibility local.josh.couchremote`, restart the app, and have the user re-enable Couch Remote in Privacy & Security > Accessibility. macOS requires that user action. A stable code-signing identity would prevent this on future updates.
