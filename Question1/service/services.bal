// ============================================================================
//  DSA612S - Assignment 1 - Question 1
//  Distributed Library and Resource Management System
//  ---------------------------------------------------------------------------
//  services.bal
//  ---------------------------------------------------------------------------
//  The *business logic layer*. Everything in this file is transport agnostic:
//  no `http` import appears anywhere below. That separation is what lets the
//  same rules be reused from a future gRPC or GraphQL front end, and it makes
//  the rules unit-testable without spinning up a listener.
//
//  Responsibilities:
//    * Enforce domain invariants (an asset that is out cannot be loaned again,
//      a disposed asset cannot be serviced, identifiers must stay unique).
//    * Generate identifiers for nested resources when the caller omits them.
//    * Compose the read models the client needs (overdue report, summary).
//
//  Every function returns either the value it produced, or one of the four
//  `AppError` subtypes, which `util.bal` later maps onto an HTTP status code.
// ============================================================================

// ============================================================================
//  SECTION 1 - ASSET CRUD
// ============================================================================

# Creates and stores a brand new asset.
#
# + asset - The candidate asset, exactly as supplied by the client.
# + return - The stored asset, a `ValidationError` when the payload is invalid,
#            or a `ConflictError` when the `assetTag` is already taken.
public isolated function createAsset(Asset asset) returns Asset|AppError {
    // 1. Structural and semantic validation of the whole aggregate.
    check validateAsset(asset);

    // 2. Normalise the key so that lookups behave predictably. Tags are
    //    treated as case sensitive but never carry stray whitespace.
    Asset normalised = {
        assetTag: asset.assetTag.trim(),
        name: asset.name.trim(),
        description: asset.description,
        institution: asset.institution.trim(),
        site: asset.site.trim(),
        status: asset.status,
        dateAcquired: asset.dateAcquired.trim(),
        components: asset.components.clone(),
        schedules: asset.schedules.clone(),
        workOrders: asset.workOrders.clone()
    };

    // 3. Hand off to the persistence layer, which enforces key uniqueness.
    return check insertAsset(normalised);
}

# Reads every asset held by the ministry.
#
# + return - A snapshot of all assets ordered by `assetTag`.
public isolated function listAssets() returns Asset[] {
    return selectAllAssets();
}

# Reads a single asset.
#
# + assetTag - The primary key to look up.
# + return - The asset, or a `NotFoundError`.
public isolated function getAsset(string assetTag) returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    return check selectAsset(assetTag.trim());
}

# Applies a partial update to an existing asset.
#
# Only the fields present in `update` are changed; everything else is carried
# over from the stored value. The whole result is re-validated before it is
# written back, so a partial update can never leave the store inconsistent.
#
# + assetTag - The asset to modify.
# + update - The fields to change.
# + return - The updated asset, or a `ValidationError`, `NotFoundError` or
#            `ConflictError`.
public isolated function updateAsset(string assetTag, AssetUpdate update) returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    Asset current = check selectAsset(assetTag.trim());

    AssetStatus newStatus = update?.status ?: current.status;

    // Domain rule: an asset that is physically in someone else's hands may not
    // be written off. It has to be returned first.
    if newStatus == DISPOSED && selectActiveLoan(current.assetTag) is LoanRecord {
        return error ConflictError(
            string `Asset '${current.assetTag}' is currently on loan and cannot be marked DISPOSED. ` +
            string `Return it first via POST /assets/${current.assetTag}/return.`);
    }

    Asset merged = {
        assetTag: current.assetTag,
        name: (update?.name ?: current.name).trim(),
        description: update?.description ?: current.description,
        institution: (update?.institution ?: current.institution).trim(),
        site: (update?.site ?: current.site).trim(),
        status: newStatus,
        dateAcquired: (update?.dateAcquired ?: current.dateAcquired).trim(),
        components: update?.components ?: current.components,
        schedules: update?.schedules ?: current.schedules,
        workOrders: update?.workOrders ?: current.workOrders
    };

    check validateAsset(merged);
    return check saveAsset(merged);
}

