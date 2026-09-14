import ballerina/test;

function testAsset(string suffix) returns Asset {
    return {
        assetTag: "TEST-" + suffix,
        name: "Test laptop",
        institution: "Test Institution",
        site: "Test Campus",
        dateAcquired: "2024-01-10"
    };
}

@test:Config {}
function testAssetCrudAndFilters() returns error? {
    Asset created = check createAsset(testAsset("CRUD"));
    test:assertTrue(createAsset(created) is ConflictError);
    Asset updated = check updateAsset(created.assetTag, {name: "Updated laptop"});
    test:assertEquals(updated.name, "Updated laptop");
    test:assertEquals(updated.site, "Test Campus");
    Asset[] matches = searchAssets("Updated laptop", "test institution", "test campus", AVAILABLE);
    test:assertEquals(matches.length(), 1);
    _ = check deleteAsset(created.assetTag);
    test:assertTrue(getAsset(created.assetTag) is NotFoundError);
}

@test:Config {}
function testInstitutionRegistrationAndWithdrawal() returns error? {
    Institution registered = check registerInstitution({name: "Standalone Test Institution"});
    test:assertTrue(listInstitutions().indexOf(registered.name) is int);
    test:assertTrue(registerInstitution({name: "standalone test institution"}) is ConflictError);
    string[] removed = check removeInstitution(registered.name);
    test:assertEquals(removed.length(), 0);
    test:assertTrue(listInstitutions().indexOf(registered.name) is ());
}

@test:Config {}
function testLoanReturnAndStatusProtection() returns error? {
    Asset created = check createAsset(testAsset("LOAN"));
    Asset issued = check loanAsset(created.assetTag, {borrower: "Test Borrower"});
    test:assertEquals(issued.status, LOANED_OUT);
    test:assertTrue(loanAsset(created.assetTag, {borrower: "Second Borrower"}) is ConflictError);
    test:assertTrue(updateAsset(created.assetTag, {status: AVAILABLE}) is ConflictError);
    test:assertTrue(deleteAsset(created.assetTag) is ConflictError);
    test:assertTrue(removeInstitution(created.institution) is ConflictError);
    Asset returned = check returnAsset(created.assetTag, {});
    test:assertEquals(returned.status, AVAILABLE);
    test:assertFalse(loanHistory(created.assetTag)[0].active);
    test:assertTrue(returnAsset(created.assetTag, {}) is ConflictError);
    _ = check deleteAsset(created.assetTag);
}

