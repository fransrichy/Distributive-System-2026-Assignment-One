public isolated function createAsset(Asset asset) returns Asset|AppError {
    check validateAsset(asset);
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
    if normalised.status == AVAILABLE && hasOpenWorkOrder(normalised) {
        normalised.status = UNDER_MAINTENANCE;
    }
    return check insertAsset(normalised);
}

public isolated function listAssets() returns Asset[] {
    return selectAllAssets();
}

public isolated function getAsset(string assetTag) returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    return check selectAsset(assetTag.trim());
}

public isolated function updateAsset(string assetTag, AssetUpdate update) returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    Asset current = check selectAsset(assetTag.trim());

    AssetStatus newStatus = update?.status ?: current.status;
    if newStatus != current.status && (selectActiveLoan(current.assetTag) is LoanRecord
            || current.status == LOANED_OUT || current.status == OCCUPIED
            || newStatus == LOANED_OUT || newStatus == OCCUPIED) {
        return error ConflictError(
            "Use the loan or return endpoint to change an asset's loan or occupancy status.");
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
    Schedule[]? schedules = update?.schedules;
    if schedules is Schedule[] {
        foreach Schedule schedule in schedules {
            if schedule.'type == BOOKING {
                check checkBookingAgainstLoan(current.assetTag, schedule.dueDate.trim());
            }
        }
    }
    if merged.status == AVAILABLE && hasOpenWorkOrder(merged) {
        merged.status = UNDER_MAINTENANCE;
    }
    return check saveAsset(merged);
}

public isolated function deleteAsset(string assetTag) returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    string tag = assetTag.trim();
    Asset current = check selectAsset(tag);
    if current.status == LOANED_OUT || current.status == OCCUPIED || selectActiveLoan(tag) is LoanRecord {
        return error ConflictError(
            string `Asset '${tag}' is currently ${current.status} and cannot be deleted. ` +
            string `Return or release it first.`);
    }
    return check deleteAssetRow(tag);
}

public isolated function listByInstitution(string institution) returns Asset[]|AppError {
    check requireNonBlank(institution, "institution");
    return selectByInstitution(institution);
}

public isolated function listBySite(string site) returns Asset[]|AppError {
    check requireNonBlank(site, "site");
    return selectBySite(site);
}

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

public isolated function listInstitutions() returns string[] {
    return selectDistinctInstitutions();
}

public isolated function listSites(string? institution = ()) returns string[] {
    return selectDistinctSites(institution);
}

public isolated function registerInstitution(InstitutionRequest request)
        returns Institution|AppError {
    check requireNonBlank(request.name, "name");
    check requireMaxLength(request.name, "name", 200);
    check requireMaxLength(request.description, "description", 500);

    string name = request.name.trim();
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

public isolated function removeInstitution(string institution) returns string[]|AppError {
    check requireNonBlank(institution, "institution");
    Asset[] owned = selectByInstitution(institution);
    boolean registered = institutionExists(institution);
    if owned.length() == 0 && !registered {
        return error NotFoundError(
            string `No institution named '${institution}' is present in the listing.`);
    }
    foreach Asset a in owned {
        if a.status == LOANED_OUT || a.status == OCCUPIED || selectActiveLoan(a.assetTag) is LoanRecord {
            return error ConflictError(
                string `Institution '${institution}' still has asset '${a.assetTag}' in status ` +
                string `${a.status}. All assets must be returned before the institution can be removed.`);
        }
    }
    _ = deleteInstitutionRow(institution);
    return deleteByInstitution(institution);
}

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
    return from OverdueSchedule row in report
        order by row.daysOverdue descending
        select row;
}

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

public isolated function loanAsset(string assetTag, LoanRequest request) returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    check requireNonBlank(request.borrower, "borrower");
    check requireMaxLength(request.borrower, "borrower", 120);

    string tag = assetTag.trim();
    Asset current = check selectAsset(tag);

    if current.status != AVAILABLE || selectActiveLoan(tag) is LoanRecord || hasOpenWorkOrder(current) {
        return error ConflictError(
            string `Asset '${tag}' cannot be loaned because its status is ${current.status}. ` +
            string `Only AVAILABLE assets can be issued.`);
    }
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

    foreach Schedule schedule in current.schedules {
        if schedule.'type == BOOKING && schedule.dueDate.trim() >= today()
                && schedule.dueDate.trim() <= dueDate {
            return error ConflictError(
                string `Asset '${tag}' is reserved on ${schedule.dueDate} by schedule '${schedule.scheduleId}'.`);
        }
    }
    AssetStatus newStatus = request.spaceBooking ? OCCUPIED : LOANED_OUT;

    Asset stored = check claimAssetForLoan(tag, newStatus);
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