# Permanently removes an asset.
#
# + assetTag - The asset to remove.
# + return - The removed asset, or a `NotFoundError` / `ConflictError`.
public isolated function deleteAsset(string assetTag) returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    string tag = assetTag.trim();

    // Read first so we can enforce the "not while it is out" rule before we
    // destroy anything.
    Asset current = check selectAsset(tag);
    if current.status == LOANED_OUT || current.status == OCCUPIED {
        return error ConflictError(
            string `Asset '${tag}' is currently ${current.status} and cannot be deleted. ` +
            string `Return or release it first.`);
    }
    return check deleteAssetRow(tag);
}

// ============================================================================
//  SECTION 2 - FILTERED VIEWS
// ============================================================================

# Lists every asset owned by one institution.
#
# + institution - The institution name, matched case insensitively.
# + return - The matching assets, or a `ValidationError` for a blank name.
public isolated function listByInstitution(string institution) returns Asset[]|AppError {
    check requireNonBlank(institution, "institution");
    return selectByInstitution(institution);
}

# Lists every asset located at one campus / site.
#
# + site - The site name, matched case insensitively.
# + return - The matching assets, or a `ValidationError` for a blank name.
public isolated function listBySite(string site) returns Asset[]|AppError {
    check requireNonBlank(site, "site");
    return selectBySite(site);
}

# Free-text search across the whole catalogue, with optional structured
# filters layered on top. Backs both the `q` parameter of `GET /assets` and
# the "Search Asset" option of the command line client.
#
# + query - Case insensitive substring matched against tag, name, description,
#           institution and site. `()` or blank matches everything.
# + institution - Optional exact (case insensitive) institution filter.
# + site - Optional exact (case insensitive) site filter.
# + status - Optional status filter.
# + return - The matching assets ordered by `assetTag`.
public isolated function searchAssets(string? query = (), string? institution = (),
        string? site = (), AssetStatus? status = ()) returns Asset[] {

    string needle = (query ?: "").trim().toLowerAscii();
    string instNeedle = (institution ?: "").trim().toLowerAscii();
    string siteNeedle = (site ?: "").trim().toLowerAscii();

    Asset[] all = selectAllAssets();
    Asset[] results = [];

    foreach Asset a in all {
        if instNeedle.length() > 0 && a.institution.trim().toLowerAscii() != instNeedle {
            continue;
        }
        if siteNeedle.length() > 0 && a.site.trim().toLowerAscii() != siteNeedle {
            continue;
        }
        if status is AssetStatus && a.status != status {
            continue;
        }
        if needle.length() > 0 {
            string haystack = string `${a.assetTag} ${a.name} ${a.description} ` +
                string `${a.institution} ${a.site}`;
            if !haystack.toLowerAscii().includes(needle) {
                continue;
            }
        }
        results.push(a);
    }
    return results;
}

# The distinct institutions currently represented in the listing.
#
# + return - A sorted list of institution names.
public isolated function listInstitutions() returns string[] {
    return selectDistinctInstitutions();
}

# The distinct campuses / sites, optionally narrowed to one institution.
#
# + institution - The institution to narrow by, or `()` for all of them.
# + return - A sorted list of site names.
public isolated function listSites(string? institution = ()) returns string[] {
    return selectDistinctSites(institution);
}


# Registers an institution so that it appears in the listing before any of its
# assets have been captured. Without this an institution could only enter the
# listing as a side effect of creating an asset, which is the wrong way round
# for a ministry that accredits the institution first.
#
# + request - The submitted name and optional description.
# + return - The stored institution, or an `AppError`.
public isolated function registerInstitution(InstitutionRequest request)
        returns Institution|AppError {
    check requireNonBlank(request.name, "name");
    check requireMaxLength(request.name, "name", 200);
    check requireMaxLength(request.description, "description", 500);

    string name = request.name.trim();

    // An institution already implied by an asset is in the listing whether or
    // not it has a registry row, so registering it again would show a
    // duplicate. The merged listing is therefore the thing to check against.
    string needle = name.toLowerAscii();
    foreach string existing in listInstitutions() {
        if existing.trim().toLowerAscii() == needle {
            return error ConflictError(
                string `Institution '${name}' is already in the listing.`);
        }
    }

    Institution institution = {
        name: name,
        description: request.description.trim(),
        registeredOn: today()
    };
    return insertInstitution(institution);
}

