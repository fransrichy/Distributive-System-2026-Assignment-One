isolated table<Asset> key(assetTag) assetTable = table [];

isolated table<LoanRecord> key(loanId) loanTable = table [];

isolated table<Institution> key(name) institutionTable = table [];

public isolated function assetExists(string assetTag) returns boolean {
    lock {
        return assetTable.hasKey(assetTag);
    }
}

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

public isolated function selectAllAssets() returns Asset[] {
    lock {
        Asset[] snapshot = from Asset a in assetTable
            order by a.assetTag ascending
            select a;
        return snapshot.clone();
    }
}

public isolated function selectAsset(string assetTag) returns Asset|NotFoundError {
    lock {
        Asset? found = assetTable[assetTag];
        if found is () {
            return error NotFoundError(string `No asset found with tag '${assetTag}'.`);
        }
        return found.clone();
    }
}

public isolated function saveAsset(Asset asset) returns Asset|NotFoundError {
    lock {
        if !assetTable.hasKey(asset.assetTag) {
            return error NotFoundError(string `No asset found with tag '${asset.assetTag}'.`);
        }
        assetTable.put(asset.clone());
        return asset.clone();
    }
}

public isolated function deleteAssetRow(string assetTag) returns Asset|NotFoundError {
    lock {
        if !assetTable.hasKey(assetTag) {
            return error NotFoundError(string `No asset found with tag '${assetTag}'.`);
        }
        Asset removed = assetTable.remove(assetTag);
        return removed.clone();
    }
}

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

isolated function selectRegisteredNames() returns string[] {
    lock {
        string[] names = from Institution i in institutionTable
            select i.name;
        return names.clone();
    }
}

isolated function selectOwningNames() returns string[] {
    lock {
        string[] names = from Asset a in assetTable
            select a.institution;
        return names.clone();
    }
}

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

public isolated function countAssets() returns int {
    lock {
        return assetTable.length();
    }
}

public isolated function insertLoan(LoanRecord loan) returns LoanRecord|ConflictError {
    lock {
        if loanTable.hasKey(loan.loanId) {
            return error ConflictError(string `Loan '${loan.loanId}' already exists.`);
        }
        loanTable.add(loan.clone());
        return loan.clone();
    }
}

public isolated function claimAssetForLoan(string assetTag, AssetStatus newStatus)
        returns Asset|AppError {
    lock {
        Asset? found = assetTable[assetTag];
        if found is () {
            return error NotFoundError(string `No asset found with tag '${assetTag}'.`);
        }
        Asset current = found.clone();
        if current.status != AVAILABLE || hasOpenWorkOrder(current) {
            return error ConflictError(
                string `Asset '${assetTag}' cannot be loaned because its status is ${current.status}. ` +
                string `Only AVAILABLE assets can be issued.`);
        }
        current.status = newStatus;
        assetTable.put(current.clone());
        return current.clone();
    }
}

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

public isolated function selectLoans(string? assetTag = ()) returns LoanRecord[] {
    lock {
        LoanRecord[] rows = from LoanRecord l in loanTable
            where assetTag is () || l.assetTag == assetTag
            order by l.loanId descending
            select l;
        return rows.clone();
    }
}

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
