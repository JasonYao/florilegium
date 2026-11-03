# Updating this fork

Branches in this fork:

- `main`: a clean mirror of the upstream's `main`. No local commits.
- `core-patchset`: our patches, rebased on top of `main`. Clients pin this branch.

Remotes: `origin` is this fork; `upstream` is the original project
(`<UPSTREAM_URL>`, replace with the real URL).

## A. Keep `main` up to date with the upstream

One-time setup:

```sh
git remote add upstream <UPSTREAM_URL>
```

Each update:

```sh
git fetch upstream --tags
git checkout main
git merge --ff-only upstream/main   # fails if main has local commits: it shouldn't
git push origin main --tags
```

If `--ff-only` fails, `main` has diverged. Move any local commits to
`core-patchset` first, then `git reset --hard upstream/main` on `main`.

## B. Rebase the patchset on top of the upstream

After `main` is updated:

```sh
git checkout core-patchset
git rebase main                     # or: git rebase --onto main <old-main-sha>
# resolve conflicts, then: git add <files> && git rebase --continue
# (git rebase --abort backs out)
```

Check the result (`tools/versioncheck.sh`, `make`, `tools/svgcheck.sh texlua`),
then publish. The history was rewritten, so a plain push is rejected:

```sh
git push --force-with-lease origin core-patchset
```

Notes:

- `git pull --rebase origin core-patchset` is for a *contributor's* local copy
  of `core-patchset` after someone else force-pushed it. It does not bring in
  upstream changes; use `git rebase main` for that.
- Tag each rebased state (for example `core-v1.3-1`) so clients can pin an
  exact, immutable point: `git tag core-v1.3-1 && git push origin core-v1.3-1`.
- Do not force-push `main`.

## C. Using this as a submodule (clients)

### First time

```sh
git submodule add -b core-patchset https://github.com/JasonYao/florilegium vendor/florilegium
git commit -m "Add florilegium submodule"
```

The commit records one exact SHA, so the pin is stable until you update it.
To pin a tag instead:

```sh
git -C vendor/florilegium checkout core-v1.3-1
git add vendor/florilegium && git commit -m "Pin florilegium core-v1.3-1"
```

Point TeX at it (the package loads its `.lua` files by bare name):

```sh
export TEXINPUTS=vendor/florilegium//:
export LUAINPUTS=vendor/florilegium//:
```

### Cloning a client repo (yes, the clone step changes)

A plain `git clone` leaves the submodule directory empty. Either:

```sh
git clone --recurse-submodules <client-repo-url>
```

or, after a plain clone:

```sh
git submodule update --init --recursive
```

Update CI checkouts too (for GitHub Actions, `actions/checkout` with
`submodules: recursive`).

### Updating the pin

```sh
git submodule update --remote vendor/florilegium   # moves to latest core-patchset
git add vendor/florilegium
git commit -m "Update florilegium"
```

If the fork's history was rebased, `--remote` still works (it fetches and checks
out the new tip). Other clones then run
`git submodule update --init --recursive` after pulling the client repo.
Pinned SHAs that were rebased away stay available only while some ref or tag
reaches them, which is another reason to tag each rebased state.