# Withdraws an entire institution from the listing, deleting all of its assets
# and its registry row. Refuses to run while any of those assets is still out
# on loan.
#
# + institution - The institution to withdraw.
# + return - The tags that were removed, or an `AppError`.
public isolated function removeInstitution(string institution) returns string[]|AppError {
    check requireNonBlank(institution, "institution");
    Asset[] owned = selectByInstitution(institution);

    // An institution registered ahead of its assets owns nothing yet, but is
    // still in the listing and so must still be removable.
    boolean registered = institutionExists(institution);
    if owned.length() == 0 && !registered {
        return error NotFoundError(
            string `No institution named '${institution}' is present in the listing.`);
    }
    foreach Asset a in owned {
        if a.status == LOANED_OUT || a.status == OCCUPIED {
            return error ConflictError(
                string `Institution '${institution}' still has asset '${a.assetTag}' in status ` +
                string `${a.status}. All assets must be returned before the institution can be removed.`);
        }
    }
    _ = deleteInstitutionRow(institution);
    return deleteByInstitution(institution);
}

// ============================================================================
//  SECTION 3 - MAINTENANCE AND OVERDUE REPORTING
// ============================================================================

# Builds the overdue report: every schedule entry whose due date lies in the
# past, flattened together with its parent asset.
#
# Disposed assets are skipped - there is no point chasing maintenance on an
# asset that has been written off. Room bookings are also skipped by default
# because a booking in the past is simply a booking that has happened, not an
# outstanding job; pass `includeBookings = true` to see them anyway.
#
# + institution - Optional institution filter.
# + site - Optional campus / site filter.
# + includeBookings - Whether to include `BOOKING` type schedules.
# + return - The overdue rows, most overdue first, or an `AppError`.
public isolated function overdueSchedules(string? institution = (), string? site = (),
        boolean includeBookings = false) returns OverdueSchedule[]|AppError {

    Asset[] candidates;
    if institution is string && institution.trim().length() > 0 {
        candidates = selectByInstitution(institution);
    } else if site is string && site.trim().length() > 0 {
        candidates = selectBySite(site);
    } else {
        candidates = selectAllAssets();
    }

    // When both filters are supplied, narrow the first result set by the other.
    if institution is string && institution.trim().length() > 0
            && site is string && site.trim().length() > 0 {
        string siteNeedle = site.trim().toLowerAscii();
        candidates = from Asset a in candidates
            where a.site.trim().toLowerAscii() == siteNeedle
            select a;
    }

    string todayIso = today();
    OverdueSchedule[] report = [];

    foreach Asset a in candidates {
        // A written off asset is out of scope for maintenance chasing.
        if a.status == DISPOSED {
            continue;
        }
        foreach Schedule s in a.schedules {
            if s.'type == BOOKING && !includeBookings {
                continue;
            }
            if !isOverdue(s.dueDate) {
                continue;
            }
            int|ValidationError elapsed = daysBetween(s.dueDate, todayIso);
            if elapsed is ValidationError {
                // A malformed stored date must not sink the whole report, so
                // it is reported with a sentinel of -1 rather than thrown.
                report.push({
                    assetTag: a.assetTag,
                    assetName: a.name,
                    institution: a.institution,
                    site: a.site,
                    status: a.status,
                    scheduleId: s.scheduleId,
                    scheduleType: s.'type,
                    dueDate: s.dueDate,
                    description: s.description,
                    daysOverdue: -1
                });
                continue;
            }
            report.push({
                assetTag: a.assetTag,
                assetName: a.name,
                institution: a.institution,
                site: a.site,
                status: a.status,
                scheduleId: s.scheduleId,
                scheduleType: s.'type,
                dueDate: s.dueDate,
                description: s.description,
                daysOverdue: elapsed
            });
        }
    }

    // Most overdue first: that is the order a maintenance officer wants.
    return from OverdueSchedule row in report
        order by row.daysOverdue descending
        select row;
}

