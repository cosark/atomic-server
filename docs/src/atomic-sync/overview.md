{{#title Atomic Sync overview: every device holds a full copy}}
# Atomic Sync overview

Most apps keep your data on somebody else's server, and the app on your phone is just a window onto it.
That works until the connection drops, the company changes its mind, or two people edit the same thing at the same time.
Atomic Sync takes the opposite approach: every device that uses a [Drive](../identifiers.md#drive-identity) keeps a full local copy and reads and writes it directly.
Sync runs in the background and passes changes between those copies, so the copies stay in agreement.

## The idea in five points

1. **Every device has a full local copy.** The app reads and writes the local store, so it keeps working offline. See [local-first](../local-first.md).
2. **Edits are signed commits.** A change becomes a [Commit](../commits/intro.md): a [Loro](https://loro.dev) CRDT update plus an Ed25519 signature from the [Agent](../agents.md) that made it. Anyone can check who changed what.
3. **Copies merge automatically.** Each Resource is a Loro document, so edits made at the same time on different devices merge without a coordinator. Merging does _not_ check your business rules, though. Your application decides when a merged result needs review.
4. **Every receiving node checks permissions.** A node verifies the signature and the signer's write right before it applies a change, and it only sends a peer what that peer's Agent may read. See [permissions and identity](permissions-and-identity.md).
5. **A server is just another peer.** An [AtomicServer](../atomic-server.md) runs the same sync engine as a phone or a browser tab. It's usually the one that stays online, but it doesn't own anything. See [remote peers](remote-peers.md).

## What happens to an edit

You change a Resource on your device, and the change lands in the local store at once.
It is signed, and put in an outbox.
When a peer is reachable, the device first compares what each side has, using [version vectors](drive-reconciliation.md), and then exchanges only what differs.
While the link stays open, later edits are pushed as they happen.
If you're offline, the outbox keeps your edits, even across a restart, and sends them when a peer comes back.

[Atomic Sync](../sync.md) walks through this in more detail.

## Where to read next

| If you want to | Read |
| --- | --- |
| Choose how devices connect | [Transports](transports.md) |
| Understand what two devices exchange | [Drive reconciliation](drive-reconciliation.md) |
| Know who may read and write during sync | [Permissions and identity](permissions-and-identity.md) |
| Keep a Drive available while your devices are off | [Remote peers](remote-peers.md) |
| Build an app on the engine | [Building on the sync engine](building-on-the-sync-engine.md) |
| Implement a client or peer | [Wire protocol](../websockets.md) |

The product-level pitch, and what you do not have to build yourself, is on [Local-first Sync Engine](../sync-engine.md).
