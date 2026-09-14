# API Documentation

**DSA612S — Assignment 1**
Distributed Library and Resource Management System (REST) &
Rental Accommodation System (gRPC)

---

## Contents

**Part A — REST API (Question 1)**
1. [Overview](#a1-overview)
2. [Data dictionary](#a2-data-dictionary)
3. [Error model](#a3-error-model)
4. [Endpoint index](#a4-endpoint-index)
5. [System endpoints](#a5-system-endpoints)
6. [Asset CRUD](#a6-asset-crud)
7. [Institution and campus views](#a7-institution-and-campus-views)
8. [Maintenance and overdue reporting](#a8-maintenance-and-overdue-reporting)
9. [Loaning and returning](#a9-loaning-and-returning)
10. [Component management](#a10-component-management)
11. [Schedule management](#a11-schedule-management)
12. [Work order management](#a12-work-order-management)
13. [State machine](#a13-state-machine)

**Part B — gRPC API (Question 2)**
14. [Overview](#b1-overview)
15. [Data dictionary](#b2-data-dictionary)
16. [RPC index](#b3-rpc-index)
17. [Unary RPCs](#b4-unary-rpcs)
18. [Client-side streaming](#b5-client-side-streaming--create_users)
19. [Server-side streaming](#b6-server-side-streaming--list_available_properties)
20. [Booking rules and the cart model](#b7-booking-rules-and-the-cart-model)
21. [Concurrency guarantees](#b8-concurrency-guarantees)

---
---

# PART A — REST API

## A1. Overview

| Property | Value |
|----------|-------|
| Base URL | `http://localhost:8080` |
| Protocol | HTTP/1.1 |
| Content type | `application/json` |
| Authentication | None (a ministry intranet deployment) |
| CORS | All origins, methods `GET POST PUT DELETE OPTIONS` |
| Unique key | `assetTag` |
| Storage | `table<Asset> key(assetTag)`, in memory |

The API follows REST conventions: nouns in paths, verbs as HTTP methods,
sub-resources nested under their parent, and a status code that carries the
outcome.

---

## A2. Data dictionary

### `Asset` — the aggregate root

| Field | Type | Required | Notes |
|-------|------|:--------:|-------|
| `assetTag` | string | yes | Primary key. Unique ministry-wide. Immutable. Max 64 chars. |
| `name` | string | yes | Max 200 chars. |
| `description` | string | no | Defaults to `""`. |
| `institution` | string | yes | Owning institution of higher learning. |
| `site` | string | yes | Campus / site / room. |
| `status` | `AssetStatus` | no | Defaults to `AVAILABLE`. |
| `dateAcquired` | string | yes | ISO-8601 `YYYY-MM-DD`. May not be in the future. |
| `components` | `Component[]` | no | Defaults to `[]`. `compId` unique within the asset. |
| `schedules` | `Schedule[]` | no | Defaults to `[]`. `scheduleId` unique within the asset. |
| `workOrders` | `WorkOrder[]` | no | Defaults to `[]`. `orderId` unique within the asset. |

### `AssetStatus`

| Value | Meaning |
|-------|---------|
| `AVAILABLE` | Free to be loaned or booked. |
| `LOANED_OUT` | Issued to a borrower (books, laptops, thin clients). |
| `OCCUPIED` | In use as a physical space (labs, meeting rooms). |
| `UNDER_MAINTENANCE` | Withdrawn for servicing or repair. |
| `DISPOSED` | Written off. Terminal state. |

### `Component`

| Field | Type | Required | Notes |
|-------|------|:--------:|-------|
| `compId` | string | yes | Unique within the parent asset. |
| `name` | string | yes | Max 200 chars. |
| `description` | string | no | Defaults to `""`. |

### `Schedule`

| Field | Type | Required | Notes |
|-------|------|:--------:|-------|
| `scheduleId` | string | yes | Unique within the parent asset. |
| `type` | `ScheduleType` | no | Defaults to `MAINTENANCE`. |
| `dueDate` | string | yes | ISO-8601 `YYYY-MM-DD`. Drives the overdue report. |
| `description` | string | no | Max 500 chars. |

`ScheduleType` ∈ `MAINTENANCE` · `SERVICING` · `INSPECTION` · `BOOKING`

### `WorkOrder`

| Field | Type | Required | Notes |
|-------|------|:--------:|-------|
| `orderId` | string | yes | Unique within the parent asset. |
| `status` | `WorkOrderStatus` | no | Defaults to `OPEN`. |
| `description` | string | yes | Max 500 chars. |
| `tasks` | `Task[]` | no | Defaults to `[]`. |

`WorkOrderStatus` ∈ `OPEN` · `IN_PROGRESS` · `CLOSED` · `CANCELLED`

### `Task`

| Field | Type | Required | Notes |
|-------|------|:--------:|-------|
| `taskId` | string | yes | Unique within the parent work order. |
| `description` | string | yes | What has to be done. |
| `completed` | boolean | no | Defaults to `false`. |

### `LoanRecord`

The `Asset` payload defined by the brief carries no borrower field, so loans
are tracked in a dedicated store rather than polluting the asset.

| Field | Type | Notes |
|-------|------|-------|
| `loanId` | string | Primary key, e.g. `LN-1001`. |
| `assetTag` | string | The asset that was issued. |
| `borrower` | string | Staff/student number or name. |
| `loanedOn` | string | ISO-8601 date the asset left the shelf. |
| `dueDate` | string | ISO-8601 date it is expected back. |
| `returnedOn` | string \| null | `null` while still out. |
| `active` | boolean | `true` while still out. |

### Sample asset payload

```json
{
  "assetTag": "NUST-LIB-3DP-001",
  "name": "Pro-Series 3D Printer",
  "description": "High-precision laboratory printer for simulation and prototype development.",
  "institution": "Namibia University of Science and Technology",
  "site": "Main Campus - Innovation Lab",
  "status": "AVAILABLE",
  "dateAcquired": "2024-03-10",
  "components": [
    { "compId": "C101", "name": "High-Torque Stepper Motor", "description": "Main motor for X-axis movement." }
  ],
  "schedules": [
    { "scheduleId": "SCH-882", "type": "MAINTENANCE", "dueDate": "2026-09-01", "description": "Quarterly calibration and nozzle cleaning." }
  ],
  "workOrders": [
    {
      "orderId": "WO-554",
      "status": "OPEN",
      "description": "Nozzle heat-bed failure",
      "tasks": [ { "taskId": "T1", "description": "Check thermal sensor connectivity.", "completed": false } ]
    }
  ]
}
```

---

## A3. Error model

Failures detected by the service's business logic return this envelope:

```json
{
  "timestamp": "2026-08-05T14:32:07Z",
  "status": 404,
  "error": "NOT_FOUND",
  "message": "No asset found with tag 'XYZ'.",
  "path": "/assets/XYZ"
}
```

| Field | Meaning |
|-------|---------|
| `timestamp` | RFC-3339 instant the failure was produced. |
| `status` | The HTTP status code, repeated in the body for logging. |
| `error` | Machine-friendly code: `BAD_REQUEST`, `NOT_FOUND`, `CONFLICT`, `INTERNAL_SERVER_ERROR`. |
| `message` | Human-readable explanation, safe to display to a user. |
| `path` | The request path, for traceability. |

### How a status code is chosen

The service layer never mentions HTTP. It raises one of four **distinct error
types**, and `util.bal:toErrorResponse` maps the type onto a status:

| Ballerina type | HTTP | Raised when |
|----------------|:----:|-------------|
| `ValidationError` | 400 | Input is syntactically or semantically invalid. |
| `NotFoundError` | 404 | The addressed resource does not exist. |
| `ConflictError` | 409 | The request clashes with current state. |
| `InternalError` | 500 | Anything unexpected. |

The error type determines the HTTP status in a shared response mapper.

Malformed JSON, or a body that cannot bind to the declared record, is rejected
by the Ballerina HTTP module with a `400` before the resource function runs.
Unknown routes return `404`, and unsupported methods return `405`. These
transport errors use the HTTP module's response format.

---

## A4. Endpoint index

| # | Method | Path | Purpose |
|---|--------|------|---------|
| 1 | `GET` | `/health` | Liveness probe |
| 2 | `GET` | `/summary` | Dashboard counters |
| 3 | `POST` | `/assets` | Create asset |
| 4 | `GET` | `/assets` | List / search assets |
| 5 | `GET` | `/assets/{assetTag}` | Read one asset |
| 6 | `PUT` | `/assets/{assetTag}` | Partial update |
| 7 | `DELETE` | `/assets/{assetTag}` | Delete asset |
| 8 | `GET` | `/assets/institution/{institution}` | Filter by institution |
| 9 | `GET` | `/assets/site/{site}` | Filter by campus / site |
| 10 | `GET` | `/institutions` | List institutions |
| 11 | `POST` | `/institutions` | Add an institution |
| 12 | `DELETE` | `/institutions/{institution}` | Withdraw an institution |
| 13 | `GET` | `/sites` | List campuses / sites |
| 14 | `GET` | `/maintenance/overdue` | Overdue schedules |
| 15 | `POST` | `/assets/{assetTag}/loan` | Loan / book |
| 16 | `POST` | `/assets/{assetTag}/return` | Return / release |
| 17 | `GET` | `/loans` | Loan audit trail |
| 18 | `POST` | `/assets/{assetTag}/components` | Add component |
| 19 | `DELETE` | `/assets/{assetTag}/components/{componentId}` | Remove component |
| 20 | `POST` | `/assets/{assetTag}/schedules` | Add schedule |
| 21 | `DELETE` | `/assets/{assetTag}/schedules/{scheduleId}` | Delete schedule |
| 22 | `POST` | `/assets/{assetTag}/workorders` | Create work order |
| 23 | `PUT` | `/assets/{assetTag}/workorders/{orderId}` | Update work order |
| 24 | `DELETE` | `/assets/{assetTag}/workorders/{orderId}` | Delete work order |
| 25 | `PUT` | `/assets/{assetTag}/schedules/{scheduleId}` | Modify schedule |

> Path segments containing spaces must be percent-encoded — `%20`, not `+`.
> The CLI client and the dashboard both do this for you.

---

## A5. System endpoints

### 1. `GET /health`

Liveness probe. The CLI client and the dashboard both call it before showing
their UI, so a wrong port is reported once and clearly.

**200 OK**
```json
{
  "status": "UP",
  "service": "library-resource-management",
  "version": "1.0.0",
  "timestamp": "2026-08-05T14:32:07Z",
  "assets": 6
}
```

### 2. `GET /summary`

Headline counters that back the dashboard tiles.

**200 OK**
```json
{
  "totalAssets": 6,
  "institutions": 3,
  "sites": 6,
  "overdueSchedules": 3,
  "activeLoans": 0,
  "byStatus": { "AVAILABLE": 5, "UNDER_MAINTENANCE": 1 },
  "generatedAt": "2026-08-05T14:32:07Z"
}
```

---

## A6. Asset CRUD

### 3. `POST /assets`

Creates a new asset.

**Request body** — a full `Asset`.

**Responses**

| Code | Body | When |
|------|------|------|
| `201` | The stored `Asset` | Success |
| `400` | `ErrorDetail` | Blank required field, bad `dateAcquired`, future acquisition date, duplicate nested id |
| `409` | `ErrorDetail` | `assetTag` already in use |
| `500` | `ErrorDetail` | Unexpected failure |

**Validation applied**

* `assetTag`, `name`, `institution`, `site` must be non-blank.
* `assetTag` ≤ 64 chars, `name` ≤ 200 chars.
* `dateAcquired` must be a real calendar date and not in the future.
* `compId`, `scheduleId`, `orderId` and `taskId` must be unique within their
  collection.
* Every `schedules[].dueDate` must parse, otherwise the overdue report breaks.
* All string keys are trimmed before storage.

```bash
curl -X POST http://localhost:8080/assets -H "Content-Type: application/json" -d "{\"assetTag\":\"IUM-LIB-LAP-101\",\"name\":\"Lenovo ThinkPad L15\",\"institution\":\"International University of Management\",\"site\":\"Dorado Campus - Resource Centre\",\"dateAcquired\":\"2025-01-20\"}"
```

---

### 4. `GET /assets`

Lists every asset, ordered by `assetTag`. All query parameters are optional and
combine with AND semantics.

| Parameter | Type | Meaning |
|-----------|------|---------|
| `q` | string | Free text over tag, name, description, institution, site |
| `institution` | string | Exact match, case insensitive |
| `site` | string | Exact match, case insensitive |
| `status` | `AssetStatus` | Exact match |

**Responses**: `200` with `Asset[]`; `400` when `status` is not a legal value.

```bash
curl "http://localhost:8080/assets?institution=University%20of%20Namibia&status=AVAILABLE"
```

```bash
curl "http://localhost:8080/assets?q=printer"
```

---

### 5. `GET /assets/{assetTag}`

**Responses**: `200` with the `Asset`; `404` when the tag is unknown.

---

### 6. `PUT /assets/{assetTag}`

Partial update. **Only the fields present in the body are changed**; everything
else is carried over. `assetTag` cannot be changed — it is the primary key.

**Request body** — any subset of:

```json
{
  "name": "…", "description": "…", "institution": "…", "site": "…",
  "status": "AVAILABLE", "dateAcquired": "2024-03-10",
  "components": [], "schedules": [], "workOrders": []
}
```

The merged result is re-validated in full, so a partial update can never leave
the store inconsistent.

**Responses**

| Code | When |
|------|------|
| `200` | Updated `Asset` |
| `400` | The merged asset fails validation |
| `404` | Unknown `assetTag` |
| `409` | Setting `status: "DISPOSED"` while the asset is out on loan |

---

### 7. `DELETE /assets/{assetTag}`

**Responses**

| Code | Body | When |
|------|------|------|
| `200` | `OperationResult` | Deleted |
| `404` | `ErrorDetail` | Unknown tag |
| `409` | `ErrorDetail` | Asset is `LOANED_OUT` or `OCCUPIED` |

```json
{
  "message": "Asset 'IUM-LIB-LAP-101' was deleted successfully.",
  "assetTag": "IUM-LIB-LAP-101",
  "resourceId": ""
}
```

---

## A7. Institution and campus views

### 8. `GET /assets/institution/{institution}`

Every asset owned by one institution. Matching is case insensitive and ignores
surrounding whitespace.

**Responses**: `200` with `Asset[]` (possibly empty); `400` for a blank name.

```bash
curl "http://localhost:8080/assets/institution/Namibia%20University%20of%20Science%20and%20Technology"
```

### 9. `GET /assets/site/{site}`

Every asset at one campus / site. Same matching rules.

```bash
curl "http://localhost:8080/assets/site/Main%20Campus%20-%20Innovation%20Lab"
```

### 10. `GET /institutions`

The distinct institutions in the listing: those registered through
`POST /institutions` plus those implied by an asset that references them.

**200 OK**
```json
[
  "International University of Management",
  "Namibia University of Science and Technology",
  "University of Namibia"
]
```


### 11. `POST /institutions`

Adds an institution to the listing. This is the counterpart to
`DELETE /institutions/{institution}`, and lets the ministry accredit an
institution before any of its assets have been captured.

**Request**
```json
{
  "name": "Welwitschia University of Namibia",
  "description": "WUN - private institution, Windhoek"
}
```

| Field | Required | Notes |
|-------|----------|-------|
| `name` | yes | Must be unique across the listing, maximum 200 characters |
| `description` | no | Free text, maximum 500 characters; defaults to `""` |

**201 Created**
```json
{
  "name": "Welwitschia University of Namibia",
  "description": "WUN - private institution, Windhoek",
  "registeredOn": "2026-08-18"
}
```

`registeredOn` is stamped by the server on the day the institution is added.

| Status | Trigger |
|--------|---------|
| `400` | `name` is blank, or a field exceeds its maximum length |
| `409` | The name is already in the listing, whether it was registered explicitly or is implied by an existing asset |

Matching is case insensitive, so `welwitschia university of namibia` collides
with the entry above.
### 12. `DELETE /institutions/{institution}`

Withdraws an institution from the listing by removing every asset it owns.
This is the removal half of the "manage institutions" requirement; `POST
/institutions` is the other half. An institution is present in the listing while
it owns assets or holds a registry row, so this endpoint drops both. An
institution registered ahead of its assets owns nothing yet, and is still
removable.

**Refuses** with `409` if any of its assets is still `LOANED_OUT` or `OCCUPIED`.

**200 OK**
```json
{
  "message": "Institution 'International University of Management' and 1 asset(s) were removed.",
  "institution": "International University of Management",
  "removedAssetTags": ["IUM-LIB-PRN-033"]
}
```

### 13. `GET /sites`

The distinct campuses / sites. Optional `?institution=` narrows the list.

---

## A8. Maintenance and overdue reporting

### 14. `GET /maintenance/overdue`

Every schedule entry whose `dueDate` lies strictly before today, flattened
together with its parent asset so the dashboard needs no second lookup.

| Parameter | Type | Default | Meaning |
|-----------|------|---------|---------|
| `institution` | string | — | Narrow to one institution |
| `site` | string | — | Narrow to one campus / site |
| `includeBookings` | boolean | `false` | Also list past `BOOKING` schedules |

**Rules**

* `DISPOSED` assets are skipped — there is no point chasing maintenance on an
  asset that has been written off.
* `BOOKING` schedules are skipped by default: a booking in the past is a
  booking that *happened*, not an outstanding job.
* Rows are returned **most overdue first**, which is the order a maintenance
  officer wants.
* A stored date that cannot be parsed yields `daysOverdue: -1` rather than
  sinking the whole report.

**200 OK**
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

---

## A9. Loaning and returning

### 15. `POST /assets/{assetTag}/loan`

Issues an asset to a borrower, or books a physical space.

**Request body**

| Field | Type | Required | Default |
|-------|------|:--------:|---------|
| `borrower` | string | yes | — |
| `dueDate` | string | no | today + 14 days |
| `spaceBooking` | boolean | no | `false` |

```json
{ "borrower": "221012345", "dueDate": "2026-09-15", "spaceBooking": false }
```

**Rules**

* The asset must exist and be **`AVAILABLE`**. Anything else is a `409`.
* `dueDate`, if supplied, must be a real date and not in the past.
* `spaceBooking: false` → status becomes `LOANED_OUT`.
  `spaceBooking: true` → status becomes `OCCUPIED`.
* A `LoanRecord` is written to the audit trail **after** the status change
  succeeds, so the two can never disagree.

**Responses**: `200` with the updated `Asset`; `400`, `404`, `409`, `500`.

---

### 16. `POST /assets/{assetTag}/return`

Accepts an asset back, or releases a booked space.

**Request body** — both fields have defaults, so `{}` is valid.

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `notes` | string | `""` | Condition notes recorded on hand-back |
| `sendForMaintenance` | boolean | `false` | Route the asset to maintenance |

**Rules**

* The asset must currently be `LOANED_OUT` or `OCCUPIED`, otherwise `409`.
* `sendForMaintenance: false` → status becomes `AVAILABLE`.
* `sendForMaintenance: true` → status becomes `UNDER_MAINTENANCE` **and a work
  order is raised automatically**, seeded with the damage notes and an
  "Inspect the asset" task, so a reported fault is never lost.
* The open `LoanRecord` is closed and stamped with today's date.

```bash
curl -X POST http://localhost:8080/assets/NUST-LIB-LAP-014/return -H "Content-Type: application/json" -d "{\"notes\":\"Cracked screen bezel\",\"sendForMaintenance\":true}"
```

---

### 17. `GET /loans`

The loan and booking audit trail, newest first. Optional `?assetTag=` narrows
it to one asset.

**200 OK**
```json
[
  {
    "loanId": "LN-1001",
    "assetTag": "NUST-LIB-LAP-014",
    "borrower": "221012345",
    "loanedOn": "2026-08-05",
    "dueDate": "2026-09-15",
    "returnedOn": null,
    "active": true
  }
]
```

---

## A10. Component management

### 18. `POST /assets/{assetTag}/components`

| Field | Type | Required | Notes |
|-------|------|:--------:|-------|
| `compId` | string | no | Generated as `C-<n>` when omitted |
| `name` | string | yes | Max 200 chars |
| `description` | string | no | Defaults to `""` |

**Rules**: the asset must exist and must not be `DISPOSED`; `compId` must not
already be used on that asset.

**Responses**: `200` with the parent `Asset`; `400`, `404`, `409` (duplicate
`compId` or disposed asset), `500`.

### 19. `DELETE /assets/{assetTag}/components/{componentId}`

**Responses**: `200` with the parent `Asset`; `404` when either the asset or
the component is unknown.

---

## A11. Schedule management

### 20. `POST /assets/{assetTag}/schedules`

| Field | Type | Required | Notes |
|-------|------|:--------:|-------|
| `scheduleId` | string | no | Generated as `SCH-<n>` when omitted |
| `type` | `ScheduleType` | no | Defaults to `MAINTENANCE` |
| `dueDate` | string | yes | ISO-8601 `YYYY-MM-DD` |
| `description` | string | no | Max 500 chars |

**Rules**

* The asset must exist and must not be `DISPOSED`.
* `dueDate` must be a real calendar date. Past dates are **allowed** — that is
  precisely how a schedule becomes overdue.
* `scheduleId` must be free on that asset.
* **Double-booking guard**: two `BOOKING` schedules may not share a `dueDate`
  on the same asset. Two groups cannot occupy one meeting room at once.

**Responses**: `200` with the parent `Asset`; `400`, `404`, `409`, `500`.

```bash
curl -X POST http://localhost:8080/assets/NUST-LIB-ROOM-002/schedules -H "Content-Type: application/json" -d "{\"type\":\"BOOKING\",\"dueDate\":\"2026-10-14\",\"description\":\"DSA612S group presentation.\"}"
```

### 21. `DELETE /assets/{assetTag}/schedules/{scheduleId}`

**Responses**: `200` with the parent `Asset`; `404`.

---

### 25. `PUT /assets/{assetTag}/schedules/{scheduleId}`

Updates an existing schedule without changing its identifier. Supply any of
`type`, `dueDate` or `description`; omitted fields retain their stored values.
Returns the updated asset. Invalid dates return `400`, missing schedules
return `404`, and a conflicting booking date returns `409`.

```json
{"dueDate": "2026-12-01", "description": "Rescheduled servicing"}
```

The Ballerina client's option 8 supports adding, modifying and removing
schedules. The web dashboard provides an Edit button beside each schedule.

## A12. Work order management

### 22. `POST /assets/{assetTag}/workorders`

| Field | Type | Required | Notes |
|-------|------|:--------:|-------|
| `orderId` | string | no | Generated as `WO-<n>` when omitted |
| `status` | `WorkOrderStatus` | no | Defaults to `OPEN` |
| `description` | string | yes | Max 500 chars |
| `tasks` | `TaskRequest[]` | no | `taskId` generated as `T-<n>` when omitted |

**Rules**

* The asset must exist and must not be `DISPOSED`.
* `orderId` must be free on that asset; `taskId`s must be unique within the order.
* **Side effect**: opening an `OPEN` or `IN_PROGRESS` job against an
  `AVAILABLE` asset moves it to `UNDER_MAINTENANCE`, so nobody loans a resource
  that is known to be faulty.

```bash
curl -X POST http://localhost:8080/assets/NUST-LIB-3DP-001/workorders -H "Content-Type: application/json" -d "{\"description\":\"Extruder jams intermittently\",\"tasks\":[{\"description\":\"Strip and clean the hot end.\"},{\"description\":\"Replace the PTFE liner.\"}]}"
```

### 23. `PUT /assets/{assetTag}/workorders/{orderId}`

Any subset of `status`, `description`, `tasks`. Supplying `tasks` replaces the
whole list.

**Side effect**: once every job on an asset is `CLOSED` or `CANCELLED`, an asset
that is `UNDER_MAINTENANCE` is returned to `AVAILABLE` automatically.

```bash
curl -X PUT http://localhost:8080/assets/NUST-LIB-3DP-001/workorders/WO-554 -H "Content-Type: application/json" -d "{\"status\":\"CLOSED\",\"tasks\":[{\"taskId\":\"T1\",\"description\":\"Check thermal sensor connectivity.\",\"completed\":true}]}"
```

### 24. `DELETE /assets/{assetTag}/workorders/{orderId}`

Same automatic return-to-service side effect as above.

---

## A13. State machine

```
                   ┌────────────────────────────────────┐
                   │                                    │
                   ▼                                    │
            ┌─────────────┐   POST /loan          ┌──────────────┐
   create → │  AVAILABLE  │──────────────────────▶│  LOANED_OUT  │
            └─────────────┘   (spaceBooking:false)└──────────────┘
              │    ▲    │                                 │
              │    │    │ POST /loan                      │ POST /return
              │    │    │ (spaceBooking:true)             │
              │    │    ▼                                 │
              │    │  ┌──────────────┐  POST /return      │
              │    │  │   OCCUPIED   │────────────────────┤
              │    │  └──────────────┘                    │
              │    │                                      │
   POST       │    │ all work orders CLOSED / CANCELLED   │ return with
   /workorders│    │ (PUT or DELETE)                      │ sendForMaintenance
              ▼    │                                      │
        ┌────────────────────┐◀───────────────────────────┘
        │ UNDER_MAINTENANCE  │
        └────────────────────┘
              │
              │ PUT /assets/{tag}  {"status":"DISPOSED"}
              ▼
        ┌────────────┐
        │  DISPOSED  │  terminal — no components, schedules or work orders
        └────────────┘
```

**Guards**

* `DELETE /assets/{tag}` is refused while `LOANED_OUT` or `OCCUPIED`.
* `status: "DISPOSED"` is refused while an active loan exists.
* Components, schedules and work orders cannot be added to a `DISPOSED` asset.

---
---

# PART B — gRPC API

## B1. Overview

| Property | Value |
|----------|-------|
| Server URL | `http://localhost:9090` |
| Protocol | gRPC over HTTP/2 |
| Serialisation | Protocol Buffers, `proto3` |
| Package | `rental` |
| Service | `rental.RentalService` |
| Contract | `Question2/proto/rental.proto` |
| Storage | `map<Property>`, `map<Host>`, `map<Guest>`, `map<Booking>` |

### Why maps rather than keyed tables here?

A Ballerina `table<T> key(k)` requires the field `k` to be declared `readonly`
inside `T`. The record types in Question 2 come from the generated Protocol
Buffer stub, which never emits `readonly` fields. A `map<T>` gives the same
O(1) primary-key access, and the brief permits either.

Question 1 defines its own records, so it uses
`table<Asset> key(assetTag)` — the stronger structure — as required.

### Error policy

Every response message carries a `success` (or `found`) flag and a `message`
string. A **business** rejection — unknown host, dates in the past, a clashing
booking — comes back as a normal response with `success = false`. That is what
the contract asks for (`search_property` must answer `"NOT AVAILABLE"` rather
than fail) and it keeps client control flow simple.

A **gRPC status error** is reserved for situations where there is no meaningful
response to send:

| Status | Raised by | When |
|--------|-----------|------|
| `ABORTED` | `create_users` | The inbound client stream broke mid-flight |
| `INVALID_ARGUMENT` | `list_available_properties` | `minPrice > maxPrice` |

---

## B2. Data dictionary

### `Property`

| Field | Proto type | Ballerina | Notes |
|-------|------------|-----------|-------|
| `propertyId` | `string` | `string` | Server-generated, e.g. `PROP-101` |
| `hostId` | `string` | `string` | Owning host |
| `name` | `string` | `string` | ≤ 150 chars |
| `location` | `string` | `string` | Region / town |
| `propertyType` | `string` | `string` | Upper-cased on storage |
| `pricePerNight` | `double` | `float` | NAD, must be > 0 |
| `status` | `PropertyStatus` | enum | See below |
| `description` | `string` | `string` | Marketing copy |
| `maxGuests` | `int32` | `int` | 1 … 100 |
| `amenities` | `repeated string` | `string[]` | Upper-cased on storage |

`PropertyStatus` ∈ `PROPERTY_STATUS_UNKNOWN`(0) · `AVAILABLE`(1) ·
`UNAVAILABLE`(2) · `UNDER_MAINTENANCE`(3)

### `Host` / `Guest`

| `Host` | | `Guest` | |
|--------|--|---------|--|
| `hostId` | string | `guestId` | string |
| `name` | string | `name` | string |
| `email` | string | `email` | string |
| `phone` | string | `phone` | string |
| `region` | string | | |

### `Booking`

| Field | Type | Notes |
|-------|------|-------|
| `bookingId` | string | e.g. `BKG-1001` |
| `propertyId` | string | |
| `guestId` | string | |
| `checkIn` | string | ISO-8601, **inclusive** |
| `checkOut` | string | ISO-8601, **exclusive** |
| `totalCost` | double | `pricePerNight × nights` |
| `state` | `BookingState` | |
| `nights` | int32 | |
| `confirmedAt` | string | Timestamp, `""` while pending |
| `propertyName` | string | Denormalised for display |

`BookingState` ∈ `BOOKING_STATE_UNKNOWN`(0) · `PENDING`(1) · `CONFIRMED`(2) ·
`CANCELLED`(3)

`UserRole` ∈ `USER_ROLE_UNKNOWN`(0) · `HOST`(1) · `GUEST`(2)

> **proto3 has no null.** An unset `string` arrives as `""`, an unset number as
> `0`, an unset enum as its zero member. The server therefore treats blank and
> zero as "leave unchanged" in `update_property`, and as "no filter" in
> `list_available_properties`.

---

## B3. RPC index

| # | RPC | Style | Request | Response |
|---|-----|-------|---------|----------|
| 1 | `add_property` | unary | `AddPropertyRequest` | `AddPropertyResponse` |
| 2 | `update_property` | unary | `UpdatePropertyRequest` | `UpdatePropertyResponse` |
| 3 | `remove_property` | unary | `RemovePropertyRequest` | `RemovePropertyResponse` |
| 4 | `search_property` | unary | `SearchPropertyRequest` | `SearchPropertyResponse` |
| 5 | `book_property` | unary | `BookPropertyRequest` | `BookPropertyResponse` |
| 6 | `confirm_booking` | unary | `ConfirmBookingRequest` | `ConfirmBookingResponse` |
| 7 | `create_users` | **client streaming** | `stream CreateUserRequest` | `CreateUsersSummary` |
| 8 | `list_available_properties` | **server streaming** | `ListAvailableRequest` | `stream Property` |

---

## B4. Unary RPCs

### 1. `add_property`

A host registers a new listing; the server issues the `propertyId`.

**Validation** (all before anything is stored)

| Rule | Message on failure |
|------|--------------------|
| `hostId`, `name`, `location`, `propertyType` non-blank | `'<field>' is required and must not be blank.` |
| `name` ≤ 150 chars | `'name' must not exceed 150 characters.` |
| `pricePerNight` > 0 | `'pricePerNight' must be greater than zero…` |
| `pricePerNight` ≤ 1 000 000 | `'pricePerNight' is implausibly high…` |
| `maxGuests` ≥ 1 | `'maxGuests' must be at least 1…` |
| `maxGuests` ≤ 100 | `'maxGuests' may not exceed 100…` |
| `hostId` must be registered | `Unknown host '<id>'. Register the host first with create_users.` |

An unset `status` (proto3 zero) defaults to `AVAILABLE`.

```ballerina
AddPropertyResponse response = check ep->add_property({
    hostId: "HOST-001",
    name: "Dune 7 Chalet",
    location: "Walvis Bay",
    propertyType: "CHALET",
    pricePerNight: 1450.0,
    status: AVAILABLE,
    description: "Self-catering chalet with dune views.",
    maxGuests: 4,
    amenities: ["WIFI", "PARKING", "BRAAI"]
});
```

```json
{
  "success": true,
  "message": "Property 'Dune 7 Chalet' was registered as PROP-101.",
  "propertyId": "PROP-101",
  "property": { "propertyId": "PROP-101", "…": "…" }
}
```

---

### 2. `update_property`

Patches a listing. **Blank strings and zero numbers mean "leave unchanged"**,
so a host can change only the price:

```ballerina
UpdatePropertyResponse response = check ep->update_property({
    propertyId: "PROP-101",
    hostId: "HOST-001",
    pricePerNight: 1600.0     // everything else stays as it was
});
```

**Rules**: the listing must exist, and `hostId` must match the owner —
a host may only touch their own listings.

---

### 3. `remove_property`

Deletes a listing and returns **all AVAILABLE properties in the host's
region**, including listings owned by other hosts in that region.

**Rules**

* The listing must exist and be owned by `hostId`.
* A listing carrying a `CONFIRMED` booking whose `checkOut` is still in the
  future **cannot** be removed — otherwise a guest would arrive to find
  nothing reserved.

```json
{
  "success": true,
  "message": "Property removed; available regional listings returned.",
  "region": "Walvis Bay",
  "remainingProperties": [ { "propertyId": "PROP-001", "…": "…" } ]
}
```

The response identifies the region and includes its available listings.

---

### 4. `search_property`

Looks one listing up by id.

| Situation | `found` | `status` |
|-----------|:-------:|----------|
| Id unknown | `false` | `"NOT AVAILABLE"` |
| Exists, `status = AVAILABLE` | `true` | `"AVAILABLE"` |
| Exists, `UNAVAILABLE` / `UNDER_MAINTENANCE` | `true` | `"NOT AVAILABLE"` |

The third row is the important one: the listing genuinely exists, so the full
details are returned, but it is not rentable.

---

### 5. `book_property` — add to the cart

Validates a requested stay and places it into the guest's **temporary booking
cart**. Nothing is reserved yet.

**Validation, in order**

1. `propertyId` and `guestId` non-blank.
2. The guest must be registered (see `create_users`).
3. The property must exist and be `AVAILABLE`.
4. `checkIn` / `checkOut` must be real ISO-8601 dates.
5. `checkOut` must be **strictly after** `checkIn`.
6. `checkIn` may not be in the past.
7. The stay must be 1 … 365 nights.
8. No `CONFIRMED` booking may already overlap the range *(advisory — re-checked
   at confirmation)*.
9. The identical stay must not already be in the guest's cart.

```json
{
  "success": true,
  "message": "Request 'BKG-1001' added to your cart: 4 night(s) at Atlantic Dune Apartment, estimated NAD 3800.0. Call confirm_booking to finalise it.",
  "bookingId": "BKG-1001",
  "nights": 4,
  "estimatedCost": 3800.0
}
```

> **Night counting.** `checkIn` is inclusive, `checkOut` is exclusive — the
> standard hospitality convention. Arriving on the 10th and leaving on the
> 14th is **four** nights.

---

### 6. `confirm_booking` — finalise

Turns a cart entry into a real reservation. Everything below happens **inside a
single `lock`**:

1. The cart entry must exist, be `PENDING`, and belong to `guestId`.
2. The property must still exist and still be `AVAILABLE`.
3. No *other* `CONFIRMED` booking may overlap the dates.
4. `nights = countNights(checkIn, checkOut)`;
   `totalCost = round(pricePerNight × nights)`.
5. The row transitions to `CONFIRMED` and is stamped with `confirmedAt`.
6. Any *other* pending wish of the same guest that now collides with the
   confirmed stay is dropped — the cart is cleared.

```json
{
  "success": true,
  "message": "Booking BKG-1001 confirmed: 4 night(s) at Atlantic Dune Apartment, total NAD 3800.0.",
  "booking": {
    "bookingId": "BKG-1001",
    "propertyId": "PROP-001",
    "guestId": "GUEST-001",
    "checkIn": "2026-09-10",
    "checkOut": "2026-09-14",
    "totalCost": 3800.0,
    "state": "CONFIRMED",
    "nights": 4,
    "confirmedAt": "2026-08-05T14:41:12Z",
    "propertyName": "Atlantic Dune Apartment"
  }
}
```

**Rejection messages**

| Cause | Message |
|-------|---------|
| Unknown id | `No booking request found with id 'BKG-9999'.` |
| Wrong guest | `Booking 'BKG-1001' does not belong to guest 'GUEST-002'.` |
| Already done | `Booking 'BKG-1001' has already been confirmed.` |
| Property gone | `The property 'PROP-101' has been removed by its host.` |
| Not available | `Property 'PROP-006' is UNDER_MAINTENANCE and can no longer be booked.` |
| Overlap | `Property 'PROP-001' is already booked from 2026-09-10 to 2026-09-14; the requested dates 2026-09-12 to 2026-09-16 overlap it.` |

---

## B5. Client-side streaming — `create_users`

```protobuf
rpc create_users (stream CreateUserRequest) returns (CreateUsersSummary);
```

**Many requests → one response, over one HTTP/2 stream.**

### Why streaming fits here

A bulk import of user profiles is unbounded in size. Unary would mean either
one RPC per profile (N round trips, N sets of headers) or one giant message
that must be fully buffered on both sides. Client streaming gives one round
trip, constant memory, and a single atomic summary.

### Client side

```ballerina
Create_usersStreamingClient sc = check ep->create_users();

foreach CreateUserRequest profile in batch {
    check sc->sendCreateUserRequest(profile);      // N messages
}
check sc->complete();                              // half-close

CreateUsersSummary? summary = check sc->receiveCreateUsersSummary();
```

`complete()` is the half-close: it tells the server no more messages are
coming, which is what unblocks the server's `next()` loop.

### Server side

```ballerina
remote function create_users(stream<CreateUserRequest, grpc:Error?> clientStream)
        returns CreateUsersSummary|error {

    record {|CreateUserRequest value;|}|grpc:Error? item = clientStream.next();
    while item is record {|CreateUserRequest value;|} {
        // … validate and store one profile …
        item = clientStream.next();               // () when the client half-closes
    }
    if item is grpc:Error {
        return error grpc:AbortedError("…");
    }
    return summary;
}
```

### Per-record validation

Each profile is validated **independently**. A bad record is recorded in
`failures` and the stream keeps going — the behaviour a bulk import needs.

| Rule | Failure line |
|------|--------------|
| `name` non-blank | `[3] 'name' is required and must not be blank.` |
| `email` well formed | `[3] Lukas: 'lukasexample.na' is not a valid email address.` |
| `role` ≠ `USER_ROLE_UNKNOWN` | `[3] Lukas: role must be HOST or GUEST.` |
| `email` not already registered | `[3] Lukas: email '…' is already registered.` |

`userId` is optional: supply one, or let the server issue `HOST-<n>` /
`GUEST-<n>`.

**Response**

```json
{
  "success": true,
  "message": "Received 4 profile(s): 2 host(s) and 2 guest(s) registered, 0 rejected.",
  "totalReceived": 4,
  "hostsCreated": 2,
  "guestsCreated": 2,
  "failures": [],
  "createdIds": ["HOST-101", "HOST-102", "GUEST-101", "GUEST-102"]
}
```

---

## B6. Server-side streaming — `list_available_properties`

```protobuf
rpc list_available_properties (ListAvailableRequest) returns (stream Property);
```

**One request → many responses, over one HTTP/2 stream.**

### Why streaming fits here

A guest browsing the national catalogue may match thousands of listings. A
unary reply would force the server to build the whole array in memory and the
client to wait for the last byte before showing the first result. Streaming
lets the first listing render while the rest are still being produced, and
neither side ever holds more than one message.

### Request filters

Every filter is optional; blank / zero means "no filter".

| Field | Type | Semantics |
|-------|------|-----------|
| `location` | string | **Substring**, case insensitive |
| `propertyType` | string | Exact, case insensitive |
| `minPrice` | double | `pricePerNight >= minPrice` |
| `maxPrice` | double | `pricePerNight <= maxPrice`; `0` = no upper bound |
| `minGuests` | int32 | `maxGuests >= minGuests`; `0` = any |

Only `AVAILABLE` listings are ever streamed. Results come cheapest first.
`minPrice > maxPrice` is rejected with `INVALID_ARGUMENT`, because an empty
stream would otherwise be indistinguishable from "nothing is available".

### Server side

```ballerina
remote function list_available_properties(ListAvailableRequest request)
        returns stream<Property, error?>|error {
    Property[] matches = searchAvailable(request);
    return new stream<Property, error?>(new PropertyGenerator(matches));
}
```

`PropertyGenerator` is a pull-based iterator: the runtime calls `next()` once
per gRPC message it writes onto the wire.

### Client side

```ballerina
stream<Property, grpc:Error?> s = check ep->list_available_properties(filter);

record {|Property value;|}|grpc:Error? item = s.next();
while item is record {|Property value;|} {
    printPropertyRow(item.value);      // rendered as it arrives
    item = s.next();
}
if item is grpc:Error { /* the stream broke mid-flight */ }
error? _ = s.close();
```

Note the distinction the client draws between **end of stream** (`next()`
returns `()`) and **stream failure** (`next()` returns a `grpc:Error`). An
empty result set is not an error.

---

## B7. Booking rules and the cart model

### The two-phase design

```
   book_property                        confirm_booking
        │                                     │
        ▼                                     ▼
   ┌──────────┐   validate dates,        ┌───────────┐
   │ PENDING  │   advisory overlap       │ CONFIRMED │  re-check overlap
   │  (cart)  │──────────────────────────▶│           │  compute cost
   └──────────┘   check                  └───────────┘  clear cart
```

A `PENDING` row is a **wish**, not a reservation: it does **not** block the
dates. Two guests may therefore hold overlapping carts, and whoever confirms
first wins. That is a deliberate choice — holding inventory on an unconfirmed
cart entry would let one guest freeze a property indefinitely.

### Overlap detection

Two half-open ranges `[aIn, aOut)` and `[bIn, bOut)` collide exactly when:

```
aIn < bOut  &&  bIn < aOut
```

| Existing booking | Requested | Overlap? |
|------------------|-----------|:--------:|
| 10 → 14 | 14 → 18 | no — back-to-back is fine |
| 10 → 14 | 12 → 16 | **yes** |
| 10 → 14 | 08 → 12 | **yes** |
| 10 → 14 | 11 → 13 | **yes** — fully inside |
| 10 → 14 | 08 → 20 | **yes** — fully contains |
| 10 → 14 | 05 → 10 | no — ends as the other starts |

Because dates are zero-padded ISO-8601 strings, `<` on strings is equivalent to
`<` on calendar dates, so no parsing is needed on this hot path.

### Price calculation

```
nights    = countNights(checkIn, checkOut)          // exclusive checkOut
totalCost = round(pricePerNight × nights, 2)
```

The estimate returned by `book_property` is **advisory**. `confirm_booking`
recalculates from the property's *current* price, so a host who changes the
rate between the two calls is honoured.

---

## B8. Concurrency guarantees

A gRPC server handles every call on its own strand, so the four stores are
shared mutable state. The guarantee rests on three mechanisms:

**1. Compiler-enforced locking.** Every store is declared `isolated`:

```ballerina
isolated map<Property> propertyStore = {};
isolated map<Booking>  bookingStore  = {};
```

Ballerina then **refuses to compile** any access that is not inside a `lock`
block. This is not a convention — it is a type-system guarantee.

**2. No references escape.** Values are `clone()`d on the way in and on the way
out, so no caller can hold a live pointer into a store and mutate it behind
the lock's back.

**3. Whole critical sections, not individual operations.** The dangerous
pattern is a read-modify-write split across several locks:

```
   Guest A: check availability ──┐
   Guest B: check availability ──┤  both see "free"
   Guest A: write CONFIRMED    ──┤
   Guest B: write CONFIRMED    ──┘  double booking
```

`confirmBookingAtomic` closes that window by doing the entire sequence —
ownership check, availability re-check, overlap scan, price calculation, state
transition, cart clearing — inside **one** `lock`:

```ballerina
public isolated function confirmBookingAtomic(string bookingId, string guestId)
        returns Booking|error {
    lock {
        // 1 ownership · 2 availability · 3 overlap · 4 price · 5 write · 6 cart
    }
}
```

Whichever strand acquires the lock first wins; the second sees the freshly
written `CONFIRMED` row and is rejected with the overlap message.

The same discipline applies in Question 1 — `insertAsset`, `saveAsset` and
`deleteAssetRow` each run wholly inside a `lock` on an `isolated` table.
