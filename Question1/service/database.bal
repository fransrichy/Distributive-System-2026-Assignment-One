# Primary in-memory store. `assetTag` is the unique key, exactly as required
# by the assignment brief.
isolated table<Asset> key(assetTag) assetTable = table [];

# Audit trail of every loan and space booking ever made.
isolated table<LoanRecord> key(loanId) loanTable = table [];

# Registry of institutions that have been added to the listing explicitly.
# An institution may also be implied by the assets that reference it; the two
# sources are merged by `selectDistinctInstitutions`.
isolated table<Institution> key(name) institutionTable = table [];

# Tests whether an asset with the given tag is present.
#
# + assetTag - The primary key to probe.
# + return - `true` when the asset exists.
public isolated function assetExists(string assetTag) returns boolean {
    lock {
        return assetTable.hasKey(assetTag);
    }
}

# Inserts a brand new asset.
#
# + asset - The asset to store; its `assetTag` must not already be in use.
# + return - The stored asset, or a `ConflictError` when the tag is taken.
public isolated function insertAsset(Asset asset) returns Asset|ConflictError {
    lock {
        if assetTable.hasKey(asset.assetTag) {
            return error ConflictError(
                string `An asset with tag '${asset.assetTag}' already exists.`);
        }
        assetTable.add(asset.clone());
        return asset.clone();
    }
}

# Reads every asset in the store.
#
# + return - A detached snapshot of all assets, sorted by `assetTag`.
public isolated function selectAllAssets() returns Asset[] {
    lock {
        Asset[] snapshot = from Asset a in assetTable
            order by a.assetTag ascending
            select a;
        return snapshot.clone();
    }
}

# Reads a single asset by its primary key.
#
# + assetTag - The primary key to look up.
# + return - A detached copy of the asset, or a `NotFoundError`.
public isolated function selectAsset(string assetTag) returns Asset|NotFoundError {
    lock {
        Asset? found = assetTable[assetTag];
        if found is () {
            return error NotFoundError(string `No asset found with tag '${assetTag}'.`);
        }
        return found.clone();
    }
}

# Overwrites an existing asset with a modified copy.
#
# The caller is expected to have read the asset first, mutated its own copy,
# and to be writing that copy back. The tag must already exist, otherwise the
# caller has a bug.
#
# + asset - The full replacement value.
# + return - A detached copy of what was stored, or a `NotFoundError`.
public isolated function saveAsset(Asset asset) returns Asset|NotFoundError {
    lock {
        if !assetTable.hasKey(asset.assetTag) {
            return error NotFoundError(string `No asset found with tag '${asset.assetTag}'.`);
        }
        assetTable.put(asset.clone());
        return asset.clone();
    }
}

# Permanently removes an asset from the store.
#
# + assetTag - The primary key to remove.
# + return - A detached copy of the removed asset, or a `NotFoundError`.
public isolated function deleteAssetRow(string assetTag) returns Asset|NotFoundError {
    lock {
        if !assetTable.hasKey(assetTag) {
            return error NotFoundError(string `No asset found with tag '${assetTag}'.`);
        }
        Asset removed = assetTable.remove(assetTag);
        return removed.clone();
    }
}

# Filters assets by owning institution. The comparison is case insensitive and
# ignores surrounding whitespace so that URL supplied values behave sensibly.
#
# + institution - The institution name to match.
# + return - A detached snapshot of the matching assets.
public isolated function selectByInstitution(string institution) returns Asset[] {
    string needle = institution.trim().toLowerAscii();
    lock {
        Asset[] matches = from Asset a in assetTable
            where a.institution.trim().toLowerAscii() == needle
            order by a.assetTag ascending
            select a;
        return matches.clone();
    }
}

# Filters assets by campus / site, case insensitively.
#
# + site - The site name to match.
# + return - A detached snapshot of the matching assets.
public isolated function selectBySite(string site) returns Asset[] {
    string needle = site.trim().toLowerAscii();
    lock {
        Asset[] matches = from Asset a in assetTable
            where a.site.trim().toLowerAscii() == needle
            order by a.assetTag ascending
            select a;
        return matches.clone();
    }
}

