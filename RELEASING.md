# Releasing

Releases are automated with [release-please](https://github.com/googleapis/release-please). It derives versions, `CHANGELOG.md`, git tags and GitHub Releases from commit messages. Nobody edits or runs them by hand.

This project ships no binaries and is not published to a package registry. A release is a git tag and a GitHub Release with notes. You install a release by building it from the tag:

```bash
git fetch --tags
git checkout vX.Y.Z
make install
```

## Flow

1. Create a branch and commit the changes.
2. Open a PR with a **Conventional Commit title**. When the PR is squash-merged into `main`, the title decides the next version:

   | PR title prefix | Example | Version bump |
   |---|---|---|
   | `fix:` | `fix: keep the strip after a display change` | patch (0.1.0 → 0.1.1) |
   | `feat:` | `feat: add a --quiet option` | minor (0.1.0 → 0.2.0) |
   | `feat!:` / `fix!:` or a `BREAKING CHANGE:` footer | `feat!: rename the login agent label` | major (0.1.0 → 1.0.0) |
   | `chore:`, `docs:`, `refactor:`, `test:`, `ci:` | `docs: fix typo` | no release |

3. Squash-merge the PR to `main`.
4. **release-please** opens or updates a **Release PR** titled `chore(main): release X.Y.Z`. It bumps the version in `.release-please-manifest.json` and in the `VERSION` line of `Sources/main.swift`, and adds the new section to `CHANGELOG.md`. If several PRs are merged before a release, they go into one Release PR.
5. Merging the Release PR runs `release.yml` again, which:
   - creates the `vX.Y.Z` git tag,
   - publishes a GitHub Release with the changelog notes.

To release, merge the code PRs, approve the Release PR's checks, then merge the Release PR.

## Approve the Release PR checks

The Release PR is authored by `github-actions[bot]`, because `release.yml` passes `github.token` to release-please. GitHub creates the PR's checks but holds them until a user with write access approves them.

**Open the Release PR's Checks tab and click "Approve and run" before merging.**

- There is no CLI for this step.
- The approval does not carry over. You need it on every release, and again whenever release-please updates an open Release PR.
- **If you merge without approving, the runs turn red.** They end as `failure` with zero jobs and no logs. That means nobody approved them, not that anything broke.

GitHub added this approval step for [pull requests created by bots](https://github.blog/changelog/2026-06-11-bot-created-pull-requests-can-run-workflows-if-approved/). It applies to branches in the same repo, not only to forks, and there is no repository setting to turn it off. The only way around it is to author the Release PR as a different identity, which needs a GitHub App or a personal access token. Neither is set up here, and the click is cheaper.

## Repository settings

These are set on GitHub and are required for the flow above.

### Branch protection on `main`

- **A pull request is required before merging**, with 0 required approvals. This also applies to admins.
- **Linear history is required**, which matches squash merges.
- **Force-pushes and deletions are blocked.**
- **No status checks are required.** The Release PR's checks wait for approval, so a required check would block the Release PR until someone approves it.

### Merging

- **Squash merging only.** Merge commits and rebase merging are off.
- **The squash commit title is the PR title**, so release-please reads the Conventional Commit title.
- **Head branches are deleted after merge.**

### Actions permissions

Under **Settings → Actions → General → Workflow permissions**:

1. **Read repository contents and packages permissions.** Each workflow asks for any extra permissions it needs, and `release.yml` asks for `contents: write` and `pull-requests: write`.
2. **Allow GitHub Actions to create and approve pull requests.**

Without (2), release-please can update its branch but cannot open the Release PR (`GitHub Actions is not permitted to create or approve pull requests`).

## Notes

- **PR titles drive releases.** With squash merges, the PR title becomes the commit that release-please reads. Titles that start with `chore:`, `docs:` or `ci:` produce no release, on purpose.
- **The version's source of truth** is `.release-please-manifest.json`. release-please keeps the `VERSION` line in `Sources/main.swift` in sync through the `x-release-please-version` marker on that line. Do not edit either one by hand for routine releases.
- `release-please-config.json` holds the rest of the configuration.

## Manual fallback

A manual tag skips the changelog and the manifest update. Use the Release PR flow when you can. If you can't:

```bash
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
gh release create vX.Y.Z --generate-notes
```
