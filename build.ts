import { execFileSync } from "node:child_process";
import { copyFileSync, cpSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadEnvFile } from "node:process";

const root = dirname(fileURLToPath(import.meta.url));
loadEnvFile(join(root, ".env.local"));
const app = join(root, "build", "Couch Remote.app");
const contents = join(app, "Contents");
mkdirSync(join(contents, "MacOS"), { recursive: true });
mkdirSync(join(contents, "Resources"), { recursive: true });
copyFileSync(join(root, "Info.plist"), join(contents, "Info.plist"));
const binary = join(contents, "MacOS", "CouchRemote");
execFileSync("xcrun", ["swiftc", "-O", "-swift-version", "5", "-framework", "AppKit", "-framework", "GameController", "-framework", "ServiceManagement", join(root, "RemoteCore.swift"), join(root, "main.swift"), "-o", binary], { stdio: "inherit" });
execFileSync(binary, ["--make-icon", join(contents, "Resources", "AppIcon.icns")], { stdio: "inherit" });
execFileSync("codesign", ["--force", "--sign", "-", "--identifier", "local.josh.couchremote", app], { stdio: "inherit" });
execFileSync(binary, ["--self-test"], { stdio: "inherit" });
console.log(`Built ${app}`);
if (process.argv.includes("--install")) {
  const installed = join(homedir(), "Applications", "Couch Remote.app");
  cpSync(app, installed, { recursive: true, force: false, errorOnExist: true });
  console.log(`Installed ${installed}`);
}