public isolated function returnAsset(string assetTag, ReturnRequest request) returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    check requireMaxLength(request.notes, "notes", 450);
    string tag = assetTag.trim();
    Asset current = check selectAsset(tag);

    if current.status != LOANED_OUT && current.status != OCCUPIED {
        return error ConflictError(
            string `Asset '${tag}' is not currently out; its status is ${current.status}. ` +
            string `Nothing to return.`);
    }
    Asset updated = current.clone();
    updated.status = request.sendForMaintenance || hasOpenWorkOrder(current) ? UNDER_MAINTENANCE : AVAILABLE;
    Asset stored = check saveAsset(updated);
    LoanRecord? active = selectActiveLoan(tag);
    if active is LoanRecord {
        _ = check closeLoan(active.loanId, today());
    }
    if request.sendForMaintenance {
        string notes = request.notes.trim();
        WorkOrderRequest auto = {
            status: OPEN,
            description: notes.length() > 0
                ? string `Damage reported on return: ${notes}`
                : "Asset returned in a damaged condition; inspection required.",
            tasks: [{description: "Inspect the asset and quantify the damage."}]
        };
        return check createWorkOrder(tag, auto);
    }
    return stored;
}

public isolated function loanHistory(string? assetTag = ()) returns LoanRecord[] {
    return selectLoans(assetTag);
}

public isolated function addComponent(string assetTag, ComponentRequest request) returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    check requireNonBlank(request.name, "name");
    check requireMaxLength(request.name, "name", 200);
    check requireMaxLength(request.description, "description", 500);

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
    if request.'type == BOOKING {
        foreach Schedule existing in current.schedules {
            if existing.'type == BOOKING && existing.dueDate.trim() == request.dueDate.trim() {
                return error ConflictError(
                    string `Asset '${tag}' is already booked on ${request.dueDate} ` +
                    string `by schedule '${existing.scheduleId}'.`);
            }
        }
        check checkBookingAgainstLoan(tag, request.dueDate.trim());
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

public isolated function updateSchedule(string assetTag, string scheduleId, ScheduleUpdate update)
        returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    check requireNonBlank(scheduleId, "scheduleId");
    Asset current = check selectAsset(assetTag.trim());
    if current.status == DISPOSED {
        return error ConflictError("Schedules on a disposed asset cannot be changed.");
    }
    int index = -1;
    foreach int i in 0 ..< current.schedules.length() {
        if current.schedules[i].scheduleId == scheduleId.trim() {
            index = i;
            break;
        }
    }
    if index < 0 {
        return error NotFoundError(string `No schedule with id '${scheduleId}' on asset '${assetTag}'.`);
    }
    Schedule existing = current.schedules[index];
    Schedule modified = {
        scheduleId: existing.scheduleId,
        'type: update?.'type ?: existing.'type,
        dueDate: (update?.dueDate ?: existing.dueDate).trim(),
        description: update?.description ?: existing.description
    };
    _ = check parseDate(modified.dueDate, "dueDate");
    check requireMaxLength(modified.description, "description", 500);
    if modified.'type == BOOKING {
        foreach Schedule other in current.schedules {
            if other.scheduleId != existing.scheduleId && other.'type == BOOKING
                    && other.dueDate.trim() == modified.dueDate {
                return error ConflictError(string `Asset '${assetTag}' is already booked on ${modified.dueDate}.`);
            }
        }
        check checkBookingAgainstLoan(current.assetTag, modified.dueDate);
    }
    current.schedules[index] = modified;
    return check saveAsset(current);
}

isolated function checkBookingAgainstLoan(string assetTag, string dueDate) returns ConflictError? {
    LoanRecord? active = selectActiveLoan(assetTag);
    if active is LoanRecord && dueDate >= active.loanedOn && dueDate <= active.dueDate {
        return error ConflictError(string `Asset '${assetTag}' is already issued through ${active.dueDate}.`);
    }
    return ();
}

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

isolated function materialiseTasks(TaskRequest[] requests) returns Task[]|ValidationError {
    Task[] tasks = [];
    map<boolean> seen = {};
    foreach TaskRequest t in requests {
        check requireNonBlank(t.description, "tasks[].description");
        check requireMaxLength(t.description, "tasks[].description", 500);
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
    WorkOrder workOrder = {
        orderId: orderId,
        status: request.status,
        description: request.description.trim(),
        tasks: tasks
    };

    Asset updated = current.clone();
    updated.workOrders.push(workOrder);
    if (workOrder.status == OPEN || workOrder.status == IN_PROGRESS) && updated.status == AVAILABLE {
        updated.status = UNDER_MAINTENANCE;
    }

    return check saveAsset(updated);
}

public isolated function updateWorkOrder(string assetTag, string orderId, WorkOrderUpdate update)
        returns Asset|AppError {
    check requireNonBlank(assetTag, "assetTag");
    check requireNonBlank(orderId, "orderId");

    string tag = assetTag.trim();
    string woId = orderId.trim();
    Asset current = check selectAsset(tag);
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
    check requireMaxLength(newDescription, "description", 500);

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

    if current.status == DISPOSED && (modified.status == OPEN || modified.status == IN_PROGRESS) {
        return error ConflictError("A work order on a disposed asset cannot be reopened.");
    }
    if updated.status == AVAILABLE && hasOpenWorkOrder(updated) {
        updated.status = UNDER_MAINTENANCE;
    }
    if updated.status == UNDER_MAINTENANCE && !hasOpenWorkOrder(updated) {
        updated.status = AVAILABLE;
    }

    return check saveAsset(updated);
}

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

isolated function hasOpenWorkOrder(Asset asset) returns boolean {
    foreach WorkOrder w in asset.workOrders {
        if w.status == OPEN || w.status == IN_PROGRESS {
            return true;
        }
    }
    return false;
}