# Lists the distinct institutions in the listing: those registered explicitly
# plus those implied by an asset that references them.
# Backs the "manage institutions" requirement in the marking rubric.
#
# + return - A sorted, de-duplicated list of institution names.
public isolated function selectDistinctInstitutions() returns string[] {
    string[] registered = selectRegisteredNames();
    string[] owning = selectOwningNames();

    map<boolean> seen = {};
    string[] names = [];
    foreach string candidate in [...registered, ...owning] {
        string name = candidate.trim();
        if name.length() == 0 {
            continue;
        }
        if !seen.hasKey(name.toLowerAscii()) {
            seen[name.toLowerAscii()] = true;
            names.push(name);
        }
    }
    return names.sort();
}

# The names on the institution registry.
#
# + return - A detached list of registered institution names.
isolated function selectRegisteredNames() returns string[] {
    lock {
        string[] names = from Institution i in institutionTable
            select i.name;
        return names.clone();
    }
}

# The institution named by each asset, duplicates included.
#
# + return - A detached list of the institution on every asset.
isolated function selectOwningNames() returns string[] {
    lock {
        string[] names = from Asset a in assetTable
            select a.institution;
        return names.clone();
    }
}

# Lists the distinct campuses / sites, optionally narrowed to one institution.
#
# + institution - Institution to narrow by, or `()` for every institution.
# + return - A sorted, de-duplicated list of site names.
public isolated function selectDistinctSites(string? institution = ()) returns string[] {
    string? needle = institution is string ? institution.trim().toLowerAscii() : ();
    lock {
        map<boolean> seen = {};
        string[] names = [];
        foreach Asset a in assetTable {
            if needle is string && a.institution.trim().toLowerAscii() != needle {
                continue;
            }
            string name = a.site.trim();
            if !seen.hasKey(name.toLowerAscii()) {
                seen[name.toLowerAscii()] = true;
                names.push(name);
            }
        }
        return names.sort().clone();
    }
}

# Removes every asset belonging to an institution. This supports the
# "add/remove institutions from listings" requirement; the registry row, if the
# institution has one, is dropped by the service layer alongside these assets.
#
# + institution - The institution to withdraw.
# + return - The tags of the assets that were removed.
public isolated function deleteByInstitution(string institution) returns string[] {
    string needle = institution.trim().toLowerAscii();
    lock {
        string[] doomed = from Asset a in assetTable
            where a.institution.trim().toLowerAscii() == needle
            select a.assetTag;
        foreach string tag in doomed {
            _ = assetTable.remove(tag);
        }
        return doomed.clone();
    }
}

# Tests whether an institution is already on the registry. The comparison is
# case-insensitive, matching how institutions are matched everywhere else.
#
# + name - The institution name to probe.
# + return - `true` when a registry row exists under that name.
public isolated function institutionExists(string name) returns boolean {
    string needle = name.trim().toLowerAscii();
    lock {
        foreach Institution i in institutionTable {
            if i.name.trim().toLowerAscii() == needle {
                return true;
            }
        }
        return false;
    }
}

# Registers a brand new institution.
#
# + institution - The institution to store; its name must not already be taken.
# + return - The stored institution, or a `ConflictError` when the name is taken.
public isolated function insertInstitution(Institution institution)
        returns Institution|ConflictError {
    string needle = institution.name.trim().toLowerAscii();
    lock {
        foreach Institution existing in institutionTable {
            if existing.name.trim().toLowerAscii() == needle {
                return error ConflictError(
                    string `Institution '${institution.name}' is already registered.`);
            }
        }
        institutionTable.add(institution.clone());
        return institution.clone();
    }
}

# Deregisters an institution, removing its registry row if it has one. An
# institution that is only implied by its assets has no row, which is not an
# error - the caller decides whether that counts as "not found".
#
# + name - The institution to deregister.
# + return - `true` when a registry row was actually removed.
public isolated function deleteInstitutionRow(string name) returns boolean {
    string needle = name.trim().toLowerAscii();
    lock {
        string[] doomed = from Institution i in institutionTable
            where i.name.trim().toLowerAscii() == needle
            select i.name;
        foreach string key in doomed {
            _ = institutionTable.remove(key);
        }
        return doomed.length() > 0;
    }
}

# Counts assets grouped by status, used by the dashboard summary endpoint.
#
# + return - A map from status name to the number of assets in that status.
public isolated function countByStatus() returns map<int> {
    lock {
        map<int> tally = {};
        foreach Asset a in assetTable {
            string statusName = a.status;
            tally[statusName] = (tally[statusName] ?: 0) + 1;
        }
        return tally.clone();
    }
}

