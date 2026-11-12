# Server design (DP3)

Network Architect, 12 Nov 2026. Hosting figures were read that day from the
pages cited in section 6.

## 1. The protocol today

MQTT 3.1.1 over WSS, QoS 0, hand-rolled in `online.gd`. Each client joins three
public brokers (EMQX, HiveMQ, Mosquitto) at once, publishes to all and merges
what arrives.

| Topic | Payload | Rate |
|---|---|---|
| `ashgrave/w1/p/<id>` | state `x z yw cl eq up w l d zone tw n q` | 0.3 s moving, 1.5 s idle, 3 s in the tower; dropped after 9 s silence |
| `ashgrave/w1/c/<id>` | direct message `k from n mid` + body | per event |

Kinds: handshake `challenge`, `attack` (forced, inside the zone), `accept`,
`decline`, `busy`, carrying `card {hp, cl, cv}`; duel `atk {dir, dmg, x}`,
`res {o, hp, rip, po, pf}`, `pst`, `turn`, `ping` (3 s), `dead {gold}`. The
attacker gets three swings; the defender plays the windup locally and reports
the outcome. 14 s of silence is a win.

**Trust: everything.** The id is a 31-bit random number, visible in the topic;
`from` is a payload field; each client reports its own position, stats, damage,
health and outcome.

- **Gold minting.** The receiver adds `dead.gold` to its gold unchecked, so two
  tabs mint without limit.
- **Forgery.** Anyone can publish as any id, inject `res` or `dead` into a live
  duel, send any `dmg`, always answer `dodged`, or quit before `dead` to keep
  the stake.
- **No privacy, no persistence.** Any subscriber to `ashgrave/w1/#` reads
  everything, and brokers store nothing.
- **Split worlds, outages.** Players with no broker in common never meet, and
  these are test brokers with no service promise.

## 2. Requirements

Scale assumed: up to 30 concurrent players, 1,000 registered, one world; hard
ceiling 200 sockets.

| # | Requirement | Priority |
|---|---|---|
| R1 | Durable identity that cannot be impersonated | must |
| R2 | Server-owned gold, duel results and stakes | must |
| R3 | Deck and RNG held by the server; private cards | must |
| R4 | Transactional persistence that survives restarts | must |
| R5 | Resume within 2 s after a tab reload; offline play still works | must |
| R6 | Old builds coexist or are told to reload | must |
| R7 | Free hosting, deployable from Windows, little upkeep | must |
| R8 | Chat, parties, mute and ban | should |
| R9 | Trading as atomic swaps of server-owned items | should |
| R10 | Shared foes and resources; movement and yield checks | should |
| R11 | Clans, land, bases, timed sieges | later (P7) |
| R12 | Server-carried presence with interest management | later |

## 3. Options

| | (a) Godot headless | (b) WebSocket server + database | (c) Relays, optional signer | (d) Hybrid: authoritative "Hall" + relays for positions |
|---|---|---|---|---|
| Authoritative | Everything | Everything | Nothing; a signer vouches for identity only | Identity, gold, duel results, casino, trades, land. Positions audited, not owned |
| Persistence | Hand-built files on a volume | Postgres | None | Transactional SQLite inside the service |
| Casino fairness | Strong; `casino_core` runs unchanged | Strong; rules ported | Not achievable | Strong; rules ported |
| Anti-cheat | Strongest; could simulate | Strong | Weak | Strong where value moves |
| Duel latency | One hop, one region | One hop, one region | Broker hop, unmanaged | One hop through the host's edge |
| Cost today | From $2.19 a month on Fly; free only on a legacy Fly organisation | Fly machine plus Supabase free, which pauses after a week idle | $0 | $0 |
| Ops burden | High: container, engine binary, volume, backups | Medium: two services | None | Low: one deploy command, no OS, no sleep |
| GDScript reuse | High for `casino_core` and tables; low for duels (rules fused with visuals) | None; tables exported | All | Tables exported; casino rules ported |
| Risk | Pricing; untested memory fit; hand-written socket server on the open internet | Two free tiers to keep alive | Cheating open; later features blocked | Host lock-in; quota exhaustible by abuse; two copies of casino rules |

**Why (d).** It alone is free today, never sleeps and needs no server upkeep.
Its price: `casino_core` must be ported to TypeScript and kept identical. I
judge that cheaper than running a VM: the module is pure and the game can print
golden vectors for the port to replay. Positions stay on relays
because a moving player sends about 12,000 of them an hour against about 720
checkpoints (my arithmetic), and they are worth nothing to
a cheat once audited. If the owner's Fly organisation is a legacy one, (a)
becomes free too and is the honest runner-up.

