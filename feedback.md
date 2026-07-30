# Feedback on the Nox Developer Experience

Notes from building Quorum Veil — a confidential quorum-approved treasury —
against Nox on Ethereum Sepolia. Overall the core privacy model (encrypted
handles + ACL-gated decryption) is genuinely powerful and mapped cleanly
onto our use case once we understood it. Most of our friction was in
discoverability of the exact API surface, not the underlying design.

## What worked well

- The mental model — encrypt off-chain, get a handle + proof, verify
  on-chain with `Nox.fromExternal`, gate decryption with `Nox.allow` — is
  simple enough that we could build a real quorum-gated privacy flow
  (proposal amounts hidden until approval quorum is met) in a few days,
  including learning the toolchain from scratch.
- Ethereum Sepolia worked without any manual gateway/subgraph configuration
  once we got the JS SDK call shapes right. Deployment, encryption, and
  decryption all worked end-to-end on Sepolia.
- The Solidity side (`Nox.add`, `Nox.sub`, `allowThis`/`allow`) is a thin,
  readable layer over normal Solidity — it didn't feel like learning a new
  language.

## Friction points

**1. `nox-hardhat-starter` (named in the hackathon brief) doesn't exist.**
The actual repo under the `iExec-Nox` GitHub org is `nox-hardhat-plugin`,
and it's the plugin's own source (a pnpm monorepo), not a ready-to-clone
starter template with an example `contracts/` folder to build in. We ended
up scaffolding a fresh Hardhat project by hand and installing
`@iexec-nox/nox-protocol-contracts` as a dependency instead. A genuine,
minimal starter template (one deployable example contract + deploy script,
not the plugin's own source) would save real time here.

**2. The JS SDK's `encryptInput` signature wasn't discoverable from the
docs pages we found.** We initially guessed an object argument
(`{ value, applicationContract }`, then `{ value, solidityType,
applicationContract }`) based on runtime error messages, and only got the
correct call shape by opening `node_modules/@iexec-nox/handle/README.md`
directly:

```ts
const { handle, handleProof } = await handleClient.encryptInput(
  value,
  solidityType,
  applicationContract
);
```

It's positional, not an options object, and returns `handleProof` (not
`proof`, which is what our contract's parameter naming and initial
assumption led us to expect). This cost us several rounds of trial and
error that a single clear code sample on the public docs site (matching
what's actually in the package README) would have prevented.

**3. `decrypt()`'s return shape wasn't obvious either.** It returns an
object (`{ value, solidityType }`), not the raw decrypted value directly —
we initially logged `[object Object]` before realizing we needed `.value`.

**4. Docs currently say Ethereum Sepolia isn't fully auto-configured yet**
("the SDK aims to support the full SolidityType union... today it accepts
boolean/string/bigint" — and separately, a note that full Sepolia support
is "upcoming," with Arbitrum Sepolia as the interim default). In practice,
Ethereum Sepolia worked correctly for us with zero manual config. This
caused real hesitation, since our hackathon track requires deployment on
ETH Sepolia specifically — worth updating that note if it's now stale, since
it reads as a bigger blocker than it turned out to be.

**5. Package name itself required searching.** The hackathon's dev
resources list didn't make `@iexec-nox/handle` (the actual JS SDK package
name) easy to find on the first pass — we found it via a GitHub search
rather than a direct docs link.

## Suggestion

A single "cheat sheet" page with copy-pasteable, verified snippets for the
three or four most common calls (`encryptInput`, `decrypt`, a minimal
Hardhat contract import + compile command) — kept in sync with the actual
shipped package — would have cut our integration time by at least half a
day.
