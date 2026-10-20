# Release channels: staging and production

One repository, two branches, two install names. A tester can keep the
production build and the staging build on the same machine at once, because
they install under different names and never overwrite each other.

| | Production | Staging |
|---|---|---|
| Branch | `production` | `main` |
| Tag shape | `v1.2.3` | `v1.2.3-stg.4` |
| GitHub release | normal | pre-release |
| Binary | `mdr` | `mdr-stg` |
| Homebrew | `brew install oxgenet/tap/mdr` | `brew install oxgenet/tap/mdr-stg` |
| Formula | `Formula/mdr.rb` | `Formula/mdr-stg.rb` |
| Windows | ZIP + MSI, `mdr.exe` | ZIP + MSI, `mdr-stg.exe` |
| Workflow | `release.yml` | `release-stg.yml` |

## The branch model

`main` is the integration branch and the source of staging builds. `production`
holds exactly what is released to users — fast-forwarding `production` to a
reviewed commit on `main` is the promotion step, and after it, `production`
always equals what is live.

```
feature branch ──PR──▶ main ──(tag v1.2.3-stg.N)──▶ staging build (mdr-stg)
                        │
                        └──(merge, when happy)──▶ production ──(tag v1.2.3)──▶ production build (mdr)
```

Nothing auto-releases on a plain branch push. A release is cut by pushing a
**tag**, which is what gives the build a version and a stable download URL. The
tag's suffix chooses the channel: a `-stg` tag is a pre-release and runs only
`release-stg.yml`; a plain `v1.2.3` tag runs only `release.yml`. `release.yml`
explicitly excludes `-stg`, `-rc` and `-beta` tags, so one tag never triggers
both.

## Cutting a staging build

```bash
git switch main
# ... merge the PRs you want to test ...
git tag v1.2.3-stg.1
git push origin v1.2.3-stg.1
```

Produces a GitHub pre-release with `mdr-stg` archives and MSI, and (when the tap
is enabled) updates `Formula/mdr-stg.rb`. Install it with:

```bash
brew install oxgenet/tap/mdr-stg      # macOS
mdr-stg file.md
```

Bump the `-stg.N` counter for each new staging build on the same version.

## Cutting a production build

```bash
git switch production
git merge --ff-only main               # promote the reviewed commit
git tag v1.2.3
git push origin production v1.2.3
```

Produces the full production release — `mdr` archives, MSI, `.deb`, `.rpm`,
`Mdr.app`/`.dmg`, and the `Formula/mdr.rb` update, plus the other package
managers that are enabled by repository variables.

## Why the two can coexist

- **Homebrew**: `mdr-stg.rb` installs a binary literally named `mdr-stg`, so it
  does not conflict with `mdr`. Both formulae can be installed together.
- **Windows MSI**: each channel has its own permanent `UpgradeCode` and its own
  PATH-component GUID in `wix/main.wxs`. Windows therefore treats them as two
  separate products: installing staging does not remove production, and each
  upgrades only its own earlier builds.
- **The binaries** are the same code built from different branch tips — staging
  from `main` (ahead), production from `production` (released). The difference
  is which commit, not a separate codebase.

## The Windows MSI

`wix/main.wxs` is one WiX 3 source shared by both channels; everything that
differs is passed as a `candle` define (binary name, product name, version,
source exe, and the two per-channel GUIDs). The workflow installs the WiX 3
toolset itself (`choco install wixtoolset`) rather than relying on a bundled
copy — current GitHub `windows-latest` images no longer ship one — and puts
`candle`/`light` on PATH. The MSI `ProductVersion` is plain `x.y.z`: the
`-stg.N` suffix is kept in the file name and download URL but dropped from that
field, which MSI requires to be numeric.

## Repository variables and secrets

The tap push is gated, exactly as the production flow already was:

- `vars.HOMEBREW_TAP_ENABLED` must be `true` for either channel to push a
  formula.
- `secrets.HOMEBREW_TAP_TOKEN` must grant write access to
  `oxgenet/homebrew-tap`.

Both channels write into the same tap repo, into `Formula/mdr.rb` and
`Formula/mdr-stg.rb` respectively.

## First-run validation

The MSI path has never run on CI yet (it is new here). On the first staging tag,
confirm on the run:

1. `choco install wixtoolset` succeeds and `candle`/`light` resolve on PATH.
2. `candle`/`light` compile `wix/main.wxs` without ICE errors.
3. The produced `.msi` installs on a clean Windows box, puts `mdr-stg` on PATH,
   and `mdr-stg --version` works.
4. Installing the production MSI afterwards leaves `mdr-stg` intact, and vice
   versa.

The quickest way to run all of this is to push a throwaway staging tag
(`v0.0.0-stg.1`), watch `release-stg.yml`, then delete the tag and its
pre-release. That exercises the real Windows build and MSI on a clean runner —
which is the only place the Windows binary can be built, since a dev machine
with Smart App Control cannot compile it at all.