# A compact set of counters used by the web dashboard's summary tiles.
#
# + return - A JSON friendly map of headline figures.
public isolated function dashboardSummary() returns map<json> {
    OverdueSchedule[]|AppError overdue = overdueSchedules();
    int overdueCount = overdue is OverdueSchedule[] ? overdue.length() : 0;
    map<int> byStatus = countByStatus();
    return {
        "totalAssets": countAssets(),
        "institutions": listInstitutions().length(),
        "sites": listSites().length(),
        "overdueSchedules": overdueCount,
        "activeLoans": (from LoanRecord l in selectLoans()
            where l.active
            select l).length(),
        "byStatus": byStatus.toJson(),
        "generatedAt": currentTimestamp()
    };
}

// ============================================================================
//  SECTION 4 - LOANING AND RETURNING
// ============================================================================

# Loans an asset to a borrower, or books a physical space.
#
# Domain rules enforced here:
#   * The asset must exist.
#   * Only an `AVAILABLE` asset can go out.
#   * The due date must be a real date that is not in the past.
#
# + assetTag - The asset to issue.
# + request - Borrower details and the optional return date.
# + return - The asset in its new status, or an `AppError`.
public isolated function loanAsset(string assetTag, LoanRequest request) returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    check requireNonBlank(request.borrower, "borrower");
    check requireMaxLength(request.borrower, "borrower", 120);

    string tag = assetTag.trim();
    Asset current = check selectAsset(tag);

    if current.status != AVAILABLE {
        return error ConflictError(
            string `Asset '${tag}' cannot be loaned because its status is ${current.status}. ` +
            string `Only AVAILABLE assets can be issued.`);
    }

    // Default loan period: two weeks, the standard library circulation term.
    string dueDate;
    string? requestedDue = request?.dueDate;
    if requestedDue is string && requestedDue.trim().length() > 0 {
        _ = check parseDate(requestedDue, "dueDate");
        if requestedDue.trim() < today() {
            return error ValidationError(
                string `Field 'dueDate' cannot be in the past: '${requestedDue}'.`);
        }
        dueDate = requestedDue.trim();
    } else {
        dueDate = check addDays(today(), 14);
    }

    // A room or lab becomes OCCUPIED; a book or laptop becomes LOANED_OUT.
    AssetStatus newStatus = request.spaceBooking ? OCCUPIED : LOANED_OUT;

    Asset updated = current.clone();
    updated.status = newStatus;
    Asset stored = check saveAsset(updated);

    // Write the audit trail entry only after the status change succeeded.
    LoanRecord loan = {
        loanId: generateId("LN"),
        assetTag: tag,
        borrower: request.borrower.trim(),
        loanedOn: today(),
        dueDate: dueDate,
        returnedOn: (),
        active: true
    };
    _ = check insertLoan(loan);

    return stored;
}

