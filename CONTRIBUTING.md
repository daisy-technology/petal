# Contributing to Petal

## Branches

| Branch | What it holds |
|---|---|
| `main` | What's released. The website deploys from here. |
| `dev` | Finished work waiting for the next release. |
| `feat/<issue>-<slug>` | One change, tied to one issue, for example `feat/2-rename-desktops`. Use `fix/` for bug fixes. |

## Making a change

1. Open an issue first, or pick one that's already open.
2. Branch off `dev`: `git switch dev && git pull && git switch -c feat/<issue>-<slug>`.
3. Run `swift test` before you push. Behavior that can be tested without a running Mac belongs in `PetalCore` with a test next to it.
4. Open a pull request into `dev` titled `feat: <issue>-<what it does>`. Start the description with `Closes #<issue>`.
5. CI runs the tests and builds a universal `Petal.zip`, which you can download from the run page to try the change. A pull request needs green CI before it merges.

Keep commits small, and write their messages in the imperative ("Add color edge", not "Added color edge").

## Releasing

1. Open a pull request from `dev` into `main` and merge it once CI passes.
2. Tag the merge commit and push the tag:

   ```sh
   git switch main && git pull
   git tag v0.2.0
   git push origin v0.2.0
   ```

3. The Release workflow runs the tests, builds `Petal.zip`, and publishes a GitHub release with the zip, its SHA-256 and generated notes. The download button on the website always points at the latest release.

Changes under `docs/` that land on `main` redeploy the website automatically.
