# ttyd-alpine

A small Docker image for [ttyd](https://github.com/tsl0922/ttyd) (share a terminal
over the web) with an SSH client, so the browser terminal can open an SSH session
to another host.

## Image

```
ghcr.io/chefcai/ttyd-alpine:latest
ghcr.io/chefcai/ttyd-alpine:<ttyd-version>   # e.g., 1.7.7
```

## What the Dockerfile does

```Dockerfile
FROM tsl0922/ttyd:alpine          # upstream image: alpine + static ttyd + bash + tini
RUN apk add --no-cache openssh-client
```

Typical use: `ttyd -p 7681 -W ssh <user>@<host>`. ttyd spawns `ssh` on a PTY
per browser session; the SSH server does the authentication.

## Runtime requirements

These are the things the container actually needs at run time. Anything not
listed here is incidental to the current base image.

| Requirement | Why | Provided today by |
|---|---|---|
| `ttyd` binary | the web terminal server | upstream `ttyd` release binary — **fully static** (musl), no shared-library deps |
| An SSH client | the command ttyd spawns | Alpine `openssh-client` (`/usr/bin/ssh`, dynamically linked: musl libc, `libcrypto.so.3`, `libz.so.1`) |
| A passwd/group entry for the running UID | `ssh` calls `getpwuid()` for the home dir and refuses to run without it | Alpine `/etc/passwd` (runs as `root` today) |
| A writable `$HOME/.ssh/` | `known_hosts`; lost when the container is recreated unless mounted | container layer (not persisted) |
| A PTY device (`/dev/pts`) | ttyd allocates one per session | Docker default |
| PID 1 that reaps children | each browser session forks `ssh` | `tini` (`ENTRYPOINT ["/sbin/tini","--"]` in the upstream image); `init: true` in compose also works |
| `/bin/sh` + `wget` | **only** for a `CMD-SHELL` healthcheck like `wget --spider http://127.0.0.1:7681/` | busybox |
| CA certificates, TLS libs | **not needed** — ttyd serves plain HTTP and TLS is terminated in front of it | — |
| `bash` | **not needed** for the `ssh` use case (the remote shell runs on the SSH server) | upstream image adds it |

## Smaller, non-Alpine option (not implemented)

Because `ttyd` is already static, the only dynamic dependency is the SSH client.
A static SSH client removes the need for a distro base entirely:

- **Base:** `gcr.io/distroless/static-debian12:nonroot` (≈2 MB; ships `/etc/passwd`
  with `nonroot` UID 65532 and home `/home/nonroot`, `/tmp`, CA certs, tzdata)
  or `scratch` plus a hand-written `/etc/passwd`.
- **SSH client:** a statically linked build, e.g. Dropbear's `dbclient`
  (≈0.3–0.5 MB static; supports password and key auth, `~/.ssh/known_hosts`) or
  OpenSSH `ssh` linked against static OpenSSL/zlib (≈3–5 MB). Build it in an
  `alpine` builder stage and `COPY` the binary in.
- **PID 1:** use `init: true` in compose (Docker's tini) instead of shipping tini.
- **Healthcheck:** distroless/scratch has no shell or `wget`. Either drop the
  compose healthcheck, switch to exec form with a static helper (e.g. a static
  busybox `wget`, ≈1 MB), or rely on the orchestrator's restart policy.
- **Non-root:** run as `nonroot` and mount a volume at `/home/nonroot/.ssh` so
  `known_hosts` survives recreation.

Expected size: ≈8–12 MB vs 22 MB today. Trade-offs: `dbclient` option names
differ slightly from OpenSSH (`-y` to accept host keys, `-i` for keys); and a
custom-built SSH client needs its own update cadence, whereas `openssh-client`
gets security fixes from Alpine automatically.

## Build pipeline notes

- The workflow reads the ttyd version from `tsl0922/ttyd:alpine` and skips the
  build if that version is already published. The base image and
  `openssh-client` are therefore **not** refreshed until ttyd itself releases.
- GitHub disables scheduled workflows after 60 days without repository
  activity; re-enable it under **Actions** if the daily run is needed.