# Accepts an asset back from a borrower, or releases a booked space.
#
# + assetTag - The asset being handed back.
# + request - Optional condition notes and the maintenance flag.
# + return - The asset in its new status, or an `AppError`.
public isolated function returnAsset(string assetTag, ReturnRequest request) returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    string tag = assetTag.trim();
    Asset current = check selectAsset(tag);

    if current.status != LOANED_OUT && current.status != OCCUPIED {
        return error ConflictError(
            string `Asset '${tag}' is not currently out; its status is ${current.status}. ` +
            string `Nothing to return.`);
    }

    // A damaged asset goes straight into the maintenance queue instead of back
    // onto the shelf.
    Asset updated = current.clone();
    updated.status = request.sendForMaintenance ? UNDER_MAINTENANCE : AVAILABLE;
    Asset stored = check saveAsset(updated);

    // Close the audit trail entry if one is open. A missing entry is tolerated
    // because an asset may have been seeded directly in an "out" status.
    LoanRecord? active = selectActiveLoan(tag);
    if active is LoanRecord {
        _ = check closeLoan(active.loanId, today());
    }

    // If the borrower reported damage, raise a work order automatically so the
    // fault is never lost.
    if request.sendForMaintenance {
        string notes = request.notes.trim();
        WorkOrderRequest auto = {
            status: OPEN,
            description: notes.length() > 0
                ? string `Damage reported on return: ${notes}`
                : "Asset returned in a damaged condition; inspection required.",
            tasks: [{description: "Inspect the asset and quantify the damage."}]
        };
        Asset|AppError withOrder = createWorkOrder(tag, auto);
        if withOrder is Asset {
            return withOrder;
        }
    }
    return stored;
}

# The loan history, newest first.
#
# + assetTag - Narrow to one asset, or `()` for the whole ministry.
# + return - The matching loan records.
public isolated function loanHistory(string? assetTag = ()) returns LoanRecord[] {
    return selectLoans(assetTag);
}

// ============================================================================
//  SECTION 5 - COMPONENT MANAGEMENT
// ============================================================================

# Attaches a new component to an asset.
#
# + assetTag - The parent asset.
# + request - The component to add; `compId` is generated when omitted.
# + return - The parent asset with the component attached, or an `AppError`.
public isolated function addComponent(string assetTag, ComponentRequest request) returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    check requireNonBlank(request.name, "name");
    check requireMaxLength(request.name, "name", 200);

    string tag = assetTag.trim();
    Asset current = check selectAsset(tag);

    if current.status == DISPOSED {
        return error ConflictError(
            string `Asset '${tag}' has been DISPOSED; components can no longer be added.`);
    }

    string compId = (request?.compId ?: "").trim();
    if compId.length() == 0 {
        compId = generateId("C");
    }

    // Guard against a client re-using an existing component id.
    foreach Component existing in current.components {
        if existing.compId == compId {
            return error ConflictError(
                string `Component '${compId}' already exists on asset '${tag}'.`);
        }
    }

    Component component = {
        compId: compId,
        name: request.name.trim(),
        description: request.description
    };

    Asset updated = current.clone();
    updated.components.push(component);
    return check saveAsset(updated);
}

# Detaches a component from an asset.
#
# + assetTag - The parent asset.
# + componentId - The component to remove.
# + return - The parent asset without the component, or an `AppError`.
public isolated function removeComponent(string assetTag, string componentId) returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    check requireNonBlank(componentId, "componentId");

    string tag = assetTag.trim();
    string compId = componentId.trim();
    Asset current = check selectAsset(tag);

    Component[] remaining = from Component c in current.components
        where c.compId != compId
        select c;

    if remaining.length() == current.components.length() {
        return error NotFoundError(
            string `No component with id '${compId}' on asset '${tag}'.`);
    }

    Asset updated = current.clone();
    updated.components = remaining;
    return check saveAsset(updated);
}

// ============================================================================
//  SECTION 6 - SCHEDULE MANAGEMENT
// ============================================================================

