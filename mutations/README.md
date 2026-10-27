# Mutation Branch Archive

This folder stores archived patches from retired mutation branches (`refs/heads/mutation/*`).

All files and entries in this directory are written and maintained exclusively by `scripts/retire_mutation_branches.sh`. Never edit, add, or delete files in this directory manually.

## Structure

- `MANIFEST.tsv`: Tab-separated index of all archived mutation branches.
- `<slice-id>/<branch-leaf>.patch`: Standard Git mailbox patches generated via `git format-patch --stdout <base_sha>..<head_sha>`.

## Manifest Columns

| Column | Description |
|---|---|
| `repo` | Repository name where the mutation branch was created. |
| `branch` | Full remote ref name of the branch (for example `mutation/cs2-d1`). |
| `head_sha` | Git commit SHA of the mutation branch head prior to retirement. |
| `base_sha` | Git commit SHA of the merge base with `origin/main`. |
| `patch_sha256` | SHA-256 checksum of the archived `.patch` file. |
| `tree_match` | Status indicator (`yes`) verifying that applying the patch via `git am` over `base_sha` produces an identical tree SHA (`head_sha^{tree}`). |

## How to Rerun a Mutation

To inspect or re-execute a mutation locally:

```bash
git worktree add --detach /tmp/m <base_sha>
cd /tmp/m
git am < <path-to-patch-file>
```

## Historical Context

- Mutation slice identifier prefixes are catalogued in `CHANGELOG.md`.
- Mutation branches retired prior to Cleanup slice 3 (Map slices 1.1.1 to 1.6 and Cleanup slice 1) were archived outside the repositories and are not included in this directory.
