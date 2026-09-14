# DSA612S — Assignment 1

**Distributed Systems and Applications**
Namibia University of Science and Technology

Two complete distributed systems in one repository:

| # | Project | Protocol | Marks |
|---|---------|----------|-------|
| 1 | Distributed Library and Resource Management System | REST over HTTP/1.1 | 50 |
| 2 | Rental Accomodation System | gRPC over HTTP/2 | 50 |

Both are written in **Ballerina Swan Lake**, the language purpose-built for
network-distributed programming.

## Running on this Windows/XAMPP computer

Ballerina 2201.13.5 is installed. XAMPP uses port 8080, so the PowerShell
launcher uses **8081 for REST** and **9090 for gRPC**. From this repository,
run each command in a separate terminal:

```powershell
.\scripts\run.ps1 rest
.\scripts\run.ps1 rest-client
.\scripts\run.ps1 grpc
.\scripts\run.ps1 grpc-client
```

Open the [library dashboard through XAMPP](http://localhost/DISTRIBUTIVE%20SYSTEM/DSA612S-Assignment/Question1/web/?apiBase=http://localhost:8081).
If Apache is unavailable, run `.\scripts\run.ps1 web` and open the URL it prints.
The web launcher requires Python; the four Ballerina programs do not.

The package defaults below remain REST 8080 and gRPC 9090 for other computers.
See [verification results and remaining submission items](docs/VERIFICATION.md).

---

## Table of contents

1. [Project description](#1-project-description)
2. [Folder structure](#2-folder-structure)
3. [Prerequisites and installation](#3-prerequisites-and-installation)
4. [Running Question 1 — REST](#4-running-question-1--rest)
5. [Running the bonus web dashboard](#5-running-the-bonus-web-dashboard)
6. [Running Question 2 — gRPC](#6-running-question-2--grpc)
7. [API examples](#7-api-examples)
8. [gRPC walkthrough](#8-grpc-walkthrough)
9. [Architecture](#9-architecture)
10. [Configuration reference](#10-configuration-reference)
11. [Regenerating the Protocol Buffer stubs](#11-regenerating-the-protocol-buffer-stubs)
12. [Screenshots](#12-screenshots)
13. [Troubleshooting](#13-troubleshooting)
14. [Documentation](#14-documentation)

---

## 1. Project description last

### Question 1 — Distributed Library and Resource Management System

The Ministry of Higher Education, Training and Innovations needs one shared
catalogue for every registered institution of higher learning in Namibia. The
catalogue tracks three very different kinds of resource under a single model:

* **Books** — short-loan and prescribed titles.
* **Electronic resources** — loan laptops, thin clients, printers, 3D printers.
* **Physical spaces** — labs, meeting rooms, discussion rooms.

Every resource carries a globally unique `assetTag`, belongs to an institution
and a campus/site, and moves through a lifecycle of
`AVAILABLE → LOANED_OUT / OCCUPIED → AVAILABLE`, with detours through
`UNDER_MAINTENANCE` and a terminal `DISPOSED` state.

On top of that the system manages:

* **Components** — replaceable sub-parts (a printer's fuser unit, a laptop battery).
* **Schedules** — maintenance, servicing, inspection and room-booking entries,
  which drive the **overdue dashboard**.
* **Work orders and tasks** — repair jobs with individually tickable sub-tasks.

Delivered as a **Ballerina HTTP service**, a **Ballerina command-line client**,
and a bonus **HTML/CSS/JavaScript dashboard** written without any framework.

### Question 2 — Rental Accommodation System

The Ministry of Tourism needs a platform for short-term accommodation across
Namibia's regions, with two roles:

* **Hosts** register, update and remove property listings.
* **Guests** browse, search, add a stay to a temporary cart, and confirm it.

Confirmation is the interesting part: the server must re-verify availability,
reject overlapping date ranges, calculate `price × nights`, and clear the
guest's cart — all atomically, so two guests racing for the same week cannot
both win.

Delivered as a **`.proto` contract**, a **Ballerina gRPC server** and a
**Ballerina gRPC client**, exercising unary, client-streaming and
server-streaming RPCs.

---

## 2. Folder structure

```
DSA612S-Assignment/
│
├── README.md                     ← you are here
│
├── Question1/                    ── REST: Library & Resource Management
│   ├── service/                  ── the HTTP API (Ballerina package)
│   │   ├── Ballerina.toml
│   │   ├── main.bal              ← transport layer: listener + 25 resources
│   │   ├── models.bal            ← domain records, enums, DTOs, typed responses
│   │   ├── database.bal          ← in-memory table<Asset> key(assetTag) + seed
│   │   ├── services.bal          ← business rules, transport-agnostic
│   │   └── util.bal              ← errors, dates, validation, error mapping
│   │
│   ├── client/                   ── the CLI client (separate Ballerina package)
│   │   ├── Ballerina.toml
│   │   └── client.bal            ← 10-option interactive menu over HTTP
│   │
│   └── web/                      ── BONUS dashboard (no frameworks)
│       ├── index.html
│       ├── styles.css            ← design tokens, light + dark themes
│       └── app.js                ← REST integration, modals, toasts, sorting
│
├── Question2/                    ── gRPC: Rental Accommodation
│   ├── proto/
│   │   └── rental.proto          ← the service contract (8 RPCs, 3 styles)
│   │
│   ├── server/                   ── the gRPC server (Ballerina package)
│   │   ├── Ballerina.toml
│   │   ├── main.bal              ← listener, configuration, bootstrap
│   │   ├── service.bal           ← the eight RPC implementations
│   │   ├── database.bal          ← map-based stores, calendar + validation
│   │   └── rental_pb.bal         ← generated Protocol Buffer stub
│   │
│   └── client/                   ── the gRPC client (Ballerina package)
│       ├── Ballerina.toml
│       ├── client.bal            ← 9-option interactive menu
│       └── rental_pb.bal         ← generated Protocol Buffer stub
│
└── docs/
    ├── API_DOCUMENTATION.md      ← every endpoint and every RPC, in detail
    └── PRESENTATION.md           ← speaker notes for the defence
```

Each of the four Ballerina packages is **independent** — its own
`Ballerina.toml`, its own build. That is deliberate: it forces client and
server to communicate only over the wire, which is the whole point of a
distributed system.

---

## 3. Prerequisites and installation

### Install Ballerina

Ballerina Swan Lake **2201.10.0 or newer**.

| Platform | Command |
|----------|---------|
| Windows | Download the MSI from <https://ballerina.io/downloads/> |
| macOS | `brew install ballerina` |
| Linux | `curl -sSL https://dist.ballerina.io/downloads/latest/ballerina-linux-installer-x64.deb -o bal.deb && sudo dpkg -i bal.deb` |

Verify the installation:

```bash
bal version
```

You should see `Ballerina 2201.x.x (Swan Lake Update ..)`. Nothing else needs
installing — the `http`, `grpc`, `protobuf`, `time`, `io` and `log` modules all
ship with the distribution, and they are pulled automatically on the first
build.

### Clone the repository

```bash
git clone <your-repository-url>
```

```bash
cd DSA612S-Assignment
```

---

## 4. Running Question 1 — REST

### 4.1 Start the REST server

```bash
cd Question1/service
```

```bash
bal run
```

Expected output:

```
============================================================
  DSA612S - Library and Resource Management System (REST)
  Ministry of Higher Education, Training and Innovations
============================================================
  Listening on : http://localhost:8080
  Seeded assets: 6
  Health check : http://localhost:8080/health
  Press Ctrl+C to stop the server.
============================================================
```

The server starts with **six seeded assets** across three institutions (NUST,
UNAM, IUM), deliberately including schedules that are already in the past so
`GET /maintenance/overdue` returns meaningful rows immediately.

Confirm it is alive:

```bash
curl http://localhost:8080/health
```

### 4.2 Start the REST client

In a **second terminal**:

```bash
cd Question1/client
```

```bash
bal run
```

You get the interactive menu:

```
==============================================================
   LIBRARY AND RESOURCE MANAGEMENT - MAIN MENU
==============================================================
    1.  View Assets                (global view)
    2.  Search Asset               (by tag or free text)
    3.  Loan Asset                 (issue / book a space)
    4.  Return Asset               (hand back / release)
    5.  View Institution Assets    (filter by institution)
    6.  View Campus Assets         (filter by site)
    7.  View Overdue Maintenance   (staff dashboard)
    8.  Manage Schedules           (add / modify / remove)
    9.  Create Work Order          (fault reporting)
   10.  Exit
==============================================================
```

Point the client at a different server with:

```bash
bal run -- -CapiUrl=http://192.168.1.20:8080
```

### 4.3 A three-minute demonstration script

1. Option **1** — see all six assets.
2. Option **7** — overdue schedules across NUST, UNAM and IUM.
3. Option **3** — loan `NUST-LIB-LAP-014` to a student; status becomes `LOANED_OUT`.
4. Option **1** again — the status change is visible.
5. Option **4** — return it, answering `y` to "damaged"; the asset moves to
   `UNDER_MAINTENANCE` **and a work order is raised automatically**.
6. Option **5** — filter to "University of Namibia".
7. Option **8** — add a maintenance schedule dated in the past, then
   option **7** again to watch it appear on the overdue dashboard.

---

## 5. Running the bonus web dashboard

The dashboard is plain HTML, CSS and JavaScript — **no build step, no npm, no
framework**. With the REST server already running:

**Option A — open the file directly**

Double-click `Question1/web/index.html`. CORS is enabled for all origins on the
service, so a `file://` page can call the API.

**Option B — serve it (recommended)**

```bash
cd Question1/web
```

```bash
python -m http.server 5500
```

Then browse to <http://localhost:5500>.

**Option C — XAMPP**

Copy `Question1/web` into `htdocs` and browse to
<http://localhost/web/index.html>.

### Dashboard features

| Feature | Where |
|---------|-------|
| Live summary tiles (total, available, out, maintenance, overdue) | top of page |
| Search across tag, name, description, institution, site | toolbar |
| Filter by institution, campus/site and status | toolbar |
| Sortable columns | click any table header |
| Full asset detail with components, schedules, work orders | click an asset tag |
| Loan an asset / book a space | **Loan** button |
| Return an asset, optionally flagging damage | **Return** button |
| Add a maintenance / servicing / inspection / booking schedule | **Schedule** button |
| Modify a schedule's date, type or description | **Edit** in asset detail or the Overdue tab |
| Open a work order with any number of sub-tasks | **W/O** button |
| Close or delete a work order | Work Orders tab |
| Overdue maintenance dashboard | Overdue tab |
| Loan history audit trail | Loan History tab |
| Register a new asset | **New Asset** button |
| **Dark mode**, remembered between visits | moon/sun button |
| Responsive down to 375 px | resize the window |
| Auto-refresh every 30 seconds | automatic |

If your API runs somewhere else, set it once in the browser console:

```javascript
localStorage.setItem('dsa.apiBase', 'http://192.168.1.20:8080'); location.reload();
```

---

## 6. Running Question 2 — gRPC

### 6.1 Start the gRPC server

```bash
cd Question2/server
```

```bash
bal run
```

Expected output:

```
================================================================
   DSA612S - RENTAL ACCOMMODATION SYSTEM (gRPC)
   Ministry of Tourism - Republic of Namibia
================================================================
   Listening on   : http://localhost:9090
   Service        : rental.RentalService
   Properties     : 6 seeded
   Hosts / Guests : 3 / 3
----------------------------------------------------------------
   RPCs exposed:
     add_property               (unary)
     update_property            (unary)
     remove_property            (unary)
     search_property            (unary)
     book_property              (unary)
     confirm_booking            (unary)
     create_users               (client streaming)
     list_available_properties  (server streaming)
----------------------------------------------------------------
   Seeded host ids : HOST-001, HOST-002, HOST-003
   Seeded guest ids: GUEST-001, GUEST-002, GUEST-003
   Press Ctrl+C to stop the server.
================================================================
```

### 6.2 Start the gRPC client

In a **second terminal**:

```bash
cd Question2/client
```

```bash
bal run
```

```
==================================================================
   RENTAL ACCOMMODATION SYSTEM - MAIN MENU
==================================================================
    1.  Create Users                (CLIENT STREAMING)
    2.  Add Property                (unary)
    3.  Update Property             (unary)
    4.  Delete Property             (unary)
    5.  List Available Properties   (SERVER STREAMING)
    6.  Search Property             (unary)
    7.  Book Property               (unary)
    8.  Confirm Booking             (unary)
    9.  Exit
------------------------------------------------------------------
   Session: host=HOST-001  guest=GUEST-001
==================================================================
```

The client remembers the last host, guest, property and cart identifiers it
saw and offers them as defaults in `[square brackets]` — press Enter to accept.

Point it at a different server with:

```bash
bal run -- -CserverUrl=http://192.168.1.20:9090
```

### 6.3 A four-minute demonstration script

1. Option **1**, accept the sample batch — watch four profiles stream out one
   at a time and a **single** summary come back. That is client streaming.
2. Option **5**, all filters blank — watch five listings arrive one message at
   a time. That is server streaming. (`PROP-006` is withheld because it is
   `UNDER_MAINTENANCE`.)
3. Option **5** again with location `Swakopmund` and max price `1000` — only
   `PROP-001` comes back.
4. Option **6** with `PROP-005` — full details, status `AVAILABLE`.
5. Option **7** — book `PROP-001` for `2026-09-10` → `2026-09-14`. The reply is
   a **cart entry**: 4 nights, estimated NAD 3800.00. Nothing is reserved yet.
6. Option **8** — confirm it. The server recalculates the cost, marks the
   booking `CONFIRMED` and clears the cart.
7. Option **7** again, same property, overlapping dates
   (`2026-09-12` → `2026-09-16`) — **rejected** with an explicit overlap
   message. That is the booking-validation requirement.
8. Option **4** — try to delete `PROP-001`; refused, because it now carries a
   confirmed booking.

---

## 7. API examples

Base URL: `http://localhost:8080`

### Create an asset

```bash
curl -X POST http://localhost:8080/assets -H "Content-Type: application/json" -d "{\"assetTag\":\"NUST-LIB-3DP-002\",\"name\":\"Pro-Series 3D Printer II\",\"description\":\"Second printer for the innovation lab.\",\"institution\":\"Namibia University of Science and Technology\",\"site\":\"Main Campus - Innovation Lab\",\"status\":\"AVAILABLE\",\"dateAcquired\":\"2025-06-01\",\"components\":[],\"schedules\":[],\"workOrders\":[]}"
```

`201 Created` with the stored asset.

### Get all assets

```bash
curl http://localhost:8080/assets
```

### Get one asset

```bash
curl http://localhost:8080/assets/NUST-LIB-3DP-001
```

### Update an asset (partial)

```bash
curl -X PUT http://localhost:8080/assets/NUST-LIB-3DP-001 -H "Content-Type: application/json" -d "{\"site\":\"Main Campus - Advanced Prototyping Lab\"}"
```

### Delete an asset

```bash
curl -X DELETE http://localhost:8080/assets/NUST-LIB-3DP-002
```

### Filter by institution

```bash
curl "http://localhost:8080/assets/institution/University%20of%20Namibia"
```

### Filter by campus / site

```bash
curl "http://localhost:8080/assets/site/Windhoek%20Campus%20-%20Computer%20Lab%20B"
```

### Overdue maintenance

```bash
curl http://localhost:8080/maintenance/overdue
```

```json
[
  {
    "assetTag": "UNAM-LIB-TC-207",
    "assetName": "HP t640 Thin Client",
    "institution": "University of Namibia",
    "site": "Windhoek Campus - Computer Lab B",
    "status": "UNDER_MAINTENANCE",
    "scheduleId": "SCH-1002",
    "scheduleType": "MAINTENANCE",
    "dueDate": "2026-06-21",
    "description": "Firmware update and thermal paste replacement.",
    "daysOverdue": 45
  }
]
```

### Loan an asset

```bash
curl -X POST http://localhost:8080/assets/NUST-LIB-LAP-014/loan -H "Content-Type: application/json" -d "{\"borrower\":\"221012345\",\"dueDate\":\"2026-09-15\"}"
```

### Book a meeting room (status becomes `OCCUPIED`)

```bash
curl -X POST http://localhost:8080/assets/NUST-LIB-ROOM-002/loan -H "Content-Type: application/json" -d "{\"borrower\":\"Dr. Shipanga\",\"spaceBooking\":true}"
```

### Return an asset

```bash
curl -X POST http://localhost:8080/assets/NUST-LIB-LAP-014/return -H "Content-Type: application/json" -d "{}"
```

### Return a damaged asset (auto-raises a work order)

```bash
curl -X POST http://localhost:8080/assets/NUST-LIB-LAP-014/return -H "Content-Type: application/json" -d "{\"notes\":\"Cracked screen bezel\",\"sendForMaintenance\":true}"
```

### Add a component

```bash
curl -X POST http://localhost:8080/assets/NUST-LIB-3DP-001/components -H "Content-Type: application/json" -d "{\"name\":\"Filament Feeder\",\"description\":\"Dual-drive extruder feeder.\"}"
```

### Remove a component

```bash
curl -X DELETE http://localhost:8080/assets/NUST-LIB-3DP-001/components/C102
```

### Add a maintenance schedule

```bash
curl -X POST http://localhost:8080/assets/NUST-LIB-3DP-001/schedules -H "Content-Type: application/json" -d "{\"type\":\"MAINTENANCE\",\"dueDate\":\"2026-12-01\",\"description\":\"Annual belt tension check.\"}"
```

### Delete a schedule

```bash
curl -X DELETE http://localhost:8080/assets/NUST-LIB-3DP-001/schedules/SCH-882
```

### Create a work order

```bash
curl -X POST http://localhost:8080/assets/NUST-LIB-3DP-001/workorders -H "Content-Type: application/json" -d "{\"status\":\"OPEN\",\"description\":\"Extruder jams intermittently\",\"tasks\":[{\"description\":\"Strip and clean the hot end.\"},{\"description\":\"Replace the PTFE liner.\"}]}"
```

### Update a work order

```bash
curl -X PUT http://localhost:8080/assets/NUST-LIB-3DP-001/workorders/WO-554 -H "Content-Type: application/json" -d "{\"status\":\"CLOSED\"}"
```

### Delete a work order

```bash
curl -X DELETE http://localhost:8080/assets/NUST-LIB-3DP-001/workorders/WO-554
```

### Error responses

Every failure uses the same envelope:

```bash
curl http://localhost:8080/assets/DOES-NOT-EXIST
```

```json
{
  "timestamp": "2026-08-05T14:32:07Z",
  "status": 404,
  "error": "NOT_FOUND",
  "message": "No asset found with tag 'DOES-NOT-EXIST'.",
  "path": "/assets/DOES-NOT-EXIST"
}
```

| Code | Meaning | Example trigger |
|------|---------|-----------------|
| `400` | Bad Request | blank `name`, malformed `dueDate`, unknown `status` filter |
| `404` | Not Found | unknown `assetTag`, `componentId`, `scheduleId`, `orderId` |
| `409` | Conflict | duplicate `assetTag`, loaning an asset that is already out |
| `500` | Internal Server Error | an unexpected failure escaping the service layer |

Full documentation of all 25 endpoints: [`docs/API_DOCUMENTATION.md`](docs/API_DOCUMENTATION.md).

---

## 8. gRPC walkthrough

### The contract

```protobuf
service RentalService {
  rpc add_property              (AddPropertyRequest)         returns (AddPropertyResponse);
  rpc update_property           (UpdatePropertyRequest)      returns (UpdatePropertyResponse);
  rpc remove_property           (RemovePropertyRequest)      returns (RemovePropertyResponse);
  rpc search_property           (SearchPropertyRequest)      returns (SearchPropertyResponse);
  rpc book_property             (BookPropertyRequest)        returns (BookPropertyResponse);
  rpc confirm_booking           (ConfirmBookingRequest)      returns (ConfirmBookingResponse);
  rpc create_users              (stream CreateUserRequest)   returns (CreateUsersSummary);
  rpc list_available_properties (ListAvailableRequest)       returns (stream Property);
}
```

### Client streaming — `create_users`

Many requests → one response.

```ballerina
Create_usersStreamingClient sc = check ep->create_users();
foreach CreateUserRequest profile in batch {
    check sc->sendCreateUserRequest(profile);   // N messages
}
check sc->complete();                            // half-close
CreateUsersSummary? summary = check sc->receiveCreateUsersSummary();  // 1 reply
```

The server drains the stream with `next()` until it returns `()`, validating
each profile independently so one bad record does not abort the batch.

### Server streaming — `list_available_properties`

One request → many responses.

```ballerina
stream<Property, grpc:Error?> s = check ep->list_available_properties(filter);
record {|Property value;|}|grpc:Error? item = s.next();
while item is record {|Property value;|} {
    printPropertyRow(item.value);                // rendered as it arrives
    item = s.next();
}
```

The server returns a `stream<Property, error?>` backed by a pull-based
generator; the runtime writes one gRPC message per `next()` call.

### Booking validation

Two half-open ranges `[aIn, aOut)` and `[bIn, bOut)` overlap exactly when:

```
aIn < bOut  &&  bIn < aOut
```

Because dates are zero-padded ISO-8601 strings, a plain string comparison is
equivalent to a calendar comparison.

`confirm_booking` performs the availability re-check, the price calculation,
the state transition and the cart clearing **inside a single `lock`**, so two
guests confirming overlapping stays at the same instant cannot both succeed.

Full documentation of all eight RPCs: [`docs/API_DOCUMENTATION.md`](docs/API_DOCUMENTATION.md).

---

## 9. Architecture

### Question 1 — layered REST service

```
   HTTP client (CLI / browser / curl)
                │  JSON over HTTP/1.1
   ┌────────────▼──────────────────────────────────────┐
   │  main.bal      TRANSPORT LAYER                    │
   │  25 resource functions, typed HTTP responses,     │
   │  CORS, status-code mapping                        │
   ├───────────────────────────────────────────────────┤
   │  services.bal  BUSINESS LAYER                     │
   │  domain rules, id generation, read models         │
   │  (no `http` import anywhere in this file)         │
   ├───────────────────────────────────────────────────┤
   │  database.bal  PERSISTENCE LAYER                  │
   │  isolated table<Asset> key(assetTag)              │
   │  isolated table<LoanRecord> key(loanId)           │
   ├───────────────────────────────────────────────────┤
   │  util.bal      CROSS-CUTTING                      │
   │  error hierarchy, calendar maths, validation      │
   └───────────────────────────────────────────────────┘
```

The single most useful design decision is the **distinct error hierarchy** in
`util.bal`:

```ballerina
public type ValidationError distinct error;   // → 400
public type NotFoundError   distinct error;   // → 404
public type ConflictError   distinct error;   // → 409
public type InternalError   distinct error;   // → 500
```

`toErrorResponse` maps a failure onto an HTTP status by its **type**, never by
string matching. Adding an endpoint costs three lines, and it is impossible to
return the wrong status code for a given failure.

### Question 2 — layered gRPC service

```
   Ballerina gRPC client
                │  Protocol Buffers over HTTP/2
   ┌────────────▼──────────────────────────────────────┐
   │  rental_pb.bal   CONTRACT (generated)             │
   │  RENTAL_DESC, messages, enums, typed stub         │
   ├───────────────────────────────────────────────────┤
   │  service.bal     SERVICE LAYER                    │
   │  8 RPCs, per-request validation, streaming        │
   ├───────────────────────────────────────────────────┤
   │  database.bal    PERSISTENCE + UTILITIES          │
   │  isolated map<Property> / map<Host> /             │
   │  map<Guest> / map<Booking>, calendar, validation  │
   ├───────────────────────────────────────────────────┤
   │  main.bal        BOOTSTRAP                        │
   │  grpc:Listener, configurables, seed data          │
   └───────────────────────────────────────────────────┘
```

### Concurrency

Both servers handle every request on its own strand, so all stores are shared
mutable state. The strategy is identical in both projects:

1. Every store is declared `isolated`, which makes the **compiler reject** any
   access outside a `lock` block.
2. Values are `clone()`d across the lock boundary, so no caller can ever hold a
   live reference into a store.
3. Sequences that must be atomic run entirely inside one `lock` —
   `confirmBookingAtomic` is the clearest example.

This is compile-time-verified thread safety, not a convention someone has to
remember.

### Why Ballerina?

* **Network primitives are language constructs.** `service`, `resource
  function`, `listener`, `client` and `remote function` are keywords, not
  library types. A REST endpoint is a language-level declaration.
* **`isolated` gives compiler-checked concurrency.** Very few languages can
  *prove* that shared state is only touched under a lock.
* **The type system models the wire.** Union return types
  (`Asset|BadRequestResponse|NotFoundResponse|…`) make every possible HTTP
  outcome part of the function signature.
* **Errors are values, not exceptions.** `check` propagates them; `distinct`
  error types let the transport layer dispatch on them.
* **First-class gRPC.** `bal grpc` generates the stub, and streaming RPCs map
  onto native Ballerina `stream` values.
* **Tables and queries are built in.** `from … where … order by … select` over
  an in-memory table needs no ORM.

---

## 10. Configuration reference

Every package is configurable without editing code, either through a
`Config.toml` beside `Ballerina.toml` or with `-C` flags.

| Package | Variable | Default | Meaning |
|---------|----------|---------|---------|
| `Question1/service` | `servicePort` | `8080` | HTTP port |
| `Question1/service` | `loadSeedData` | `true` | Load the six demo assets |
| `Question1/client` | `apiUrl` | `http://localhost:8080` | REST base URL |
| `Question1/client` | `requestTimeout` | `30` | Seconds before giving up |
| `Question2/server` | `serverPort` | `9090` | gRPC port |
| `Question2/server` | `loadSeedData` | `true` | Load the demo catalogue |
| `Question2/client` | `serverUrl` | `http://localhost:9090` | gRPC server URL |

Example `Question1/service/Config.toml`:

```toml
servicePort = 9000
loadSeedData = false
```

Or on the command line:

```bash
bal run -- -CservicePort=9000 -CloadSeedData=false
```

---

## 11. Regenerating the Protocol Buffer stubs

`rental_pb.bal` is committed in both `Question2/server` and `Question2/client`
so the projects build with no extra tooling step. After editing
`proto/rental.proto`, regenerate it:

```bash
cd Question2
```

```bash
bal grpc --input proto/rental.proto --output server --mode service
```

```bash
bal grpc --input proto/rental.proto --output client --mode client
```

The `--mode service` run also emits a `rental_service.bal` skeleton — delete it,
because `service.bal` is the real implementation. Keep only `rental_pb.bal`.

---

## 12. Screenshots

Place captures in a `docs/screenshots/` folder and they will render here.

| # | What to capture | Suggested filename |
|---|-----------------|--------------------|
| 1 | REST server start-up banner | `01-rest-server-start.png` |
| 2 | CLI client main menu | `02-rest-client-menu.png` |
| 3 | CLI global asset view (option 1) | `03-rest-all-assets.png` |
| 4 | CLI overdue dashboard (option 7) | `04-rest-overdue.png` |
| 5 | CLI loan flow (option 3) | `05-rest-loan.png` |
| 6 | Web dashboard, light mode | `06-web-light.png` |
| 7 | Web dashboard, dark mode | `07-web-dark.png` |
| 8 | Web dashboard, asset detail modal | `08-web-detail.png` |
| 9 | Web dashboard on a phone width | `09-web-mobile.png` |
| 10 | gRPC server start-up banner | `10-grpc-server-start.png` |
| 11 | gRPC client streaming users (option 1) | `11-grpc-create-users.png` |
| 12 | gRPC server streaming listings (option 5) | `12-grpc-list-stream.png` |
| 13 | gRPC booking + confirmation (options 7, 8) | `13-grpc-booking.png` |
| 14 | gRPC overlapping-booking rejection | `14-grpc-overlap-reject.png` |

```markdown
![REST server start-up](docs/screenshots/01-rest-server-start.png)
![Web dashboard, dark mode](docs/screenshots/07-web-dark.png)
![gRPC client streaming](docs/screenshots/11-grpc-create-users.png)
```

---

## 13. Troubleshooting

**`error: address already in use`**
Another process holds the port. Change it:

```bash
bal run -- -CservicePort=8081
```

**CLI client says "Cannot reach the API"**
The REST server is not running, or it is on another port. Start it first, then
check with `curl http://localhost:8080/health`.

**Web dashboard shows "API offline"**
Confirm the server is up, then confirm the base URL:

```javascript
localStorage.getItem('dsa.apiBase')
```

**gRPC client says "did not answer"**
The gRPC server is not running. gRPC needs HTTP/2, so a plain browser cannot
call it — use the Ballerina client.

**`bal` command not found**
Ballerina's `bin` directory is not on your `PATH`. Reopen the terminal after
installing, or add it manually.

**First build is slow**
Ballerina is resolving the standard-library modules from Ballerina Central.
Subsequent builds use the local cache. Force offline builds with
`bal build --offline`.

**A stub does not match your Ballerina version**
Regenerate it — see [section 11](#11-regenerating-the-protocol-buffer-stubs).

---

## 14. Documentation

| Document | Contents |
|----------|----------|
| [`docs/API_DOCUMENTATION.md`](docs/API_DOCUMENTATION.md) | Every REST endpoint and every gRPC RPC: parameters, payloads, status codes, examples, data dictionary |
| [`docs/PRESENTATION.md`](docs/PRESENTATION.md) | Slide-by-slide speaker notes, architecture explanations, streaming deep-dive, likely defence questions |

Generate the Ballerina API docs for any package with:

```bash
bal doc
```

---

## Group members

| Name | Student number | Contribution |
|------|----------------|--------------|
| _(add name)_ | _(add number)_ | REST service — models, database, services |
| _(add name)_ | _(add number)_ | REST service — transport layer, error handling |
| _(add name)_ | _(add number)_ | REST CLI client |
| _(add name)_ | _(add number)_ | Web dashboard (bonus) |
| _(add name)_ | _(add number)_ | Protocol Buffer contract |
| _(add name)_ | _(add number)_ | gRPC server — service layer |
| _(add name)_ | _(add number)_ | gRPC server — persistence and concurrency |
| _(add name)_ | _(add number)_ | gRPC client and documentation |

> All members must appear as contributors in the repository history.

---

## Licence

Submitted as academic coursework for DSA612S, Namibia University of Science
and Technology. Source released under Apache-2.0.