## 4. Recommendation: (d), the Hall

**Components.** Game client → (1) public relays, positions only, unchanged
format; (2) one WSS socket to the Hall. The Hall is a Cloudflare Worker that
hands the socket to **one** SQLite-backed Durable Object holding the whole
world: sockets (hibernation API), tables, duels, ledger. One object makes every
trade and pot a single transaction and caps billed duration. Rules live in
plain TypeScript modules, so the same code runs under Node. A static
`version.json` on GitHub Pages gives `build`, `min_build`, `hall_url` and
`relays`; clients poll it every 5 minutes.

**Protocol.** JSON text frames:
`{"v":1,"t":"duel.atk","i":17,"d":{…}}`. `v` is the protocol version, `t` a
namespaced type, `i` the sender's sequence number (duplicates dropped). The
server stamps the sender; clients never send `from`. It speaks versions N and
N-1; unknown fields are ignored. First frame is `hello {build, hid+tok | key}`; the reply is
`welcome {hid, tok, roster, sheet, resume}` or `reject {upgrade|banned|full}`.
Credentials travel in the frame, never the URL.

**Identity.** No accounts. The client makes a 32-byte secret with the browser's
crypto, keeps it in the save, and sends it once; the server stores its hash and
issues the player id (`hid`) and a 24-hour token. A new socket for the same
`hid` evicts the old one, so tab reloads are cheap. Display names are unique.
The secret, shown as a recovery code, moves a character between devices;
impersonation needs it. Relay ghosts are drawn only for ids in the server
roster, with name and gear from the server; a forged relay position can still
misplace a ghost, which is cosmetic.

**Authority, in order:** identity, names, chat → gold ledger and duel results →
casino → character sheet, inventory, trades, shared nodes → land. Client-run for good: movement (speed-checked from a position checkpoint every 5 s and on every
position-dependent action), solo fights and tower runs (yields capped from
exported tables), and the defence timing game.

**Duels.** Same kinds as today, sent to the Hall and relayed after checks.
*Validated:* proximity and zone at the handshake; whose turn; three swings a
turn, at least 1 s apart; `dmg` within the attacker's sheet; executions only
inside a `pst` window; exactly one `res` per `atk`, ruled a hit after 4 s.
*Owned by the server:* both health totals, the result, the stake transfer and
the record. *Simulated on the defender's phone:* dodge, block and parry timing.
The windup starts on receipt, so latency delays only the attacker's feedback
and nothing rolls back. Parry rates are logged. A silent player has 20 s to
resume, then forfeits.

**Casino.** The Hall shuffles with the platform's secure RNG from a per-hand
seed, sends each seat only its own cards, and reveals board cards as dealt. The
deck and seed never leave the server. A hash of the seed is published before
the hand; the seed is revealed afterwards for blackjack and roulette, and only
logged for poker, where it would expose folded hands. Buy-ins move gold into
escrow. Collusion by voice cannot be prevented.

**Land and sieges.** Holdings, structures and sieges are rows. Windows open and
close by alarm and are re-derived from timestamps on every read. Siege scores
come from refereed duels inside the window; the schema fits every DP4 option.

| Table | Holds |
|---|---|
| `player`, `session` | `hid`, secret hash, name, flags; tokens |
| `sheet`, `item` | gold, level, gear, record; owned items |
| `ledger` | append-only gold movements with reason and reference |
| `duel` | pair, zone, stake, live state, result |
| `seat_table`, `hand_log` | seats, escrow, state; commitment, seed, events |
| `trade` | two offers, confirmations, state |
| `clan`, `member`, `holding`, `structure`, `siege` | P7 |
| `node` | shared foe or resource state |
| `audit` | flags, bans, admin actions |

**Limits.** Per socket 10 messages a second, burst 40. Chat 5 per
10 s. Frames at most 4 KB. Four sockets per IP, one per `hid`, five new
identities per IP a day. Amounts are non-negative integers within balance. The
Hall meters itself: at 80% of the daily quota it sheds chat; at 95% it stops
new hands and clients drop to offline.

## 5. Migration

