<p align="center">
  <img src="https://reseam.app/logo.svg" alt="Reseam logo" width="96">
</p>

<h1 align="center">Reseam CI</h1>

The image Reseam's repositories build and release in, published at `ghcr.io/reseam/ci`. It runs on any forge whose runner can pull a public image: GitHub, Forgejo, Codeberg.

It is Ubuntu 24.04 with:

- Java 17 and 21, Node.js, Bun, `just`
- The Android SDK platforms 35, 36 and 37, build-tools 35 and 36, and the NDK
- Rust with the Android, Windows and WASI targets, BoltFFI, llvm-mingw and a Windows JDK for the Windows CLI, and the WASI SDK
- The Linux and Windows packaging tools: `dpkg`, `rpm`, `makepkg`, NSIS

Cargo, Gradle, Bun and npm keep their downloads under `/cache`. Mount a volume there and they carry over between runs.

Versions are pinned as `ARG`s in the [Dockerfile](Dockerfile). Jobs run as `ci` (uid 1001, the uid of GitHub's runner user), with passwordless `sudo`. The SDK is read-only, so a build that needs a package the image lacks fails instead of downloading it.

## How repositories use it

Each repository has a `justfile` and one workflow, `.github/workflows/ci.yml`, that runs `just check` and then `just release <tag>` in this image on `v*` tags. `just release` publishes with [`reseam release`](https://reseam.app/docs/cli/release/).

On Forgejo, the organization variable `RUNNER` names the runner label. GitHub falls back to `ubuntu-latest`.

The workflow mounts the volume `reseam-ci` at `/cache` and builds Rust into `/cache/target`. A Forgejo runner mounts it only when its `container.valid_volumes` lists `reseam-ci`. Where the volume does not persist, the workflow falls back to `actions/cache` for the downloads.

## Publish

```bash
docker build -t ghcr.io/reseam/ci:<yyyy.mm.dd> .
docker push ghcr.io/reseam/ci:<yyyy.mm.dd>
```

Then point each repository's `ci.yml` at the new tag.

## License

AGPL-3.0-or-later, with additional terms under section 7 in [NOTICE](NOTICE).
