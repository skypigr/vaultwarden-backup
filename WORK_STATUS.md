# GPG Encryption Feature - Work Status

This document tracks the progress of the different work streams for the GPG encryption feature. Teams are expected to update the status of their respective items and link to their pull requests once they are open.

| Work Stream                               | Team                      | Status        | Pull Request (PR) | Notes                               |
| ----------------------------------------- | ------------------------- | ------------- | ----------------- | ----------------------------------- |
| **1. Infrastructure & Environment Setup** | DevOps                    | `Completed` | [3da959b](https://github.com/ttionya/vaultwarden-backup/commit/3da959bd1232fef8c5d5fb52de4b3587a3a85363) | Modify `Dockerfile` to add `gnupg`. |
| **2. Backend Scripting**                  | Backend/Shell Scripting   | `Not Started` | \-                | Implement encryption in `backup.sh`.  |
| **3. Automated Testing**                  | QA/Test Automation        | `Not Started` | \-                | Create new test unit `backup-gpg`.    |
| **4. User Documentation**                 | Technical Writing/Docs    | `Not Started` | \-                | Update `README.md` with GPG info.   |
| **5. Final Integration & Verification**   | Release Manager/Lead Dev  | `Not Started` | \-                | Merge all PRs and conduct manual E2E testing. |

---

### How to Update

1.  Find the row for your work stream.
2.  Change the **Status** to `In Progress` when you begin work.
3.  Once you create a pull request, add the link or PR number to the **Pull Request (PR)** column.
4.  When the PR is merged, change the **Status** to `Completed`.
