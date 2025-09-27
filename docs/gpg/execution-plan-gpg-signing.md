Title: GPG Signing for Encrypted Backups — Execution Plan

Summary
- Goal: Add signing to the existing GPG encryption flow so backups are signed and encrypted by default, with an option to also produce a detached signature of the ciphertext for out-of-band verification.
- Design decision: Use a separate signing key whose private key is imported into the backup container only for signing. Keep the recipient’s decryption private key out of the container.
- Backward compatibility: When signing is disabled, current encryption-only behavior remains unchanged. When GPG is disabled, behavior remains unchanged.

Key Repo Pointers (as of creation)
- Encryption entry point: scripts/backup.sh:154 (function encrypt_with_gpg)
- Packaging flow: scripts/backup.sh:205 (function backup_package)
- Upload flow: scripts/backup.sh:235 (function upload)
- GPG env loading: scripts/includes.sh:656 (function init_env_gpg)
- Tests for GPG encryption: tests/units/backup-gpg/test.sh
- User docs for GPG encryption: README.md:138 and variable docs around README.md:404
- Dockerfile includes gnupg already

Configuration Overview (new environment variables)
- GPG_SIGN_ENABLE=TRUE|FALSE — enable inline signing during encryption (default FALSE)
- GPG_SIGNER=<UID or key ID> — the signer identity to use with gpg --local-user
- GPG_SIGNING_PRIVATE_KEY_BASE64=<base64 of ASCII-armored private key or signing subkey>
- GPG_SIGNING_PASSPHRASE (supports _FILE via existing get_env)
- GPG_DETACHED_SIGN_ENABLE=TRUE|FALSE — optionally produce a detached signature of the ciphertext (default FALSE)
- GPG_SIG_ARMOR=TRUE|FALSE — armor detached signature (default TRUE)
- Notes:
  - Continue to use existing variables for encryption: GPG_ENABLE, GPG_RECIPIENT, GPG_PUBLIC_KEY_BASE64, GPG_TRUST_LEVEL
  - Do not log secrets; only echo minimal non-sensitive info (e.g., signer UID or key ID)

Security Constraints
- Never import the recipient’s decryption private key into the backup container.
- Use a dedicated signing key (or signing subkey) with a passphrase, supplied via secret file env when possible.
- Use an ephemeral GNUPGHOME with allow-loopback-pinentry; delete it after use.
- Avoid logging passphrases or private material; log only high-level status and non-sensitive metadata.

Behavioral Design
- Default: Inline sign-and-encrypt one-pass output (single .zip.gpg). Verify signature during decryption time.
  Command shape: gpg --sign --encrypt --local-user "$GPG_SIGNER" --recipient "$GPG_RECIPIENT" ...
- Optional: Detached signature of ciphertext (two files: .zip.gpg and .zip.gpg.sig) to allow verification without decryption.
  Command shape: gpg --detach-sign [--armor] --local-user "$GPG_SIGNER" "$encrypted_file"

Actionable TODOs (assignable, minimal file reads required)

[ ] T1: Add signer env plumbing
- Files: scripts/includes.sh:656
- Tasks:
  - Extend init_env_gpg to read: GPG_SIGN_ENABLE, GPG_SIGNER, GPG_SIGNING_PRIVATE_KEY_BASE64, GPG_SIGNING_PASSPHRASE, GPG_DETACHED_SIGN_ENABLE, GPG_SIG_ARMOR
  - Ensure get_env is used so _FILE variants work; default GPG_SIG_ARMOR=TRUE
  - Echo only summary lines (e.g., signer UID, boolean flags, length of private key string), never actual key or passphrase content
- Acceptance:
  - Running backup shows new GPG signing settings when enabled, without leaking secrets

[ ] T2: Ephemeral GNUPGHOME setup and teardown
- Files: scripts/backup.sh:154 (encrypt_with_gpg or a new helper)
- Tasks:
  - Create a temp directory; set GNUPGHOME to it (chmod 700)
  - Create "$GNUPGHOME/gpg-agent.conf" with allow-loopback-pinentry
  - Use --pinentry-mode loopback for all gpg calls
  - Ensure cleanup (rm -rf) in success and failure paths
- Acceptance:
  - gpg operations proceed non-interactively; temp dir is deleted post-run

[ ] T3: Import signer private key + passphrase handling
- Files: scripts/backup.sh:154
- Tasks:
  - When GPG_SIGN_ENABLE=TRUE, import base64-decoded private key via gpg --batch --import
  - For signing operations, pass --pinentry-mode loopback and include --passphrase "$GPG_SIGNING_PASSPHRASE" only if set
  - Fail fast with clear error + send_notification on import failure