# Adds a maintenance, servicing, inspection or booking schedule to an asset.
#
# + assetTag - The parent asset.
# + request - The schedule to add; `scheduleId` is generated when omitted.
# + return - The parent asset with the schedule attached, or an `AppError`.
public isolated function addSchedule(string assetTag, ScheduleRequest request) returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    check requireNonBlank(request.dueDate, "dueDate");
    _ = check parseDate(request.dueDate, "dueDate");
    check requireMaxLength(request.description, "description", 500);

    string tag = assetTag.trim();
    Asset current = check selectAsset(tag);

    if current.status == DISPOSED {
        return error ConflictError(
            string `Asset '${tag}' has been DISPOSED; no further schedules can be created.`);
    }

    string scheduleId = (request?.scheduleId ?: "").trim();
    if scheduleId.length() == 0 {
        scheduleId = generateId("SCH");
    }

    foreach Schedule existing in current.schedules {
        if existing.scheduleId == scheduleId {
            return error ConflictError(
                string `Schedule '${scheduleId}' already exists on asset '${tag}'.`);
        }
    }

    // A booking must not collide with another booking on the same day; two
    // groups cannot occupy one meeting room at once.
    if request.'type == BOOKING {
        foreach Schedule existing in current.schedules {
            if existing.'type == BOOKING && existing.dueDate.trim() == request.dueDate.trim() {
                return error ConflictError(
                    string `Asset '${tag}' is already booked on ${request.dueDate} ` +
                    string `by schedule '${existing.scheduleId}'.`);
            }
        }
    }

    Schedule schedule = {
        scheduleId: scheduleId,
        'type: request.'type,
        dueDate: request.dueDate.trim(),
        description: request.description
    };

    Asset updated = current.clone();
    updated.schedules.push(schedule);
    return check saveAsset(updated);
}

# Removes a schedule entry from an asset.
#
# + assetTag - The parent asset.
# + scheduleId - The schedule to remove.
# + return - The parent asset without the schedule, or an `AppError`.
public isolated function removeSchedule(string assetTag, string scheduleId) returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    check requireNonBlank(scheduleId, "scheduleId");

    string tag = assetTag.trim();
    string schedId = scheduleId.trim();
    Asset current = check selectAsset(tag);

    Schedule[] remaining = from Schedule s in current.schedules
        where s.scheduleId != schedId
        select s;

    if remaining.length() == current.schedules.length() {
        return error NotFoundError(
            string `No schedule with id '${schedId}' on asset '${tag}'.`);
    }

    Asset updated = current.clone();
    updated.schedules = remaining;
    return check saveAsset(updated);
}

// ============================================================================
//  SECTION 7 - WORK ORDER AND TASK MANAGEMENT
// ============================================================================

# Converts the task DTOs of a request into stored `Task` values, generating
# identifiers where the client did not supply them.
#
# + requests - The incoming task DTOs.
# + return - The materialised tasks, or a `ValidationError`.
isolated function materialiseTasks(TaskRequest[] requests) returns Task[]|ValidationError {
    Task[] tasks = [];
    map<boolean> seen = {};
    foreach TaskRequest t in requests {
        check requireNonBlank(t.description, "tasks[].description");
        string taskId = (t?.taskId ?: "").trim();
        if taskId.length() == 0 {
            taskId = generateId("T");
        }
        if seen.hasKey(taskId) {
            return error ValidationError(string `Duplicate taskId '${taskId}' in the task list.`);
        }
        seen[taskId] = true;
        tasks.push({taskId: taskId, description: t.description.trim(), completed: t.completed});
    }
    return tasks;
}

# Opens a work order against a faulty asset.
#
# + assetTag - The parent asset.
# + request - The work order to create; ids are generated when omitted.
# + return - The parent asset with the work order attached, or an `AppError`.
public isolated function createWorkOrder(string assetTag, WorkOrderRequest request) returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    check requireNonBlank(request.description, "description");
    check requireMaxLength(request.description, "description", 500);

    string tag = assetTag.trim();
    Asset current = check selectAsset(tag);

    if current.status == DISPOSED {
        return error ConflictError(
            string `Asset '${tag}' has been DISPOSED; no further work orders can be raised.`);
    }

    string orderId = (request?.orderId ?: "").trim();
    if orderId.length() == 0 {
        orderId = generateId("WO");
    }

    foreach WorkOrder existing in current.workOrders {
        if existing.orderId == orderId {
            return error ConflictError(
                string `Work order '${orderId}' already exists on asset '${tag}'.`);
        }
    }

    Task[] tasks = check materialiseTasks(request.tasks);

    // NOTE: the variable is called `workOrder`, not `order` - `order` is a
    // reserved word in Ballerina because of the `order by` query clause.
    WorkOrder workOrder = {
        orderId: orderId,
        status: request.status,
        description: request.description.trim(),
        tasks: tasks
    };

    Asset updated = current.clone();
    updated.workOrders.push(workOrder);

    // Raising an open job on an available asset takes it out of circulation so
    // that nobody loans a resource that is known to be faulty.
    if (workOrder.status == OPEN || workOrder.status == IN_PROGRESS) && updated.status == AVAILABLE {
        updated.status = UNDER_MAINTENANCE;
    }

    return check saveAsset(updated);
}

