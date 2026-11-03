# Updating this fork

Branches in this fork:

- `main`: a clean mirror of the upstream's `main`. No local commits.
- `core-patchset`: our patches, updated by merging `main`. Clients pin this branch or
  one of its version tags.

Remotes: `origin` is this fork; `upstream` is the original project
(https://github.com/kevinraymond/florilegium).

## [This forked repo] A. Keep `main` up to date with the upstream

One-time setup:

```sh
git remote add upstream https://github.com/kevinraymond/florilegium.git
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

## [This forked repo] B. Merge upstream changes into the patchset

After `main` is updated:

```sh
git checkout core-patchset
git merge --no-ff main
# resolve conflicts, then: git add <files> && git commit
```

Check the result (`tools/versioncheck.sh`, `make`, `tools/svgcheck.sh texlua`),
then publish the merge commit:

```sh
git push origin core-patchset
```

Each untagged commit pushed to `core-patchset` is tagged automatically with the next
`YYYY.M.P` version for the current UTC year and month (for example,
`2026.8.3` is the third tag created in August 2026). The patch number starts
at 1 each month and increments from the existing tags. The workflow tags the
branch tip; no `VERSION` file or manual tag command is needed. These plain
SemVer tags are separate from the upstream package's `v*` release tags.

- Merges preserve earlier commit IDs, so existing submodule pins remain valid.
- Do not rewrite or force-push either shared branch, and do not move or delete
  published version tags.

## [Client repo] Using this as a submodule

### First time

```sh
git submodule add -b core-patchset https://github.com/JasonYao/florilegium vendor/florilegium
git commit -m "Add florilegium submodule"
```

The client commit records one exact SHA, so the pin is stable until you update
it. To pin an automatically created version tag instead:

```sh
git -C vendor/florilegium fetch --tags
git -C vendor/florilegium checkout 2026.8.3
git add vendor/florilegium && git commit -m "Pin florilegium 2026.8.3"
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

To update to a specific version tag instead, fetch tags inside the submodule,
check out the desired `YYYY.M.P` tag, then commit the changed submodule pin in
the client repo. Other clones run `git submodule update --init --recursive`
after pulling the client repo.