- Acceptance:
  - Key import succeeds and errors are reported cleanly; no passphrase or key material logged

[ ] T4: Implement inline sign-and-encrypt path
- Files: scripts/backup.sh:154
- Tasks:
  - If GPG_SIGN_ENABLE=TRUE: run gpg --yes --batch --trust-model "$GPG_TRUST_LEVEL" --pinentry-mode loopback ${GPG_SIGNING_PASSPHRASE:+--passphrase "$GPG_SIGNING_PASSPHRASE"} --local-user "$GPG_SIGNER" --recipient "$GPG_RECIPIENT" --sign --encrypt --output "$source_file.gpg" "$source_file"
  - Else: keep current encryption-only path
  - Preserve logic to delete plaintext and set UPLOAD_FILE to the .gpg path
- Acceptance:
  - .zip.gpg produced with embedded signature when enabled; encryption-only path unaffected when disabled

[ ] T5: Optional detached signature of ciphertext
- Files: scripts/backup.sh:154, scripts/backup.sh:235
- Tasks:
  - If GPG_DETACHED_SIGN_ENABLE=TRUE, after producing "$encrypted_file", run: gpg --yes --batch --local-user "$GPG_SIGNER" --pinentry-mode loopback ${GPG_SIGNING_PASSPHRASE:+--passphrase "$GPG_SIGNING_PASSPHRASE"} ${GPG_SIG_ARMOR:+--armor} --detach-sign --output "$encrypted_file.sig" "$encrypted_file"
  - Update upload to also copy "$encrypted_file.sig" if present
- Acceptance:
  - .zip.gpg.sig created/ uploaded when enabled; no change otherwise

[ ] T6: Tests — extend GPG unit tests
- Files: tests/units/backup-gpg/test.sh
- Tasks:
  - Generate separate signer keypair in test; export signer public key for verification
  - TC5: Inline sign+encrypt → run backup with GPG_SIGN_ENABLE, provide signer private key and passphrase; verify decrypt shows “Good signature” using signer public key
  - TC6: Detached sig → enable GPG_DETACHED_SIGN_ENABLE; assert .zip.gpg.sig exists; gpg --verify on ciphertext passes
  - Negative cases: missing GPG_SIGNER, missing private key, wrong passphrase → graceful failures with clear messages
- Acceptance:
  - New tests pass locally; existing TC1–TC4 unaffected

[ ] T7: Documentation updates
- Files: README.md:138, README.md:404
- Tasks:
  - Add “GPG Signing” subsection: default inline signing, optional detached signature, and separate-keys rationale
  - Document new env vars; add docker-compose and docker run examples
  - Add short “verify signature” snippets for inline (during decrypt) and detached (gpg --verify)
- Acceptance:
  - Docs accurate, copy-pasteable, and consistent with implemented flags

[ ] T8: Release tracking
- Files: CHANGELOG.md, docs/gpg/work-status.md, version
- Tasks:
  - Add CHANGELOG entry
  - Update WORK_STATUS with T1–T7 statuses
  - Bump version when ready
- Acceptance:
  - Repo reflects feature availability and status

End-to-End Acceptance Criteria
- With signing enabled, backups produce a signed-and-encrypted .zip.gpg; decrypting with the recipient’s private key reports a “Good signature” from GPG_SIGNER.
- With detached signing enabled, .zip.gpg.sig is created and uploaded; gpg --verify passes against .zip.gpg using signer’s public key.
- No secret material is printed; ephemeral keyring is cleaned up.
- Encryption-only and no-GPG flows remain backward compatible.

Operational Notes and Rollback
- Feature gates: GPG_SIGN_ENABLE and GPG_DETACHED_SIGN_ENABLE; disabling either reverts to simpler behavior without code rollback.
- Key rotation: signer and recipient keys can be rotated independently; ensure docs call this out.

Appendix: Minimal Command Shapes (reference)
- Inline sign+encrypt:
  gpg --yes --batch --trust-model "$GPG_TRUST_LEVEL" --pinentry-mode loopback \
    ${GPG_SIGNING_PASSPHRASE:+--passphrase "$GPG_SIGNING_PASSPHRASE"} \
    --local-user "$GPG_SIGNER" --recipient "$GPG_RECIPIENT" \
    --sign --encrypt --output "$out" "$in"
- Detached signature of ciphertext:
  gpg --yes --batch --local-user "$GPG_SIGNER" --pinentry-mode loopback \
    ${GPG_SIGNING_PASSPHRASE:+--passphrase "$GPG_SIGNING_PASSPHRASE"} \
    ${GPG_SIG_ARMOR:+--armor} --detach-sign --output "$out.sig" "$out"
