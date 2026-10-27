{{#title Atomic Sync transports: WebSocket, Iroh and WebRTC}}
# Transports

Your devices live in very different places.
A browser tab can't accept connections, a phone moves between networks, and a server sits at a fixed address.
No single way of connecting works for all of them, so Atomic Sync is one protocol that runs over several transports.
The transport only decides how two devices reach each other. The frames, the signature checks and the permission checks are the same on all of them.

| Transport | Connects | Address you need |
| --- | --- | --- |
| WebSocket | A client (browser, CLI, app) to an AtomicServer | The server's URL |
| Iroh (QUIC) | Two native nodes running `atomic_lib`, for example a phone and a laptop or a server | The other node's id, usually from a QR code |
| WebRTC | Browser tabs, up to eight (an implementation limit) | A peer link made on the Sync page |
| HTTP `POST /commit` | Any client to an AtomicServer | The server's URL |

## WebSocket

This is what the web app uses by default.
The client opens `/ws` on an AtomicServer, proves its Agent with an `AUTH` frame, reconciles each Drive and then subscribes to live updates.
It needs a server that stays reachable, but that server can be small and self-hosted. See [remote peers](remote-peers.md).
Details: [Wire protocol](../websockets.md#overview-and-transports).

## Iroh peer to peer

If you have two native devices, you shouldn't need a server to sync them.
[Iroh](https://iroh.computer) opens QUIC connections between devices, directly when it can and through a relay when it can't.
Every node has a persistent node id, written `atomic:node:<id>`. The older spelling `did:ad:node:<id>` is still accepted.
To pair two devices, one shows its node id as a QR code and the other scans it, then asks its own node to sync a Drive with that id.
An AtomicServer starts Iroh on boot and logs its node id (`Iroh transport ready ... Connect with: atomic:node:...`).
A person with write rights on a Drive can also make a server dial a node with `POST /iroh-sync`, with the body `{"nodeId": "...", "drive": "..."}`.

A node id says _where_ to connect. It does not grant any access. See [permissions and identity](permissions-and-identity.md).
A browser tab can't accept incoming connections, so it can't be dialed over Iroh.

Servers can also announce which Drives they hold through the pkarr relay network, so a client that only knows a Drive's identifier can find a node to dial. See [resolution](../identifiers.md#resolution).

## WebRTC between browsers

Two browser tabs on two machines can't reach each other on their own.
With WebRTC they can sync through an encrypted data channel, with no server holding the data.
A small signaling service introduces the tabs and never sees Drive data.
Some networks also need a TURN relay, and everyone must have the app open to exchange changes. See [browser peer sync](../browser-peer-sync.md).

A mesh transport over [Reticulum](https://reticulum.network/) is planned but not built.

## HTTP commits

A client can send a signed commit with `POST /commit`.
This is the fallback when no socket is open, and a simple way for scripts to write. It gives no live updates.

## Which one to use

| Situation | Use |
| --- | --- |
| A web app with a server you run | WebSocket, with local persistence in the browser |
| Phones or desktops that should sync without a server | Iroh, paired with a QR code |
| A mix of browsers and native apps | A shared AtomicServer. Browsers cannot speak Iroh. |
| Browsers sharing without any server, while all are open | WebRTC |
| A script or integration that writes data | HTTP `POST /commit` |

Most setups combine them: WebSocket to a server for reach and availability, Iroh for direct device-to-device sync.
Be honest with yourself about one limit, though.
None of the peer-to-peer transports keeps data available when every device that holds it is off. For that you need an always-on node.
The [design decisions page](../local-first-guide/7-design-decisions.md) covers these choices in more depth.
