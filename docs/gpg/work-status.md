# GPG Encryption Feature - Work Status

This document tracks the progress of the different work streams for the GPG encryption feature. Teams are expected to update the status of their respective items and link to their pull requests once they are open.

| Work Stream                               | Team                      | Status        | Pull Request (PR) | Notes                               |
| ----------------------------------------- | ------------------------- | ------------- | ----------------- | ----------------------------------- |
| **1. Infrastructure & Environment Setup** | DevOps                    | `Completed` | [3da959b](https://github.com/ttionya/vaultwarden-backup/commit/3da959bd1232fef8c5d5fb52de4b3587a3a85363) | Modify `Dockerfile` to add `gnupg`. |
| **2. Backend Scripting**                  | Backend/Shell Scripting   | `Completed`   | [4454e28](https://github.com/ttionya/vaultwarden-backup/commit/4454e28) | Implement encryption in `backup.sh`.  |
| **3. Automated Testing**                  | QA/Test Automation        | `Completed` | [4454e28](https://github.com/ttionya/vaultwarden-backup/commit/4454e28)                | Create new test unit `backup-gpg`.    |
| **4. User Documentation**                 | Technical Writing/Docs    | `Completed` | [Local Implementation]                | Update `README.md` with GPG info.   |
| **5. Final Integration & Verification**   | Release Manager/Lead Dev  | `Not Started` | \-                | Merge all PRs and conduct manual E2E testing. |

---

## GPG Signing Feature - Work Status

This section tracks progress for the GPG Signing enhancement (inline sign + optional detached signature).

| Work Stream | Status | Commit(s) | Notes |
| --- | --- | --- | --- |
| 1. Env plumbing (includes.sh) | `Completed` | 05e928f | Load signing env vars; safe summary logging only. |
| 2. Ephemeral GNUPGHOME + loopback | `Completed` | da15273 | Temp GNUPGHOME per run; cleanup and loopback pinentry. |
| 3. Import signer key + validation | `Completed` | e1738a5 | Import private key when signing enabled; validate signer key presence. |
| 4. Sign-and-encrypt path | `Completed` | 025aa5a | Use gpg --sign --encrypt with signer; fallback to encrypt-only when disabled. |
| 5. Detached signature + upload | `Completed` | d1471ae | Optional .gpg.sig generation and upload alongside ciphertext. |
| 6. Tests (TC5 inline, TC6 detached) | `Completed` | eb1386d, 53a792c | Add tests and stabilize verification/log assertions. |
| 7. Documentation updates | `Completed` | 72f77f4, ff59c7d | README signing section + execution plan doc. |
| 8. Release tracking (CHANGELOG/version) | `Not Started` | \- | Add CHANGELOG entry and version bump when releasing. |
| Security hardening: passphrase handling | `Completed` | 6e3162d | Prefer --passphrase-file; avoid exporting passphrase; temp file fallback + cleanup. |

### How to Update

1.  Find the row for your work stream.
2.  Change the **Status** to `In Progress` when you begin work.
3.  Once you create a pull request, add the link or PR number to the **Pull Request (PR)** column.
4.  When the PR is merged, change the **Status** to `Completed`.
