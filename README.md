# STFU protected CI (public, source-free)

This public repository provides only a generic automation harness. The source and game data of **Star Trek: The Next Generation — A Final Unity** remain in the original private repository and private storage. Do not commit any translated game code, original ISO, media ZIP, signed URLs, private keys, or plaintext build artifacts here.

## Status
- Public standard GitHub runner probe #3 passed on 2026-11-18 (run 44220738856).
- Actual private STFU build is gated by repository secret `STFU_PRIVATE_READ_TOKEN`. No token has been configured or verified in this workflow yet.
- Strict stage43 NDK compilation and Android APK remain unverified after the GitHub billing interruption.
- PR #1 is a harmless secret-free runner probe, and the private STFU PR #2 remains unmerged.

## One-time setup (owner only)
1. In GitHub **Settings → Developer settings → Personal access tokens → Fine-grained tokens**, create a fine-grained token with resource owner `kairushinjuu`. Select **Only select repositories → 2004s**.
2. Set repository permission **Contents: Read-only** (Metadata is implicit), short expiration. Do not give Actions, Administration, or write privileges. A token with contents read is sufficient for private checkout.
3. In this **public harness repository** go to **Settings → Secrets and variables → Actions → New repository secret**. Name `STFU_PRIVATE_READ_TOKEN`. Paste the token there, **never in public issues, commits, logs, or chat**.
4. Trigger the trusted workflow by asking ChatGPT to update `ci/build-request.txt` on `main`, or use **Actions → STFU protected ARM64 NDK build → Run workflow**.
5. The workflow packages APK and diagnostics only inside `stfu-stage43-protected.age`, encrypted for the SSH-ed25519 public recipient stored at `ci/age_artifact_key.pub`. The corresponding **private decryption key** is stored only in the private STFU-Android Google Drive folder. The public artifact must NEVER include unencrypted `*.apk`, game source or logs.

## Security
Only a trusted `push` to `main` or owner-issued manual `workflow_dispatch` runs the private build. There is **no pull_request or pull_request_target trigger** for the token-bearing workflow. Public PRs cannot run the private build. No private source is copied into git or publicly uploaded artifacts. The temporary hosted worker sees private code during compilation; third-party toolchains and dependencies still form part of the trusted execution environment. Rotate the fine-grained token when done.

The public repository's ordinary GitHub `GITHUB_TOKEN` cannot read private STFU source; the user-created narrowly scoped secret is mandatory. A failed/pending credit card on the owner account might still block other workflows; the secret-free public probe proved that a standard public hosted runner is currently usable.