# Updates an existing work order, including its sub-tasks.
#
# + assetTag - The parent asset.
# + orderId - The work order to modify.
# + update - The fields to change.
# + return - The parent asset with the modified work order, or an `AppError`.
public isolated function updateWorkOrder(string assetTag, string orderId, WorkOrderUpdate update)
        returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    check requireNonBlank(orderId, "orderId");

    string tag = assetTag.trim();
    string woId = orderId.trim();
    Asset current = check selectAsset(tag);

    // `-1` is used as the "not found" sentinel so that the variable keeps a
    // plain `int` type and needs no narrowing after the loop.
    int index = -1;
    foreach int i in 0 ..< current.workOrders.length() {
        if current.workOrders[i].orderId == woId {
            index = i;
            break;
        }
    }
    if index < 0 {
        return error NotFoundError(string `No work order with id '${woId}' on asset '${tag}'.`);
    }

    WorkOrder existing = current.workOrders[index];
    string newDescription = (update?.description ?: existing.description).trim();
    check requireNonBlank(newDescription, "description");

    TaskRequest[]? incomingTasks = update?.tasks;
    Task[] newTasks;
    if incomingTasks is TaskRequest[] {
        newTasks = check materialiseTasks(incomingTasks);
    } else {
        newTasks = existing.tasks;
    }

    WorkOrder modified = {
        orderId: existing.orderId,
        status: update?.status ?: existing.status,
        description: newDescription,
        tasks: newTasks
    };

    Asset updated = current.clone();
    updated.workOrders[index] = modified;

    // Once every job on an asset is closed or cancelled, and the asset was
    // only under maintenance because of those jobs, put it back into service.
    if updated.status == UNDER_MAINTENANCE && !hasOpenWorkOrder(updated) {
        updated.status = AVAILABLE;
    }

    return check saveAsset(updated);
}

# Deletes a work order from an asset.
#
# + assetTag - The parent asset.
# + orderId - The work order to delete.
# + return - The parent asset without the work order, or an `AppError`.
public isolated function deleteWorkOrder(string assetTag, string orderId) returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    check requireNonBlank(orderId, "orderId");

    string tag = assetTag.trim();
    string woId = orderId.trim();
    Asset current = check selectAsset(tag);

    WorkOrder[] remaining = from WorkOrder w in current.workOrders
        where w.orderId != woId
        select w;

    if remaining.length() == current.workOrders.length() {
        return error NotFoundError(string `No work order with id '${woId}' on asset '${tag}'.`);
    }

    Asset updated = current.clone();
    updated.workOrders = remaining;

    if updated.status == UNDER_MAINTENANCE && !hasOpenWorkOrder(updated) {
        updated.status = AVAILABLE;
    }

    return check saveAsset(updated);
}

# Tests whether an asset still has at least one unfinished work order.
#
# + asset - The asset to inspect.
# + return - `true` when an OPEN or IN_PROGRESS job remains.
isolated function hasOpenWorkOrder(Asset asset) returns boolean {
    foreach WorkOrder w in asset.workOrders {
        if w.status == OPEN || w.status == IN_PROGRESS {
            return true;
        }
    }
    return false;
}