# The total number of assets currently stored.
#
# + return - The row count of the asset table.
public isolated function countAssets() returns int {
    lock {
        return assetTable.length();
    }
}

# Records the start of a loan or space booking.
#
# + loan - The loan record to store.
# + return - A detached copy of the stored record, or a `ConflictError` when
#            the generated loan id has somehow already been used.
public isolated function insertLoan(LoanRecord loan) returns LoanRecord|ConflictError {
    lock {
        if loanTable.hasKey(loan.loanId) {
            return error ConflictError(string `Loan '${loan.loanId}' already exists.`);
        }
        loanTable.add(loan.clone());
        return loan.clone();
    }
}

# Finds the open loan for an asset, if the asset is currently out.
#
# + assetTag - The asset to look up.
# + return - The open loan, or `()` when the asset is not on loan.
public isolated function selectActiveLoan(string assetTag) returns LoanRecord? {
    lock {
        LoanRecord[] open = from LoanRecord l in loanTable
            where l.assetTag == assetTag && l.active
            select l;
        if open.length() == 0 {
            return ();
        }
        return open[0].clone();
    }
}

# Closes an open loan by stamping it with a return date.
#
# + loanId - The loan to close.
# + returnedOn - The ISO-8601 date the asset came back.
# + return - The closed loan, or a `NotFoundError` when the id is unknown.
public isolated function closeLoan(string loanId, string returnedOn) returns LoanRecord|NotFoundError {
    lock {
        LoanRecord? found = loanTable[loanId];
        if found is () {
            return error NotFoundError(string `No loan found with id '${loanId}'.`);
        }
        LoanRecord updated = found.clone();
        updated.active = false;
        updated.returnedOn = returnedOn;
        loanTable.put(updated);
        return updated.clone();
    }
}

# Reads the loan history, newest first, optionally narrowed to one asset.
#
# + assetTag - The asset to narrow by, or `()` for the whole history.
# + return - A detached snapshot of the matching loan records.
public isolated function selectLoans(string? assetTag = ()) returns LoanRecord[] {
    lock {
        LoanRecord[] rows = from LoanRecord l in loanTable
            where assetTag is () || l.assetTag == assetTag
            order by l.loanId descending
            select l;
        return rows.clone();
    }
}