@test:Config {}
function testScheduleModificationAndBookingConflicts() returns error? {
    Asset created = check createAsset(testAsset("SCHEDULE"));
    string tomorrow = check addDays(today(), 1);
    string nextWeek = check addDays(today(), 7);
    _ = check addSchedule(created.assetTag, {scheduleId: "SERVICE", dueDate: today()});
    Asset updated = check updateSchedule(created.assetTag, "SERVICE", {dueDate: nextWeek, description: "Rescheduled"});
    test:assertEquals(updated.schedules[0].dueDate, nextWeek);
    test:assertEquals(updated.schedules[0].'type, MAINTENANCE);
    _ = check addSchedule(created.assetTag, {scheduleId: "ROOM", 'type: BOOKING, dueDate: tomorrow});
    test:assertTrue(updateSchedule(created.assetTag, "SERVICE", {'type: BOOKING, dueDate: tomorrow}) is ConflictError);
    test:assertTrue(updateSchedule(created.assetTag, "SERVICE", {dueDate: "2026-02-30"}) is ValidationError);
    test:assertTrue(updateSchedule(created.assetTag, "MISSING", {dueDate: today()}) is NotFoundError);
    test:assertTrue(loanAsset(created.assetTag, {borrower: "Test Guest", spaceBooking: true, dueDate: nextWeek}) is ConflictError);
    _ = check removeSchedule(created.assetTag, "ROOM");
    Asset booked = check loanAsset(created.assetTag, {borrower: "Test Guest", spaceBooking: true, dueDate: tomorrow});
    test:assertEquals(booked.status, OCCUPIED);
    test:assertTrue(addSchedule(created.assetTag, {'type: BOOKING, dueDate: tomorrow}) is ConflictError);
    _ = check returnAsset(created.assetTag, {});
    _ = check deleteAsset(created.assetTag);
}

@test:Config {}
function testWorkOrderTaskLifecycle() returns error? {
    Asset created = check createAsset(testAsset("WORKORDER"));
    Asset opened = check createWorkOrder(created.assetTag, {
        orderId: "REPAIR", description: "Broken screen",
        tasks: [{taskId: "SCREEN", description: "Replace screen"}]
    });
    test:assertEquals(opened.status, UNDER_MAINTENANCE);
    test:assertTrue(loanAsset(created.assetTag, {borrower: "Test Borrower"}) is ConflictError);
    Asset closed = check updateWorkOrder(created.assetTag, "REPAIR", {
        status: CLOSED, tasks: [{taskId: "SCREEN", description: "Replace screen", completed: true}]
    });
    test:assertTrue(closed.workOrders[0].tasks[0].completed);
    test:assertEquals(closed.status, AVAILABLE);
    Asset reopened = check updateWorkOrder(created.assetTag, "REPAIR", {status: IN_PROGRESS});
    test:assertEquals(reopened.status, UNDER_MAINTENANCE);
    _ = check deleteWorkOrder(created.assetTag, "REPAIR");
    _ = check deleteAsset(created.assetTag);
}

@test:Config {}
function testFaultReportedWhileOnLoan() returns error? {
    Asset created = check createAsset(testAsset("RETURNFAULT"));
    _ = check loanAsset(created.assetTag, {borrower: "Test Borrower"});
    _ = check createWorkOrder(created.assetTag, {description: "Fault reported by borrower"});
    Asset returned = check returnAsset(created.assetTag, {});
    test:assertEquals(returned.status, UNDER_MAINTENANCE);
    test:assertTrue(selectActiveLoan(created.assetTag) is ());
    _ = check deleteAsset(created.assetTag);
}

@test:Config {}
function testConcurrentLoanAttempts() returns error? {
    Asset created = check createAsset(testAsset("CONCURRENT"));
    future<Asset|AppError>[] attempts = [];
    foreach int i in 0 ..< 32 {
        future<Asset|AppError> attempt = start loanAsset(created.assetTag, {borrower: string `Borrower ${i}`});
        attempts.push(attempt);
    }
    int accepted = 0;
    foreach future<Asset|AppError> attempt in attempts {
        Asset|AppError result = wait attempt;
        if result is Asset {
            accepted += 1;
        }
    }
    test:assertEquals(accepted, 1, "Only one borrower may receive an available asset.");
    test:assertEquals(loanHistory(created.assetTag).length(), 1);
    _ = check returnAsset(created.assetTag, {});
    _ = check deleteAsset(created.assetTag);
}

@test:Config {}
function testNestedPayloadValidation() returns error? {
    Asset invalid = testAsset("INVALID");
    invalid.workOrders = [{orderId: "BAD", description: "Bad task", tasks: [{taskId: "", description: ""}]}];
    test:assertTrue(createAsset(invalid) is ValidationError);
    invalid.workOrders = [];
    invalid.schedules = [
        {scheduleId: "ONE", 'type: BOOKING, dueDate: today()},
        {scheduleId: "TWO", 'type: BOOKING, dueDate: today()}
    ];
    test:assertTrue(createAsset(invalid) is ValidationError);
    invalid.schedules = [];
    invalid.dateAcquired = "2026-02-30";
    test:assertTrue(createAsset(invalid) is ValidationError);
}

@test:Config {}
function testComponentsAndOverdueFiltering() returns error? {
    Asset created = check createAsset(testAsset("OVERDUE"));
    Asset equipped = check addComponent(created.assetTag, {compId: "BATTERY", name: "Battery"});
    test:assertEquals(equipped.components.length(), 1);
    test:assertTrue(addComponent(created.assetTag, {compId: "BATTERY", name: "Duplicate"}) is ConflictError);
    string yesterday = check addDays(today(), -1);
    _ = check addSchedule(created.assetTag, {scheduleId: "PAST", dueDate: yesterday});
    _ = check addSchedule(created.assetTag, {scheduleId: "TODAY", dueDate: today()});
    OverdueSchedule[] rows = check overdueSchedules("Test Institution", "Test Campus");
    test:assertEquals(rows.length(), 1);
    test:assertEquals(rows[0].daysOverdue, 1);
    Asset detached = check removeComponent(created.assetTag, "BATTERY");
    test:assertEquals(detached.components.length(), 0);
    _ = check deleteAsset(created.assetTag);
}
