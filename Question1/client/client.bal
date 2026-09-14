import ballerina/http;
import ballerina/io;

configurable string apiUrl = "http://localhost:8080";

configurable decimal requestTimeout = 30;

public type Component record {
    string compId;
    string name;
    string description?;
};

public type Schedule record {
    string scheduleId;
    string 'type?;
    string dueDate;
    string description?;
};

public type Task record {
    string taskId;
    string description;
    boolean completed?;
};

public type WorkOrder record {
    string orderId;
    string status?;
    string description;
    Task[] tasks?;
};

public type Asset record {
    string assetTag;
    string name;
    string description?;
    string institution;
    string site;
    string status;
    string dateAcquired;
    Component[] components?;
    Schedule[] schedules?;
    WorkOrder[] workOrders?;
};

public type OverdueSchedule record {
    string assetTag;
    string assetName;
    string institution;
    string site;
    string status;
    string scheduleId;
    string scheduleType;
    string dueDate;
    string description;
    int daysOverdue;
};

const string UNRESERVED =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";

final readonly & string[] HEX_DIGITS =
    ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"];

isolated function encodeSegment(string value) returns string {
    string encoded = "";
    foreach string:Char ch in value {
        if UNRESERVED.includes(ch) {
            encoded += ch;
            continue;
        }
        foreach byte b in ch.toBytes() {
            int code = <int>b;
            encoded += "%" + HEX_DIGITS[code / 16] + HEX_DIGITS[code % 16];
        }
    }
    return encoded;
}

isolated function fit(string value, int width) returns string {
    if value.length() == width {
        return value;
    }
    if value.length() > width {
        return width > 3 ? value.substring(0, width - 3) + "..." : value.substring(0, width);
    }
    string padded = value;
    while padded.length() < width {
        padded += " ";
    }
    return padded;
}

isolated function line(string ch, int count) returns string {
    string result = "";
    foreach int _ in 0 ..< count {
        result += ch;
    }
    return result;
}

function heading(string title) {
    io:println("");
    io:println(line("=", 118));
    io:println("  " + title);
    io:println(line("=", 118));
}

function printError(string message) {
    io:println("");
    io:println("  [ERROR] " + message);
}

function printOk(string message) {
    io:println("");
    io:println("  [OK] " + message);
}

function dispatch(http:Client api, string method, string path, json payload)
        returns http:Response|error {
    match method {
        "GET" => {
            http:Response response = check api->get(path);
            return response;
        }
        "POST" => {
            http:Response response = check api->post(path, payload);
            return response;
        }
        "PUT" => {
            http:Response response = check api->put(path, payload);
            return response;
        }
        "DELETE" => {
            http:Response response = check api->delete(path);
            return response;
        }
    }
    return error(string `Unsupported HTTP method '${method}'.`);
}

function invoke(http:Client api, string method, string path, json payload = ()) returns json|error {
    http:Response response = check dispatch(api, method, path, payload);

    int status = response.statusCode;
    json|http:ClientError body = response.getJsonPayload();

    if status >= 200 && status < 300 {
        if body is http:ClientError {
            return ();
        }
        return body;
    }
    string detail = string `the server returned HTTP ${status}`;
    if body is map<json> {
        json? message = body["message"];
        json? code = body["error"];
        if message is string {
            detail = code is string ? string `${code} - ${message}` : message;
        }
    }
    return error(string `Request failed (${status}): ${detail}`);
}

function ask(string prompt) returns string {
    return io:readln(prompt).trim();
}

function askRequired(string prompt) returns string {
    while true {
        string value = ask(prompt);
        if value.length() > 0 {
            return value;
        }
        io:println("  This value is required, please try again.");
    }
}

function renderAssetTable(Asset[] assets, string title) {
    heading(title);
    if assets.length() == 0 {
        io:println("  No assets matched your request.");
        return;
    }

    io:println("  " + fit("ASSET TAG", 22) + fit("NAME", 34) + fit("INSTITUTION", 30) +
        fit("SITE", 20) + fit("STATUS", 12));
    io:println("  " + line("-", 116));

    foreach Asset a in assets {
        io:println("  " + fit(a.assetTag, 22) + fit(a.name, 34) + fit(a.institution, 30) +
            fit(a.site, 20) + fit(a.status, 12));
    }
    io:println("  " + line("-", 116));
    io:println(string `  ${assets.length()} asset(s).`);
}