# Populates the store with a realistic cross-campus data set so that the CLI
# client, the web dashboard and the marker all have something to work with the
# moment the server starts.
#
# The seed intentionally contains schedules that are already in the past, so
# that `GET /maintenance/overdue` returns meaningful rows on a fresh start.
#
# + return - The number of assets that were seeded.
public isolated function seedDatabase() returns int {
    string overdueDate = checkpanic addDays(today(), -45);
    string recentlyOverdue = checkpanic addDays(today(), -7);
    string upcoming = checkpanic addDays(today(), 60);
    string soon = checkpanic addDays(today(), 12);

    Asset[] seed = [
        {
            assetTag: "NUST-LIB-3DP-001",
            name: "Pro-Series 3D Printer",
            description: "High-precision laboratory printer for simulation and prototype development.",
            institution: "Namibia University of Science and Technology",
            site: "Main Campus - Innovation Lab",
            status: UNDER_MAINTENANCE,
            dateAcquired: "2024-03-10",
            components: [
                {
                    compId: "C101",
                    name: "High-Torque Stepper Motor",
                    description: "Main motor for X-axis movement."
                },
                {
                    compId: "C102",
                    name: "Heated Print Bed",
                    description: "Borosilicate glass bed with 220C heating element."
                }
            ],
            schedules: [
                {
                    scheduleId: "SCH-882",
                    'type: MAINTENANCE,
                    dueDate: recentlyOverdue,
                    description: "Quarterly calibration and nozzle cleaning."
                }
            ],
            workOrders: [
                {
                    orderId: "WO-554",
                    status: OPEN,
                    description: "Nozzle heat-bed failure",
                    tasks: [
                        {taskId: "T1", description: "Check thermal sensor connectivity.", completed: false},
                        {taskId: "T2", description: "Replace thermistor if resistance is out of range.", completed: false}
                    ]
                }
            ]
        },
        {
            assetTag: "NUST-LIB-LAP-014",
            name: "Dell Latitude 5540 Loan Laptop",
            description: "Student loan laptop issued from the main library circulation desk.",
            institution: "Namibia University of Science and Technology",
            site: "Main Campus - Library Circulation",
            status: AVAILABLE,
            dateAcquired: "2023-11-02",
            components: [
                {compId: "C201", name: "65Wh Battery", description: "Removable lithium-ion battery pack."},
                {compId: "C202", name: "Docking Adapter", description: "USB-C multiport docking adapter."}
            ],
            schedules: [
                {
                    scheduleId: "SCH-901",
                    'type: SERVICING,
                    dueDate: soon,
                    description: "Annual battery health check and OS re-image."
                }
            ],
            workOrders: []
        },
        {
            assetTag: "NUST-LIB-ROOM-002",
            name: "Postgraduate Discussion Room 2",
            description: "Bookable eight seat discussion room with interactive whiteboard.",
            institution: "Namibia University of Science and Technology",
            site: "Main Campus - Library Level 3",
            status: AVAILABLE,
            dateAcquired: "2022-01-15",
            components: [
                {compId: "C301", name: "Interactive Whiteboard", description: "86 inch touch enabled display."}
            ],
            schedules: [
                {
                    scheduleId: "SCH-915",
                    'type: BOOKING,
                    dueDate: upcoming,
                    description: "Reserved for the Faculty of Computing research seminar."
                }
            ],
            workOrders: []
        },
        {
            assetTag: "UNAM-LIB-TC-207",
            name: "HP t640 Thin Client",
            description: "Fixed thin client terminal in the undergraduate computer lab.",
            institution: "University of Namibia",
            site: "Windhoek Campus - Computer Lab B",
            status: UNDER_MAINTENANCE,
            dateAcquired: "2021-07-19",
            components: [
                {compId: "C401", name: "Power Supply Unit", description: "External 65W PSU."}
            ],
            schedules: [
                {
                    scheduleId: "SCH-1002",
                    'type: MAINTENANCE,
                    dueDate: overdueDate,
                    description: "Firmware update and thermal paste replacement."
                },
                {
                    scheduleId: "SCH-1003",
                    'type: INSPECTION,
                    dueDate: upcoming,
                    description: "Annual electrical safety inspection."
                }
            ],
            workOrders: [
                {
                    orderId: "WO-771",
                    status: IN_PROGRESS,
                    description: "Terminal powers on but does not reach the login screen.",
                    tasks: [
                        {taskId: "T1", description: "Replace power supply unit.", completed: true},
                        {taskId: "T2", description: "Re-flash the thin client firmware image.", completed: false}
                    ]
                }
            ]
        },
        {
            assetTag: "UNAM-LIB-BOOK-8891",
            name: "Distributed Systems: Concepts and Design (5th Ed.)",
            description: "Core prescribed textbook for DSA612S, short loan collection.",
            institution: "University of Namibia",
            site: "Windhoek Campus - Short Loan Desk",
            status: AVAILABLE,
            dateAcquired: "2020-02-28",
            components: [],
            schedules: [
                {
                    scheduleId: "SCH-1104",
                    'type: INSPECTION,
                    dueDate: recentlyOverdue,
                    description: "Stock take and binding condition check."
                }
            ],
            workOrders: []
        },
        {
            assetTag: "IUM-LIB-PRN-033",
            name: "Konica Minolta bizhub C300i",
            description: "Multifunction print, copy and scan station for postgraduate students.",
            institution: "International University of Management",
            site: "Dorado Campus - Resource Centre",
            status: AVAILABLE,
            dateAcquired: "2023-05-22",
            components: [
                {compId: "C501", name: "Fuser Unit", description: "Thermal fuser assembly, rated 200k pages."},
                {compId: "C502", name: "Cyan Toner Cartridge", description: "TN328C high yield cartridge."}
            ],
            schedules: [
                {
                    scheduleId: "SCH-1201",
                    'type: SERVICING,
                    dueDate: overdueDate,
                    description: "Vendor service visit - drum and fuser replacement."
                }
            ],
            workOrders: [
                {
                    orderId: "WO-880",
                    status: CLOSED,
                    description: "Paper jam in tray 2 reported by resource centre staff.",
                    tasks: [
                        {taskId: "T1", description: "Clear obstruction from the tray 2 feed path.", completed: true}
                    ]
                }
            ]
        }
    ];

    int inserted = 0;
    foreach Asset a in seed {
        Asset|ConflictError result = insertAsset(a);
        if result is Asset {
            inserted += 1;
        }
    }
    return inserted;
}
