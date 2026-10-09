import { execFileSync, spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadEnvFile } from "node:process";
import { signingIdentity } from "./signing.ts";

// Creates the self-signed certificate that gives every build the same code identity,
// so macOS keeps Couch Remote's Accessibility approval across updates.
const root = dirname(fileURLToPath(import.meta.url));
loadEnvFile(join(root, ".env.local"));
const keychain = join(process.env.HOME!, "Library", "Keychains", "login.keychain-db");
if (spawnSync("security", ["find-certificate", "-c", signingIdentity, keychain]).status === 0) {
  console.log(`${signingIdentity} already exists in the login keychain.`);
  process.exit(0);
}
const work = mkdtempSync(join(tmpdir(), "couch-remote-signing-"));
try {
  const config = join(work, "cert.cnf");
  writeFileSync(config, [
    "[req]",
    "distinguished_name = dn",
    "x509_extensions = ext",
    "prompt = no",
    "[dn]",
    `CN = ${signingIdentity}`,
    "[ext]",
    "basicConstraints = critical, CA:false",
    "keyUsage = critical, digitalSignature",
    "extendedKeyUsage = critical, codeSigning",
    "",
  ].join("\n"));
  const key = join(work, "key.pem");
  const cert = join(work, "cert.pem");
  const bundle = join(work, "identity.p12");
  const password = randomBytes(16).toString("hex");
  execFileSync("/usr/bin/openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "3650", "-config", config, "-keyout", key, "-out", cert]);
  execFileSync("/usr/bin/openssl", ["pkcs12", "-export", "-inkey", key, "-in", cert, "-out", bundle, "-passout", `pass:${password}`]);
  execFileSync("security", ["import", bundle, "-k", keychain, "-P", password, "-T", "/usr/bin/codesign"], { stdio: "inherit" });
  console.log(`Created ${signingIdentity} in the login keychain.`);
} finally {
  rmSync(work, { recursive: true, force: true });
}