| Phase | Ships | Old builds |
|---|---|---|
| 0 | No server. `version.json` poller and reload banner; build number in state; `?hall=` override; clamp accepted `dead.gold` to 0–200 | Unaffected |
| 1 | Hall: identity, roster, names, chat | Seen as before; no chat |
| 2 | Refereed duels, gold ledger, record | Duel new builds as "classic", no stake |
| 3 | Online blackjack, roulette, poker | Offline tables only |
| 4 | Sheet, inventory, trades, parties, shared nodes | Cannot trade |
| 5 | Clans, land, sieges | No access |
| 6 | Optional: positions through the Hall on `w2`; relays retired | See an empty `w1` |

Builds before Phase 0 have no poller; they stay visible and duel-able until the
tab reloads. Later, raising `min_build` shows older clients a reload banner.

## 6. Costs, limits, fallback

| Host | Finding | Source (read 12 Nov 2026) |
|---|---|---|
| Cloudflare Durable Objects, Free | 100,000 requests and 13,000 GB-s a day; 20 incoming socket messages count as one request; 100,000 rows written a day; 5 GB; SQLite only; over a limit, operations fail until 00:00 UTC; hibernating sockets are not billed. One always-awake object uses about 11,060 GB-s (my arithmetic at the stated 128 MB) | https://developers.cloudflare.com/durable-objects/platform/pricing |
| Cloudflare Workers | Free: 10 ms CPU per HTTP request. Paid: $5 a month minimum | https://developers.cloudflare.com/workers/platform/limits/ and https://developers.cloudflare.com/workers/platform/pricing/ |
| Fly.io | No free tier for new organisations; 256 MB machine $2.19 a month | https://docs.fly.io/about/pricing |
| Fly.io legacy | Three 256 MB machines and 3 GB free for pre-sunset organisations | https://docs.fly.io/about/discontinued-plans |
| Supabase Free | 500 MB; paused after 1 week of inactivity | https://supabase.com/pricing |
| HiveMQ broker | For temporary testing, not production data | https://www.hivemq.com/public-mqtt-broker/ |

**Unverified:** the owner's Fly and Supabase accounts; whether
Cloudflare Free needs a card; the hibernation idle timeout; whether the 10 ms
limit applies inside Durable Objects; free per-object storage (the limits page
says both 1 GB and 10 GB); whether Fly waives bills under $5 (its trial page
says so, its pricing page does not); the 256 MB fit of Godot headless; EMQX and
Mosquitto terms; latency figures, which are targets.

**Fallback.** Workers Paid at $5, or the same modules under Node with SQLite on
a Fly machine. `hall_url` in `version.json` moves live clients without a
reload; a weekly JSON export keeps the data portable.

## 7. Testing

- **Soak** (local, never production): 50 Node bots for 30 minutes walking,
  duelling and playing poker, half the sockets killed every 30 s. Assert gold
  conservation, one `res` per `atk`, no duplicated items, resume under 2 s,
  relay delay p95 under 150 ms, and a day's quota use. The `pvp_a`/`pvp_b`
  bots run against the local Hall.
- **Exploit scripts:** forged sender; replayed sequence numbers; `dead` with
  huge gold; out-of-turn, too-fast or over-damage `atk`; withheld `res`;
  disconnect at 1 health; the same gold spent on two sockets at once; negative
  and fractional amounts; item swapped at trade confirm; betting over stack;
  asking for another seat's cards; registration flood; teleport gathering; distant land claims; sieges outside the window; oversized
  frames; quota-burning reconnect loops.

## 8. Owner decisions

1. **Stack.** (d) Hall on Cloudflare plus relays: free, low upkeep, casino
   rules ported once. (a) Godot headless on Fly: one copy of the rules, from
   $2.19 a month unless your Fly organisation is legacy, most upkeep.
   (c) Stay on relays: free; no online casino, trading or land.
   **Recommend (d).**
2. **Accounts.** Create a free Cloudflare account and report whether it asked
   for a card; or check the Fly dashboard for a legacy plan; or neither yet.
   Supabase is not needed. **Recommend both checks.**
3. **Gold when the ledger starts.** Adopt local gold once, capped at 5,000:
   bounded. Start everyone at zero: cleanest, annoys players. Adopt uncapped:
   minted gold survives. **Recommend the cap.**
4. **Disconnect in a staked duel.** 20 s to resume, then forfeit: closes the
   quit exploit, sometimes punishes a killed tab. No stake moves: exploitable.
   Instant forfeit: harsh on iPhone. **Recommend 20 s.**
5. **Spend ceiling.** Strictly free: online features pause when a quota runs
   out. Pre-approve $5 a month once use passes 70% of quota. **Recommend
   strictly free until soak numbers exist.**
