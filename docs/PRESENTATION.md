# Presentation Notes

**DSA612S — Assignment 1 · Group defence**
Distributed Library and Resource Management System (REST) &
Rental Accommodation System (gRPC)

> Suggested running time: **20 minutes presentation + 10 minutes questions.**
> Timings per slide are in the margin. Everything in *italics* is a speaker
> note, not something to put on the slide.

---

## Contents

- [Before you start](#before-you-start)
- [Slide 1 — Title](#slide-1--title-30-s)
- [Slide 2 — The two problems](#slide-2--the-two-problems-90-s)
- [Slide 3 — Why Ballerina](#slide-3--why-ballerina-2-min)
- [Slide 4 — Repository layout](#slide-4--repository-layout-60-s)
- [Slide 5 — Q1 architecture](#slide-5--q1-architecture-2-min)
- [Slide 6 — Q1 domain model](#slide-6--q1-domain-model-90-s)
- [Slide 7 — Q1 storage and the unique key](#slide-7--q1-storage-and-the-unique-key-90-s)
- [Slide 8 — Q1 error handling](#slide-8--q1-error-handling-2-min)
- [Slide 9 — Q1 endpoint tour](#slide-9--q1-endpoint-tour-90-s)
- [Slide 10 — Q1 live demo](#slide-10--q1-live-demo-3-min)
- [Slide 11 — Bonus web dashboard](#slide-11--bonus-web-dashboard-90-s)
- [Slide 12 — Q2 the contract](#slide-12--q2-the-contract-2-min)
- [Slide 13 — gRPC streaming explained](#slide-13--grpc-streaming-explained-3-min)
- [Slide 14 — Q2 booking rules](#slide-14--q2-booking-rules-2-min)
- [Slide 15 — Concurrency](#slide-15--concurrency-2-min)
- [Slide 16 — Q2 live demo](#slide-16--q2-live-demo-3-min)
- [Slide 17 — REST vs gRPC](#slide-17--rest-vs-grpc-90-s)
- [Slide 18 — What we would do next](#slide-18--what-we-would-do-next-60-s)
- [Anticipated questions](#anticipated-questions)
- [Demo checklist](#demo-checklist)
- [Speaking-role split](#speaking-role-split)

---

## Before you start

*Ten minutes before the session:*

1. Open **four** terminals, pre-`cd`'d:
   `Q1/service`, `Q1/client`, `Q2/server`, `Q2/client`.
2. Run both servers once and leave them running — the first build downloads
   standard-library modules and you do not want that happening on stage.
3. Open the web dashboard in a browser tab, already in **dark mode**.
4. Increase the terminal font size to at least 16 pt.
5. Have `docs/API_DOCUMENTATION.md` open in a fifth tab for questions.

---

## Slide 1 — Title *(30 s)*

> **DSA612S Assignment 1**
> Two distributed systems, two communication styles
> *Matatias Nghihangwa 225156237 · Eliaser Angula 225053241 ·
> Pandera Katjipuka 225123851 · Monika Shalauda 222075449 ·
> Risto Sakeus 225042428 · Alanray Miller 223003018 ·
> Kavara Edward 225017288 · Haufiku Frans 222127147*

*Say:* "We built two complete distributed systems in Ballerina. The first is a
REST library and resource management system for the Ministry of Higher
Education. The second is a gRPC rental accommodation platform for the Ministry
of Tourism. The interesting part is not that we built two systems — it is that
they solve deliberately different communication problems, and we can show you
why each protocol was the right choice."

---

## Slide 2 — The two problems *(90 s)*

| | Question 1 | Question 2 |
|---|---|---|
| **Client** | Ministry of Higher Education | Ministry of Tourism |
| **Domain** | Books, laptops, labs, meeting rooms | Short-term rental listings |
| **Key challenge** | One model for three very different resource kinds | Booking conflicts under concurrency |
| **Protocol** | REST over HTTP/1.1 | gRPC over HTTP/2 |
| **Consumers** | CLI client + browser dashboard | CLI client |

*Say:* "Question 1's hard part is modelling. A book, a loan laptop and a
meeting room are physically nothing alike, yet all three have to live in one
catalogue with one unique tag, one lifecycle and one maintenance schedule.

Question 2's hard part is correctness under concurrency. Two guests can ask for
the same beach cottage for the same week at the same instant, and exactly one
of them must win."

---

## Slide 3 — Why Ballerina *(2 min)*

> Network concepts are **language keywords**, not library types.

```ballerina
service / on new http:Listener(8080) {
    resource function get assets/[string assetTag]() returns Asset|ApiError {
        …
    }
}
```

*Say:* "In most languages a REST endpoint is a framework annotation on an
ordinary method. In Ballerina, `service`, `resource function` and `listener`
are keywords. The compiler knows this is an HTTP resource. That is why
`bal openapi` can generate an exact OpenAPI contract from the source, with no
extra metadata."

**Five concrete reasons, in the order we would defend them:**

1. **`isolated` gives compiler-checked concurrency.** We can *prove* that
   shared state is only touched under a lock. Very few languages offer this.
2. **The type system models the wire.** A resource function returns
   `Asset|BadRequestResponse|NotFoundResponse|ConflictResponse|InternalErrorResponse`.
   Every possible HTTP outcome is part of the signature.
3. **Errors are values, not exceptions.** `check` propagates them, and
   `distinct` error types let the transport layer dispatch a status code by
   *type* rather than by matching strings.
4. **First-class gRPC.** `bal grpc` generates the stub, and both streaming
   styles map onto native Ballerina `stream` values.
5. **Tables and query expressions are built in.**
   `from … where … order by … select` over an in-memory table — no ORM, no
   third-party collection library.

*If asked "why not Node/Spring?":* "Both would work. Spring would need
annotations plus a `synchronized` discipline nobody can verify; Node would need
a framework plus TypeScript plus a protobuf library. Ballerina gave us the
network primitives, the concurrency proof and the gRPC toolchain in one
distribution."

---

## Slide 4 — Repository layout *(60 s)*

```
DSA612S-Assignment/
├── Question1/  service/ · client/ · web/
├── Question2/  proto/ · server/ · client/
└── docs/       API_DOCUMENTATION.md · PRESENTATION.md
```

*Say:* "Four **independent** Ballerina packages, each with its own
`Ballerina.toml`. That is deliberate: because the client cannot import the
server's types, it is forced to talk over the wire. It is genuinely
inter-process communication, not two halves of one program."

---

## Slide 5 — Q1 architecture *(2 min)*

```
main.bal      TRANSPORT   24 resource functions · CORS · status mapping
services.bal  BUSINESS    domain rules · id generation · read models
database.bal  PERSISTENCE isolated table<Asset> key(assetTag)
util.bal      CROSS-CUT   errors · calendar maths · validation
```

*Say:* "Four files, four responsibilities, one rule that enforces the whole
thing: **`services.bal` does not import `ballerina/http`.** Not once. The
business layer has no idea it is being driven over REST.

That has a practical payoff. When we added the gRPC project we already knew the
pattern would hold, and if the ministry asked for a GraphQL front end tomorrow
we would write a new transport file and reuse the business layer unchanged."

*Point at the diagram:* "Data flows down, errors flow up. A resource function
does exactly three things: call the business layer, wrap a success, delegate a
failure."

---

## Slide 6 — Q1 domain model *(90 s)*

```
Asset (assetTag ← unique key)
 ├── Component[]   compId
 ├── Schedule[]    scheduleId · type · dueDate  ─────▶ overdue report
 └── WorkOrder[]   orderId · status
      └── Task[]   taskId · completed
```

*Say:* "`Asset` is the aggregate root. Everything else is owned by it and
identified only within it — `compId` C101 can exist on two different assets
without clashing, because it is scoped to its parent.

The status enum unifies the three resource kinds. A book or a laptop goes to
`LOANED_OUT`; a lab or a meeting room goes to `OCCUPIED`. Same endpoint, one
boolean in the request body decides which."

*If asked about the `LoanRecord`:* "The asset payload in the brief has no
borrower field, so rather than pollute the model we keep a separate audit
trail keyed by `loanId`. It gives us loan history for free, which the dashboard
uses."

---

## Slide 7 — Q1 storage and the unique key *(90 s)*

```ballerina
isolated table<Asset> key(assetTag) assetTable = table [];
```

*Say:* "One line gives us three things: O(1) primary-key lookup, uniqueness
enforced by the **runtime** rather than by our code, and first-class query
syntax."

```ballerina
Asset[] matches = from Asset a in assetTable
                  where a.institution.trim().toLowerAscii() == needle
                  order by a.assetTag ascending
                  select a;
```

*Say:* "That is SQL-shaped code over an in-memory structure, with full type
checking. `assetTag` is declared `readonly` in the record — Ballerina requires
key fields to be immutable, which is exactly the guarantee you want from a
primary key."

*Have ready:* "In Question 2 we used `map` instead. The reason is technical: the
record types there come from the generated protobuf stub, which never emits
`readonly` fields, so a keyed table would not compile. A map gives the same
O(1) access and the brief allows either."

---

## Slide 8 — Q1 error handling *(2 min)*

> **This is the slide to spend time on.** It is the cleanest idea in the
> project.

```ballerina
public type ValidationError distinct error;   // → 400
public type NotFoundError   distinct error;   // → 404
public type ConflictError   distinct error;   // → 409
public type InternalError   distinct error;   // → 500
```

```ballerina
public isolated function toErrorResponse(error e, string path) returns ApiError {
    if e is ValidationError { return <BadRequestResponse>{ … }; }
    if e is NotFoundError   { return <NotFoundResponse>{ … }; }
    if e is ConflictError   { return <ConflictResponse>{ … }; }
    return <InternalErrorResponse>{ … };
}
```

*Say:* "The business layer never mentions HTTP. It raises a *typed* error. One
function maps type → status code, and every endpoint funnels through it.

Two consequences. First, it is impossible to return 404 for a validation
failure — the type system will not let you. Second, adding an endpoint costs
three lines, because the error path is already written."

**Show the uniform envelope:**

```json
{ "timestamp": "…", "status": 409, "error": "CONFLICT",
  "message": "Asset 'NUST-LIB-LAP-014' cannot be loaned because its status is LOANED_OUT.",
  "path": "/assets/NUST-LIB-LAP-014/loan" }
```

*Say:* "Every failure looks like this. The message is written for a human — it
says what went wrong **and what to do about it**. Compare that to a bare
`409 Conflict`."

---

## Slide 9 — Q1 endpoint tour *(90 s)*

| Group | Endpoints |
|-------|-----------|
| CRUD | `POST /assets` · `GET /assets` · `GET|PUT|DELETE /assets/{tag}` |
| Filtering | `/assets/institution/{i}` · `/assets/site/{s}` · `/sites` |
| Institutions | `GET` · `POST /institutions` · `DELETE /institutions/{i}` |
| Maintenance | `GET /maintenance/overdue` |
| Circulation | `POST /assets/{tag}/loan` · `POST /assets/{tag}/return` · `GET /loans` |
| Components | `POST` · `DELETE /assets/{tag}/components/{id}` |
| Schedules | `POST` · `DELETE /assets/{tag}/schedules/{id}` |
| Work orders | `POST` · `PUT` · `DELETE /assets/{tag}/workorders/{id}` |

*Say:* "24 endpoints. Note the nesting: a component has no independent
existence, so its URL is `/assets/{tag}/components/{id}` — you cannot address
one without naming its parent. That is REST resource modelling done properly."

**Two behaviours worth calling out:**

* Returning an asset with `sendForMaintenance: true` moves it to
  `UNDER_MAINTENANCE` **and raises a work order automatically**, so a reported
  fault is never lost.
* Closing the last open work order returns the asset to `AVAILABLE`
  automatically.

---

## Slide 10 — Q1 live demo *(3 min)*

*Terminal 1 is already running the service. Drive terminal 2.*

| Step | Action | Point to make |
|------|--------|---------------|
| 1 | Option **1** | Six assets, three institutions. Global view. |
| 2 | Option **7** | Four overdue schedules, **most overdue first**. |
| 3 | Option **3**, loan `NUST-LIB-LAP-014` | Status → `LOANED_OUT`, due date defaults to +14 days. |
| 4 | Option **3** again, same asset | **409 rejected.** "Only AVAILABLE assets can be issued." |
| 5 | Option **4**, return it, answer `y` to damaged | → `UNDER_MAINTENANCE` **and a work order appears**. |
| 6 | Option **5**, pick UNAM | Institution filter. |
| 7 | Option **8**, add a schedule dated last month | Then option **7** — it is on the dashboard. |

*Say at step 4:* "That is the conflict rule doing its job. The client did not
have to know the rule — the server told it, in a sentence a librarian could
read."

*If time is short, drop steps 6 and 7.*

---

## Slide 11 — Bonus web dashboard *(90 s)*

> Vanilla HTML + CSS + JavaScript. **No framework, no build step, no npm.**

*Switch to the browser. Have it already in dark mode.*

*Say:* "Same API, second consumer. This is the argument for building a proper
REST layer: we wrote zero new server code for this."

**Show, in this order — do not narrate everything:**

1. **Toggle the theme.** "Two full themes from CSS custom properties, and the
   choice is remembered in `localStorage`."
2. **Type in the search box.** "Debounced client-side filtering across five
   fields."
3. **Click an asset tag.** "Full detail — components, schedules, work orders
   with tickable tasks."
4. **Loan something.** "The table, the tiles and the loan-history tab all
   refresh from one API round trip."
5. **Narrow the window to phone width.** "Responsive down to 375 pixels."

*Mention once:* "Every value that reaches the DOM goes through an escaping
function, so an asset name containing markup cannot inject anything."

---

## Slide 12 — Q2 the contract *(2 min)*

```protobuf
service RentalService {
  rpc add_property              (AddPropertyRequest)        returns (AddPropertyResponse);
  rpc update_property           (UpdatePropertyRequest)     returns (UpdatePropertyResponse);
  rpc remove_property           (RemovePropertyRequest)     returns (RemovePropertyResponse);
  rpc search_property           (SearchPropertyRequest)     returns (SearchPropertyResponse);
  rpc book_property             (BookPropertyRequest)       returns (BookPropertyResponse);
  rpc confirm_booking           (ConfirmBookingRequest)     returns (ConfirmBookingResponse);
  rpc create_users              (stream CreateUserRequest)  returns (CreateUsersSummary);
  rpc list_available_properties (ListAvailableRequest)      returns (stream Property);
}
```

*Say:* "The `.proto` file is the single source of truth. Both the server and
the client generate their stubs from it, so the contract cannot drift. If we
rename a field, both sides stop compiling — which is exactly what you want."

**Two design decisions to defend:**

* **Every response carries `success` and `message`.** Business rejections come
  back as normal responses, not gRPC status errors. The brief demands this —
  `search_property` must answer "Not Available" rather than fail. gRPC status
  errors are reserved for cases with no meaningful response: a broken stream,
  or `minPrice > maxPrice`.
* **proto3 has no null.** An unset string arrives as `""`, an unset number as
  `0`. We turned that into a feature: in `update_property`, blank and zero mean
  "leave unchanged", which gives us patch semantics for free.

---

## Slide 13 — gRPC streaming explained *(3 min)*

> **The examiner will ask about this. Know it cold.**

### Client-side streaming — `create_users`

```
   CLIENT                                 SERVER
     │── CreateUserRequest ──────────────▶│
     │── CreateUserRequest ──────────────▶│   accumulating…
     │── CreateUserRequest ──────────────▶│
     │── half-close ─────────────────────▶│
     │◀───────────── CreateUsersSummary ──│   one reply
```

*Say:* "Many requests, one response, **one HTTP/2 stream**. A bulk import of
user profiles is unbounded in size. Unary would mean either N round trips with
N sets of headers, or one giant message both sides must buffer entirely.

The key call is `complete()` — the half-close. It tells the server no more
messages are coming, which is what unblocks the server's read loop.

Note the validation policy: each profile is validated independently, so one bad
email does not abort the batch. Failures come back in a `failures` array."

### Server-side streaming — `list_available_properties`

```
   CLIENT                                 SERVER
     │── ListAvailableRequest ───────────▶│
     │◀──────────────────────── Property ─│   rendered immediately
     │◀──────────────────────── Property ─│
     │◀──────────────────────── Property ─│
     │◀──────────────────── end of stream │
```

*Say:* "One request, many responses. A guest browsing the national catalogue
may match thousands of listings. Unary means the server builds the whole array
in memory and the client waits for the last byte before showing the first
result. Streaming lets the first listing render while the rest are still being
produced, and neither side ever holds more than one message.

On the server it is a pull-based generator — the runtime calls `next()` once
per message it writes. On the client we loop on `next()` and print as we go."

*Critical detail to volunteer:* "The client distinguishes **end of stream** —
`next()` returns nil — from **stream failure** — `next()` returns a
`grpc:Error`. An empty result set is not an error. That distinction is the sort
of thing that bites people who treat a stream like an array."

---

## Slide 14 — Q2 booking rules *(2 min)*

### Two phases

```
   book_property  ──▶  PENDING (cart)  ──▶  confirm_booking  ──▶  CONFIRMED
      validate dates      a wish,              re-check overlap
      advisory check      not a hold           compute cost
                                               clear the cart
```

*Say:* "A pending cart entry does **not** block the dates. That is deliberate:
if it did, one guest could freeze a property indefinitely by adding it to a
cart and walking away. Two guests may hold overlapping carts, and whoever
confirms first wins."

### Overlap detection

```
[aIn, aOut) overlaps [bIn, bOut)   ⟺   aIn < bOut  &&  bIn < aOut
```

| Existing | Requested | Overlap? |
|---|---|:--:|
| 10 → 14 | 14 → 18 | **no** — back-to-back is legal |
| 10 → 14 | 12 → 16 | yes |
| 10 → 14 | 11 → 13 | yes — fully inside |
| 10 → 14 | 08 → 20 | yes — fully contains |

*Say:* "Half-open intervals: check-in inclusive, check-out exclusive. That is
the hospitality convention, and it makes back-to-back bookings work naturally —
one guest leaves on the 14th, the next arrives on the 14th, no conflict.

Because dates are zero-padded ISO-8601 strings, a plain string comparison is
equivalent to a calendar comparison. No parsing on the hot path."

### Price

```
nights    = countNights(checkIn, checkOut)     // exclusive checkOut
totalCost = round(pricePerNight × nights, 2)
```

*Say:* "The estimate from `book_property` is advisory. `confirm_booking`
recalculates from the property's **current** price, so a host who changes the
rate between the two calls is honoured."

---

## Slide 15 — Concurrency *(2 min)*

> **The strongest slide in the deck. Do not rush it.**

### The bug we are preventing

```
   Guest A: check availability ──┐
   Guest B: check availability ──┤  both see "free"
   Guest A: write CONFIRMED    ──┤
   Guest B: write CONFIRMED    ──┘  ← double booking
```

### The mechanism

```ballerina
isolated map<Booking> bookingStore = {};
```

*Say:* "`isolated` on a module-level variable makes the **compiler refuse** any
access that is not inside a `lock` block. This is not a convention someone has
to remember and a reviewer has to catch — the build fails."

```ballerina
public isolated function confirmBookingAtomic(string bookingId, string guestId)
        returns Booking|error {
    lock {
        // 1. ownership check
        // 2. property still available?
        // 3. overlap scan over every CONFIRMED booking
        // 4. totalCost = pricePerNight × nights
        // 5. write CONFIRMED
        // 6. clear the guest's cart
    }
}
```

*Say:* "The naive fix is to lock each individual operation. That does not work
— the window is *between* the check and the write. So the whole critical
section lives in one lock. Whichever strand gets there first wins; the second
sees the freshly written `CONFIRMED` row and is rejected with an explicit
overlap message.

There is a third mechanism too: values are `clone()`d across every lock
boundary, so no caller can hold a live reference into a store and mutate it
behind the lock's back."

*If asked "did you test it?":* "Not with an automated race test — that is
honest. What we can say is stronger than a passing test: the compiler proves no
store is reachable outside a lock, and the entire read-modify-write sequence is
inside one. A load test would be the next step."

---

## Slide 16 — Q2 live demo *(3 min)*

*Terminal 3 is already running the server. Drive terminal 4.*

| Step | Action | Point to make |
|------|--------|---------------|
| 1 | Option **1**, accept the sample batch | Four profiles stream out **one at a time**; **one** summary comes back. |
| 2 | Option **5**, no filters | Five listings arrive one message at a time. `PROP-006` is withheld — it is `UNDER_MAINTENANCE`. |
| 3 | Option **5**, `Swakopmund`, max 1000 | Filters applied server-side; one result. |
| 4 | Option **7**, `PROP-001`, 2026-09-10 → 09-14 | Cart entry, 4 nights, estimated NAD 3800. **Nothing reserved yet.** |
| 5 | Option **8**, confirm | Recalculated, `CONFIRMED`, cart cleared. |
| 6 | Option **7**, `PROP-001`, 2026-09-12 → 09-16 | **Rejected** — explicit overlap message. |
| 7 | Option **7**, `PROP-001`, 2026-09-14 → 09-18 | **Accepted** — back-to-back is legal. |
| 8 | Option **4**, delete `PROP-001` | **Refused** — it carries a confirmed booking. |

*Steps 6 and 7 together are the money shot.* One is rejected, the next is
accepted, and the difference is a single day — that is the half-open interval
rule made visible.

---

## Slide 17 — REST vs gRPC *(90 s)*

| | REST (Q1) | gRPC (Q2) |
|---|---|---|
| Transport | HTTP/1.1 | HTTP/2 |
| Payload | JSON, self-describing | Protobuf, binary, schema-driven |
| Contract | Convention + docs | `.proto`, compiler-enforced |
| Browser | Native `fetch` | Needs a proxy |
| Streaming | Not natively | Client, server, bidirectional |
| Human-readable on the wire | Yes | No |
| Payload size | Larger | Roughly 3–10× smaller |
| Best for | Public APIs, browser clients | Internal service-to-service, streaming |

*Say:* "This is not a ranking, it is a fit question.

Question 1 has a browser consumer and a `curl`-wielding ministry IT
department. REST is right: any tool can call it, the payload is readable, and
we could hand someone a URL.

Question 2 is machine-to-machine with unbounded result sets and bulk imports.
gRPC is right: a binary schema, a contract that cannot drift, and streaming
built into the protocol.

The evidence that we made the right call is that our bonus web dashboard exists
at all. It talks to Question 1 directly from the browser. It could not do that
to Question 2 without a proxy."

---

## Slide 18 — What we would do next *(60 s)*

Be honest about the boundaries. It reads as competence, not weakness.

| Gap | What we would do |
|-----|------------------|
| Storage is in memory | Swap `database.bal` for PostgreSQL via `ballerina/sql`. The layering means only that one file changes. |
| No authentication | Ballerina has `http:JwtValidator` / `grpc` interceptors; add role checks so only a host can touch their listings. |
| No automated tests | Add `bal test` suites — especially a concurrent race test on `confirmBookingAtomic`. |
| Single instance | The `isolated`/`lock` model guards one process. Multiple instances would need optimistic locking in the database. |
| No pagination | `GET /assets` returns everything. At national scale it needs `limit`/`offset`. |

*Say:* "The layering is what makes the first row cheap. `services.bal` calls
`insertAsset` and `selectAsset` — it does not know or care whether those hit a
map or a database."

---

## Anticipated questions

**Q: Why is `assetTag` `readonly`?**
Ballerina requires the key field of a `table` to be immutable. That is also the
correct semantics — a primary key that can change is not a primary key. To
"change" a tag you delete and recreate, which is honest about what is really
happening.

**Q: What happens if two people loan the same asset simultaneously?**
`loanAsset` reads the asset, checks `status == AVAILABLE`, and writes. The read
and write are each atomic. The narrow window between them is the same class of
problem we solved properly in Question 2 with `confirmBookingAtomic` — and we
would close it the same way, by moving the whole sequence into one lock in
`database.bal`. Question 2 is where the brief asked for concurrency handling,
so that is where we did the careful version.

**Q: Why does a pending booking not block the dates?**
Because it would let one guest freeze inventory by abandoning a cart. Real
platforms use a *timed* hold — five or ten minutes. We would implement that
with a `ballerina/task` job that expires stale `PENDING` rows.

**Q: Why did you use a `map` in Q2 but a `table` in Q1?**
A `table<T> key(k)` requires `k` to be `readonly` inside `T`. Question 2's
records come from the generated protobuf stub, which never emits `readonly`
fields, so a keyed table would not compile. A map gives the same O(1) access
and the brief permits either.

**Q: Why are business errors returned as `success: false` rather than gRPC status codes?**
The contract demands it in at least one place — `search_property` must return
"Not Available", which is an outcome, not a failure. We kept the policy
consistent across all eight RPCs and reserved gRPC status errors for cases with
genuinely no response to send: a broken stream (`ABORTED`) and an incoherent
filter (`INVALID_ARGUMENT`).

**Q: How does the overdue report handle a corrupt stored date?**
It emits the row with `daysOverdue: -1` instead of failing. A single bad record
must not blind a maintenance officer to the other forty.

**Q: Is the web dashboard safe against XSS?**
Every value inserted into `innerHTML` goes through an `esc()` function that
escapes `& < > " '`. An asset named `<script>alert(1)</script>` renders as
text.

**Q: Why is `create_users` streaming rather than a `repeated` field?**
A `repeated` field means one message that both sides must buffer completely.
Streaming is constant-memory and gives incremental progress. For a ministry
onboarding thousands of hosts, that is the difference between working and
not.

**Q: What is `RENTAL_DESC` in the stub?**
The serialised `FileDescriptorProto` of `rental.proto`, hex-encoded. Both the
client stub and the service hand it to the gRPC runtime, which uses it to
resolve message shapes, method names and streaming modes at runtime. It is
generated — regenerate with `bal grpc` after editing the contract.

**Q: How do you handle a space in an institution name in a URL?**
The CLI client has a hand-written percent-encoder. We deliberately did not use
`url:encode`, because that applies form-encoding rules where a space becomes
`+` — inside a *path segment* a space must be `%20`, and `+` would resolve to
the wrong resource.

---

## Demo checklist

Print this. Tick it before you walk in.

- [ ] `bal version` ≥ 2201.10.0 on the demo machine
- [ ] Q1 service running on 8080 — `curl http://localhost:8080/health` returns `UP`
- [ ] Q1 client terminal open at `Question1/client`
- [ ] Q2 server running on 9090 — banner shows `6 seeded`
- [ ] Q2 client terminal open at `Question2/client`
- [ ] Web dashboard open, dark mode on, tiles populated
- [ ] Terminal font ≥ 16 pt, window wide enough for the 100-column tables
- [ ] `docs/API_DOCUMENTATION.md` open in a tab for questions
- [ ] Booking demo dates are **in the future** — check-in in the past is rejected
- [ ] Every group member is a contributor in the repository history
- [ ] Screenshots committed under `docs/screenshots/`

> **Restart trick.** Both servers hold state in memory. If a demo goes sideways,
> `Ctrl+C` and `bal run` restores the seeded state in seconds.

---

## Speaking-role split

For a group of eight, roughly two and a half minutes each.

| Member | Slides | Topic |
|--------|--------|-------|
| Matatias Nghihangwa | 1–2 | Title, the two problems |
| Eliaser Angula | 3–4 | Why Ballerina, repository layout |
| Pandera Katjipuka | 5–7 | Q1 architecture, domain model, storage |
| Monika Shalauda | 8–9 | Q1 error handling, endpoint tour |
| Risto Sakeus | 10–11 | Q1 live demo, web dashboard |
| Alanray Miller | 12–13 | Q2 contract, streaming explained |
| Kavara Edward | 14–15 | Booking rules, concurrency |
| Haufiku Frans | 16–18 | Q2 live demo, REST vs gRPC, next steps |

*Everyone* should be able to answer questions on slides 8, 13 and 15 — error
handling, streaming and concurrency are where the marks are.
