# NeuraScribe controlled Textual fork

This checkout is the Textual revision NeuraScribe builds against. It is a
controlled fork of `whitneyland/textual`, which is itself a fork of the
upstream `gonzalezreal/textual` package.

| | |
|---|---|
| Upstream | https://github.com/gonzalezreal/textual |
| Crash-fix fork (our base) | https://github.com/whitneyland/textual |
| Base commit | `bd9fbee3d775483b56015918308068beaae6c3d3` ("Fix stale text position handling") |
| Our remote fork (origin) | https://github.tools.sap/I507459/swiftui-textual |
| Working branch | `neuronscribe/lazy-layout` |
| Local checkout | `/Volumes/Store2T/code/textual-neurascribe-fork` |
| Remotes | `origin` = our GHE fork, `upstream` = whitneyland/textual, `parent` = gonzalezreal/textual |

`bd9fbee` is kept as the base so the crash fix the app already relied on is
preserved; the perf patches in `UPSTREAM.md` are layered on top of it.

## How NeuraScribe consumes this checkout

The app references it through `XCLocalSwiftPackageReference` with
`relativePath = vendor/textual`, where `vendor/textual` is a **relative**
symlink to this sibling directory:

```
NeuraScribe/vendor/textual -> ../../textual-neurascribe-fork
```

The relative link works for any NeuraScribe checkout that sits next to this
directory on the same machine. A local package's SwiftPM identity is the
lowercased basename of its path, so keep this directory's basename stable
(`textual-neurascribe-fork`).

## Publishing back to github.com (one command)

This machine has no github.com credentials, so the fork currently lives on the
SAP GitHub Enterprise instance. To publish to github.com instead:

```bash
# 1. Fork whitneyland/textual on github.com (keeps the crash fix and the fork lineage)
# 2. Point a remote at it and push the working branch
git remote add github git@github.com:<you>/textual.git
git push -u github neuronscribe/lazy-layout
```

Then switch the app's `XCLocalSwiftPackageReference` back to an
`XCRemoteSwiftPackageReference` pointing at that URL and pin the patch commit
in `Package.resolved`.

## Portability limitation (read this before moving the checkout)

`vendor/textual` is a **relative** symlink, so it only resolves when this
directory sits two levels above the NeuraScribe `vendor` folder (i.e. as a
direct sibling of the NeuraScribe checkout). On another machine or in CI the
layout differs and the link may dangle, so the project will not resolve. The
intended migration is:

1. Push the patch commit to a reachable fork.
2. Replace the `XCLocalSwiftPackageReference` with a remote package reference
   to that fork (revision-pinned), and add a matching entry to
   `NeuraScribe.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Alternatively, check the fork out at the same relative location (a sibling
directory named `textual-neurascribe-fork` of the NeuraScribe checkout).

## ExFAT notes

This checkout lives on the ExFAT volume `/Volumes/Store2T`. ExFAT loses the
Unix executable bit, so git reports every file as `100755`; this clone sets
`core.fileMode=false` (and `core.autocrlf=false`) to keep `git status` clean.
AppleDouble `._*` sidecars are excluded via `.git/info/exclude`. Only build
products must stay on APFS — the source tree on ExFAT is fine.

## License

MIT, unchanged from upstream — see `LICENSE`.