function renderAssetDetail(Asset asset) {
    heading("ASSET DETAIL - " + asset.assetTag);
    io:println("  Name         : " + asset.name);
    io:println("  Description  : " + (asset?.description ?: "-"));
    io:println("  Institution  : " + asset.institution);
    io:println("  Site         : " + asset.site);
    io:println("  Status       : " + asset.status);
    io:println("  Acquired     : " + asset.dateAcquired);

    Component[] components = asset?.components ?: [];
    io:println("");
    io:println(string `  COMPONENTS (${components.length()})`);
    if components.length() == 0 {
        io:println("    (none)");
    } else {
        foreach Component c in components {
            io:println("    - " + fit(c.compId, 12) + fit(c.name, 34) + (c?.description ?: ""));
        }
    }

    Schedule[] schedules = asset?.schedules ?: [];
    io:println("");
    io:println(string `  SCHEDULES (${schedules.length()})`);
    if schedules.length() == 0 {
        io:println("    (none)");
    } else {
        foreach Schedule s in schedules {
            io:println("    - " + fit(s.scheduleId, 12) + fit(s?.'type ?: "MAINTENANCE", 14) +
                fit(s.dueDate, 14) + (s?.description ?: ""));
        }
    }

    WorkOrder[] orders = asset?.workOrders ?: [];
    io:println("");
    io:println(string `  WORK ORDERS (${orders.length()})`);
    if orders.length() == 0 {
        io:println("    (none)");
    } else {
        foreach WorkOrder w in orders {
            io:println("    - " + fit(w.orderId, 12) + fit(w?.status ?: "OPEN", 14) + w.description);
            foreach Task t in w?.tasks ?: [] {
                string mark = (t?.completed ?: false) ? "[x]" : "[ ]";
                io:println("        " + mark + " " + fit(t.taskId, 10) + t.description);
            }
        }
    }
    io:println("");
}

function renderOverdue(OverdueSchedule[] rows) {
    heading("OVERDUE MAINTENANCE DASHBOARD");
    if rows.length() == 0 {
        io:println("  Nothing is overdue. Every schedule is up to date.");
        return;
    }

    io:println("  " + fit("ASSET TAG", 22) + fit("SCHEDULE", 12) + fit("TYPE", 14) +
        fit("DUE DATE", 13) + fit("DAYS LATE", 11) + fit("INSTITUTION", 30));
    io:println("  " + line("-", 116));

    foreach OverdueSchedule row in rows {
        io:println("  " + fit(row.assetTag, 22) + fit(row.scheduleId, 12) +
            fit(row.scheduleType, 14) + fit(row.dueDate, 13) +
            fit(row.daysOverdue.toString(), 11) + fit(row.institution, 30));
    }
    io:println("  " + line("-", 116));
    io:println(string `  ${rows.length()} overdue schedule(s).`);
}

function actionViewAssets(http:Client api) returns error? {
    json payload = check invoke(api, "GET", "/assets");
    Asset[] assets = check payload.cloneWithType();
    renderAssetTable(assets, "GLOBAL VIEW - ALL ASSETS ACROSS THE MINISTRY");
}

function actionSearchAsset(http:Client api) returns error? {
    string term = askRequired("  Enter an asset tag or a search term: ");
    json|error exact = invoke(api, "GET", "/assets/" + encodeSegment(term));
    if exact is json {
        Asset asset = check exact.cloneWithType();
        renderAssetDetail(asset);
        return;
    }
    io:println("  No asset carries that exact tag; searching all fields instead...");
    json payload = check invoke(api, "GET", "/assets?q=" + encodeSegment(term));
    Asset[] assets = check payload.cloneWithType();
    if assets.length() == 1 {
        renderAssetDetail(assets[0]);
        return;
    }
    renderAssetTable(assets, "SEARCH RESULTS FOR '" + term + "'");
}

function actionLoanAsset(http:Client api) returns error? {
    heading("LOAN AN ASSET / BOOK A SPACE");
    json available = check invoke(api, "GET", "/assets?status=AVAILABLE");
    Asset[] assets = check available.cloneWithType();
    if assets.length() == 0 {
        printError("There are no AVAILABLE assets to loan at the moment.");
        return;
    }
    renderAssetTable(assets, "CURRENTLY AVAILABLE");

    string tag = askRequired("  Asset tag to loan: ");
    string borrower = askRequired("  Borrower (staff / student number or name): ");
    string dueDate = ask("  Return date as YYYY-MM-DD (blank for the default 14 days): ");
    string spaceAnswer = ask("  Is this a room or lab booking? (y/N): ").toLowerAscii();

    map<json> request = {
        "borrower": borrower,
        "spaceBooking": spaceAnswer == "y" || spaceAnswer == "yes"
    };
    if dueDate.length() > 0 {
        request["dueDate"] = dueDate;
    }

    json payload = check invoke(api, "POST", "/assets/" + encodeSegment(tag) + "/loan", request);
    Asset asset = check payload.cloneWithType();
    printOk(string `Asset '${asset.assetTag}' is now ${asset.status} and issued to ${borrower}.`);
    renderAssetDetail(asset);
}

function actionReturnAsset(http:Client api) returns error? {
    heading("RETURN AN ASSET / RELEASE A SPACE");
    json loanedJson = check invoke(api, "GET", "/assets?status=LOANED_OUT");
    json occupiedJson = check invoke(api, "GET", "/assets?status=OCCUPIED");
    Asset[] loaned = check loanedJson.cloneWithType();
    Asset[] occupied = check occupiedJson.cloneWithType();
    Asset[] out = [];
    foreach Asset a in loaned {
        out.push(a);
    }
    foreach Asset a in occupied {
        out.push(a);
    }

    if out.length() == 0 {
        printError("No asset is currently on loan or occupied.");
        return;
    }
    renderAssetTable(out, "CURRENTLY OUT");

    string tag = askRequired("  Asset tag being returned: ");
    string damaged = ask("  Is the asset damaged and in need of maintenance? (y/N): ").toLowerAscii();
    boolean sendForMaintenance = damaged == "y" || damaged == "yes";
    string notes = sendForMaintenance
        ? askRequired("  Describe the damage: ")
        : ask("  Condition notes (optional): ");

    map<json> request = {
        "notes": notes,
        "sendForMaintenance": sendForMaintenance
    };

    json payload = check invoke(api, "POST", "/assets/" + encodeSegment(tag) + "/return", request);
    Asset asset = check payload.cloneWithType();
    printOk(string `Asset '${asset.assetTag}' was returned and is now ${asset.status}.`);
}

function actionViewByInstitution(http:Client api) returns error? {
    json listing = check invoke(api, "GET", "/institutions");
    string[] institutions = check listing.cloneWithType();

    heading("INSTITUTIONS IN THE LISTING");
    if institutions.length() == 0 {
        io:println("  No institution currently owns any asset.");
        return;
    }
    foreach int i in 0 ..< institutions.length() {
        io:println(string `   ${i + 1}. ${institutions[i]}`);
    }

    string answer = askRequired("  Enter a number from the list, or type an institution name: ");
    string institution = answer;
    int|error ordinal = int:fromString(answer);
    if ordinal is int && ordinal >= 1 && ordinal <= institutions.length() {
        institution = institutions[ordinal - 1];
    }

    json payload = check invoke(api, "GET", "/assets/institution/" + encodeSegment(institution));
    Asset[] assets = check payload.cloneWithType();
    renderAssetTable(assets, "ASSETS OWNED BY " + institution.toUpperAscii());
}

function actionViewBySite(http:Client api) returns error? {
    json listing = check invoke(api, "GET", "/sites");
    string[] sites = check listing.cloneWithType();

    heading("CAMPUSES / SITES IN THE LISTING");
    if sites.length() == 0 {
        io:println("  No site currently holds any asset.");
        return;
    }
    foreach int i in 0 ..< sites.length() {
        io:println(string `   ${i + 1}. ${sites[i]}`);
    }

    string answer = askRequired("  Enter a number from the list, or type a site name: ");
    string site = answer;
    int|error ordinal = int:fromString(answer);
    if ordinal is int && ordinal >= 1 && ordinal <= sites.length() {
        site = sites[ordinal - 1];
    }

    json payload = check invoke(api, "GET", "/assets/site/" + encodeSegment(site));
    Asset[] assets = check payload.cloneWithType();
    renderAssetTable(assets, "ASSETS LOCATED AT " + site.toUpperAscii());
}

function actionViewOverdue(http:Client api) returns error? {
    string institution = ask("  Filter by institution (blank for every institution): ");
    string path = "/maintenance/overdue";
    if institution.length() > 0 {
        path += "?institution=" + encodeSegment(institution);
    }
    json payload = check invoke(api, "GET", path);
    OverdueSchedule[] rows = check payload.cloneWithType();
    renderOverdue(rows);
}

function actionAddSchedule(http:Client api) returns error? {
    heading("SCHEDULE MANAGER - ADD A SCHEDULE");

    string tag = askRequired("  Asset tag: ");
    io:println("  Schedule type:  1) MAINTENANCE   2) SERVICING   3) INSPECTION   4) BOOKING");
    string typeChoice = ask("  Select [1-4, default 1]: ");

    string scheduleType;
    match typeChoice {
        "2" => {
            scheduleType = "SERVICING";
        }
        "3" => {
            scheduleType = "INSPECTION";
        }
        "4" => {
            scheduleType = "BOOKING";
        }
        _ => {
            scheduleType = "MAINTENANCE";
        }
    }

    string dueDate = askRequired("  Due date (YYYY-MM-DD): ");
    string description = ask("  Description: ");
    string scheduleId = ask("  Schedule id (blank to let the server generate one): ");

    map<json> request = {
        "type": scheduleType,
        "dueDate": dueDate,
        "description": description
    };
    if scheduleId.length() > 0 {
        request["scheduleId"] = scheduleId;
    }

    json payload = check invoke(api, "POST", "/assets/" + encodeSegment(tag) + "/schedules", request);
    Asset asset = check payload.cloneWithType();
    printOk(string `Schedule added to '${asset.assetTag}'.`);
    renderAssetDetail(asset);
}

function actionManageSchedule(http:Client api) returns error? {
    heading("SCHEDULE MANAGER");
    io:println("  1) Add schedule   2) Modify schedule   3) Remove schedule");
    string choice = ask("  Select [1-3, default 1]: ");
    if choice == "" || choice == "1" {
        return actionAddSchedule(api);
    }
    if choice != "2" && choice != "3" {
        return error("Choose 1, 2 or 3 for the schedule action.");
    }

    string tag = askRequired("  Asset tag: ");
    string path = "/assets/" + encodeSegment(tag);
    json payload = check invoke(api, "GET", path);
    Asset asset = check payload.cloneWithType();
    renderAssetDetail(asset);
    if (asset?.schedules ?: []).length() == 0 {
        io:println("  This asset has no schedules to modify or remove.");
        return;
    }

    string scheduleId = askRequired("  Schedule id: ");
    Schedule? selected = ();
    foreach Schedule schedule in asset?.schedules ?: [] {
        if schedule.scheduleId == scheduleId {
            selected = schedule;
            break;
        }
    }
    if selected is () {
        return error(string `Schedule '${scheduleId}' does not belong to '${tag}'.`);
    }
    path += "/schedules/" + encodeSegment(scheduleId);
    if choice == "3" {
        string answer = ask("  Remove this schedule? (y/N): ").toLowerAscii();
        if answer != "y" && answer != "yes" {
            return;
        }
        _ = check invoke(api, "DELETE", path);
        printOk(string `Schedule '${scheduleId}' removed from '${tag}'.`);
        return;
    }

    string scheduleType = ask("  Type (MAINTENANCE / SERVICING / INSPECTION / BOOKING; blank to keep): ").toUpperAscii();
    string dueDate = ask(string `  Due date (YYYY-MM-DD, blank to keep ${selected.dueDate}): `);
    string description = ask("  Description (blank to keep): ");
    map<json> request = {};
    if scheduleType.length() > 0 {
        request["type"] = scheduleType;
    }
    if dueDate.length() > 0 {
        request["dueDate"] = dueDate;
    }
    if description.length() > 0 {
        request["description"] = description;
    }
    if request.length() == 0 {
        io:println("  No changes entered.");
        return;
    }
    json updated = check invoke(api, "PUT", path, request);
    Asset updatedAsset = check updated.cloneWithType();
    printOk(string `Schedule '${scheduleId}' updated.`);
    renderAssetDetail(updatedAsset);
}

function actionCreateWorkOrder(http:Client api) returns error? {
    heading("WORK ORDER MANAGER - OPEN A WORK ORDER");

    string tag = askRequired("  Asset tag: ");
    string description = askRequired("  Fault description: ");
    io:println("  Status:  1) OPEN   2) IN_PROGRESS");
    string statusChoice = ask("  Select [1-2, default 1]: ");
    string status = statusChoice == "2" ? "IN_PROGRESS" : "OPEN";

    io:println("  Enter the sub-tasks one per line. Submit a blank line to finish.");
    json[] tasks = [];
    while true {
        string taskDescription = ask(string `    Task ${tasks.length() + 1}: `);
        if taskDescription.length() == 0 {
            break;
        }
        tasks.push({"description": taskDescription, "completed": false});
    }

    map<json> request = {
        "status": status,
        "description": description,
        "tasks": tasks
    };

    json payload = check invoke(api, "POST", "/assets/" + encodeSegment(tag) + "/workorders", request);
    Asset asset = check payload.cloneWithType();
    printOk(string `Work order opened against '${asset.assetTag}'.`);
    renderAssetDetail(asset);
}

function printMenu() {
    io:println("");
    io:println(line("=", 62));
    io:println("   LIBRARY AND RESOURCE MANAGEMENT - MAIN MENU");
    io:println(line("=", 62));
    io:println("    1.  View Assets                (global view)");
    io:println("    2.  Search Asset               (by tag or free text)");
    io:println("    3.  Loan Asset                 (issue / book a space)");
    io:println("    4.  Return Asset               (hand back / release)");
    io:println("    5.  View Institution Assets    (filter by institution)");
    io:println("    6.  View Campus Assets         (filter by site)");
    io:println("    7.  View Overdue Maintenance   (staff dashboard)");
    io:println("    8.  Manage Schedules           (add / modify / remove)");
    io:println("    9.  Create Work Order          (fault reporting)");
    io:println("   10.  Exit");
    io:println(line("=", 62));
}

function checkConnection(http:Client api) returns error? {
    json payload = check invoke(api, "GET", "/health");
    if payload is map<json> {
        json? assets = payload["assets"];
        string count = assets is () ? "0" : assets.toString();
        io:println(string `  Connected to ${apiUrl} - ${count} asset(s) in the store.`);
    }
}

public function main() returns error? {
    io:println(line("=", 62));
    io:println("   DSA612S - DISTRIBUTED LIBRARY AND RESOURCE MANAGEMENT");
    io:println("   Ministry of Higher Education, Training and Innovations");
    io:println("   REST command line client");
    io:println(line("=", 62));

    http:Client api = check new (apiUrl, timeout = requestTimeout);

    error? connection = checkConnection(api);
    if connection is error {
        printError(string `Cannot reach the API at ${apiUrl}: ${connection.message()}`);
        io:println("  Start the server first:  cd Question1/service && bal run");
        return;
    }

    while true {
        printMenu();
        string choice = ask("  Select an option [1-10]: ");
        error? outcome = ();
        match choice {
            "1" => {
                outcome = actionViewAssets(api);
            }
            "2" => {
                outcome = actionSearchAsset(api);
            }
            "3" => {
                outcome = actionLoanAsset(api);
            }
            "4" => {
                outcome = actionReturnAsset(api);
            }
            "5" => {
                outcome = actionViewByInstitution(api);
            }
            "6" => {
                outcome = actionViewBySite(api);
            }
            "7" => {
                outcome = actionViewOverdue(api);
            }
            "8" => {
                outcome = actionManageSchedule(api);
            }
            "9" => {
                outcome = actionCreateWorkOrder(api);
            }
            "10"|"q"|"Q"|"exit" => {
                io:println("");
                io:println("  Goodbye. The Ministry thanks you for keeping the catalogue tidy.");
                return;
            }
            _ => {
                printError(string `'${choice}' is not a valid option. Please choose 1 to 10.`);
            }
        }

        if outcome is error {
            printError(outcome.message());
        }
    }
}
