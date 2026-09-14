// ============================================================================
//  DSA612S - Assignment 1 - Question 1
//  Distributed Library and Resource Management System
//  ---------------------------------------------------------------------------
//  client.bal - Question 1 client implementation
//  ---------------------------------------------------------------------------
//  An interactive command line front end for the REST API defined in
//  `Question1/service`. It is a *separate Ballerina package*, so it talks to
//  the server purely over HTTP - exactly the inter-process communication the
//  assignment asks for.
//
//  Menu
//  ----
//     1  View Assets                 6  View Campus Assets
//     2  Search Asset                7  View Overdue Maintenance
//     3  Loan Asset                  8  Create Schedule
//     4  Return Asset                9  Create Work Order
//     5  View Institution Assets    10  Exit
//
//  DESIGN NOTES
//  ------------
//  * The record types below intentionally mirror only the fields the client
//    needs, and they are *open* records. A consumer that tolerates unknown
//    fields keeps working when the server adds new ones - the standard rule
//    for evolving a distributed contract.
//  * Status and type fields are typed as plain `string` rather than as enums,
//    for the same tolerance reason.
//  * Every API call goes through `invoke`, which turns a non-2xx response and
//    its JSON error envelope into a readable Ballerina error, so the menu
//    loop never crashes on a server side failure.
// ============================================================================

import ballerina/http;
import ballerina/io;

// ============================================================================
//  SECTION 1 - CONFIGURATION
// ============================================================================

# Base URL of the Library REST API. Override with `Config.toml` or
# `bal run -- -CapiUrl=http://10.0.0.5:8080`.
configurable string apiUrl = "http://localhost:8080";

# How long to wait for the server before giving up, in seconds.
configurable decimal requestTimeout = 30;

// ============================================================================
//  SECTION 2 - CLIENT SIDE VIEW OF THE API CONTRACT
// ============================================================================

# A component of an asset, as returned by the API.
#
# + compId - Component identifier.
# + name - Component name.
# + description - What the component does.
public type Component record {
    string compId;
    string name;
    string description?;
};

# A schedule entry attached to an asset.
#
# + scheduleId - Schedule identifier.
# + type - MAINTENANCE, SERVICING, INSPECTION or BOOKING.
# + dueDate - ISO-8601 due date.
# + description - What has to be done.
public type Schedule record {
    string scheduleId;
    string 'type?;
    string dueDate;
    string description?;
};

# A sub-task of a work order.
#
# + taskId - Task identifier.
# + description - What has to be done.
# + completed - Whether the task is finished.
public type Task record {
    string taskId;
    string description;
    boolean completed?;
};

# A repair job raised against an asset.
#
# + orderId - Work order identifier.
# + status - OPEN, IN_PROGRESS, CLOSED or CANCELLED.
# + description - Summary of the fault.
# + tasks - The steps required to fix it.
public type WorkOrder record {
    string orderId;
    string status?;
    string description;
    Task[] tasks?;
};

# A library or campus resource.
#
# + assetTag - Ministry-wide unique tag.
# + name - Human readable name.
# + description - Long form description.
# + institution - Owning institution.
# + site - Campus / site.
# + status - Current availability status.
# + dateAcquired - ISO-8601 acquisition date.
# + components - Replaceable sub-parts.
# + schedules - Maintenance and booking entries.
# + workOrders - Repair jobs.
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

# One row of the overdue maintenance report.
#
# + assetTag - Tag of the affected asset.
# + assetName - Name of the affected asset.
# + institution - Owning institution.
# + site - Campus / site.
# + status - Current status of the asset.
# + scheduleId - Identifier of the overdue schedule.
# + scheduleType - Category of the overdue schedule.
# + dueDate - The date that has passed.
# + description - Description of the outstanding work.
# + daysOverdue - How many whole days late it is.
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

// ============================================================================
//  SECTION 3 - TERMINAL PRESENTATION HELPERS
// ============================================================================

# Characters that never need percent-encoding inside a URI path segment,
# per RFC 3986 section 2.3.
const string UNRESERVED =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";

# Lookup table used by the percent-encoder.
final readonly & string[] HEX_DIGITS =
    ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"];

# Percent-encodes a value so it can be dropped into a URI path segment.
#
# A hand written encoder is used rather than `url:encode` because the latter
# applies form-encoding rules, where a space becomes `+`. Inside a path
# segment a space has to be `%20`, otherwise institution names such as
# "University of Namibia" resolve to the wrong resource.
#
# + value - The raw text to encode.
# + return - The percent-encoded text.
isolated function encodeSegment(string value) returns string {
    string encoded = "";
    foreach string:Char ch in value {
        if UNRESERVED.includes(ch) {
            encoded += ch;
            continue;
        }
        // Everything else is encoded byte by byte from its UTF-8 form, which
        // keeps the encoder correct for non-ASCII characters too.
        foreach byte b in ch.toBytes() {
            int code = <int>b;
            encoded += "%" + HEX_DIGITS[code / 16] + HEX_DIGITS[code % 16];
        }
    }
    return encoded;
}

# Pads or truncates a value to an exact column width.
#
# + value - The text to lay out.
# + width - The target column width.
# + return - A string of exactly `width` characters.
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

# Repeats a character to build a horizontal rule.
#
# + ch - The character to repeat.
# + count - How many times to repeat it.
# + return - The resulting line.
isolated function line(string ch, int count) returns string {
    string result = "";
    foreach int _ in 0 ..< count {
        result += ch;
    }
    return result;
}

# Prints a section heading surrounded by a rule.
#
# + title - The heading text.
function heading(string title) {
    io:println("");
    io:println(line("=", 118));
    io:println("  " + title);
    io:println(line("=", 118));
}

# Prints a failure in a consistent, obvious format.
#
# + message - The failure text.
function printError(string message) {
    io:println("");
    io:println("  [ERROR] " + message);
}

# Prints a success notice in a consistent format.
#
# + message - The success text.
function printOk(string message) {
    io:println("");
    io:println("  [OK] " + message);
}

// ============================================================================
//  SECTION 4 - HTTP PLUMBING
// ============================================================================

# Executes one API call and normalises the outcome.
#
# Sends the request using the appropriate HTTP method and returns the server’s response.
#
# `http:Client` exposes one remote method per verb, so the verb is dispatched  
# here rather than passed through as a string. Every branch returns its own
# value, which is what keeps the caller free of an uninitialised variable.
#
# + api - The configured HTTP client.
# + method - "GET", "POST", "PUT" or "DELETE".
# + path - The request path, already percent-encoded.
# + payload - The JSON body for POST and PUT, or `()`.
# + return - The raw HTTP response, or an error when the verb is unsupported
#            or the request never reached the server.
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

# Executes one API call and normalises the outcome.
#
# + api - The configured HTTP client.
# + method - "GET", "POST", "PUT" or "DELETE".
# + path - The request path, already percent-encoded.
# + payload - The JSON body for POST and PUT, or `()`.
# + return - The decoded response body, or an error describing the failure.
function invoke(http:Client api, string method, string path, json payload = ()) returns json|error {
    http:Response response = check dispatch(api, method, path, payload);

    int status = response.statusCode;
    json|http:ClientError body = response.getJsonPayload();

    if status >= 200 && status < 300 {
        if body is http:ClientError {
            // A 2xx with no body is still a success.
            return ();
        }
        return body;
    }

    // Non-2xx: try to surface the server's own message.
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

# Reads a line from the terminal and trims surrounding whitespace.
#
# + prompt - The prompt to display.
# + return - The trimmed input.
function ask(string prompt) returns string {
    return io:readln(prompt).trim();
}

# Reads a line and rejects a blank answer, re-prompting until one is given.
#
# + prompt - The prompt to display.
# + return - The non-blank trimmed input.
function askRequired(string prompt) returns string {
    while true {
        string value = ask(prompt);
        if value.length() > 0 {
            return value;
        }
        io:println("  This value is required, please try again.");
    }
}

// ============================================================================
//  SECTION 5 - RENDERING
// ============================================================================

# Renders a list of assets as an aligned table.
#
# + assets - The assets to display.
# + title - The heading to print above the table.
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

# Renders the full detail of a single asset, including every nested
# collection.
#
# + asset - The asset to display.
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

# Renders the overdue maintenance dashboard.
#
# + rows - The overdue rows returned by the API.
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

// ============================================================================
//  SECTION 6 - MENU ACTIONS
// ============================================================================

# Menu option 1 - lists every asset held by the ministry.
#
# + api - The configured HTTP client.
# + return - An error when the call fails.
function actionViewAssets(http:Client api) returns error? {
    json payload = check invoke(api, "GET", "/assets");
    Asset[] assets = check payload.cloneWithType();
    renderAssetTable(assets, "GLOBAL VIEW - ALL ASSETS ACROSS THE MINISTRY");
}

# Menu option 2 - looks an asset up by tag, or falls back to a free text
# search when the tag is not an exact match.
#
# + api - The configured HTTP client.
# + return - An error when the call fails.
function actionSearchAsset(http:Client api) returns error? {
    string term = askRequired("  Enter an asset tag or a search term: ");

    // First try an exact primary key lookup, which is the cheapest path.
    json|error exact = invoke(api, "GET", "/assets/" + encodeSegment(term));
    if exact is json {
        Asset asset = check exact.cloneWithType();
        renderAssetDetail(asset);
        return;
    }

    // Not a known tag, so fall back to the free text search endpoint.
    io:println("  No asset carries that exact tag; searching all fields instead...");
    json payload = check invoke(api, "GET", "/assets?q=" + encodeSegment(term));
    Asset[] assets = check payload.cloneWithType();
    if assets.length() == 1 {
        renderAssetDetail(assets[0]);
        return;
    }
    renderAssetTable(assets, "SEARCH RESULTS FOR '" + term + "'");
}

# Menu option 3 - loans an asset, or books a meeting room / lab.
#
# + api - The configured HTTP client.
# + return - An error when the call fails.
function actionLoanAsset(http:Client api) returns error? {
    heading("LOAN AN ASSET / BOOK A SPACE");

    // Show what is actually available so the user does not have to guess.
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

# Menu option 4 - takes an asset back from a borrower.
#
# + api - The configured HTTP client.
# + return - An error when the call fails.
function actionReturnAsset(http:Client api) returns error? {
    heading("RETURN AN ASSET / RELEASE A SPACE");

    // Everything that is currently out, in one list.
    json loanedJson = check invoke(api, "GET", "/assets?status=LOANED_OUT");
    json occupiedJson = check invoke(api, "GET", "/assets?status=OCCUPIED");
    Asset[] loaned = check loanedJson.cloneWithType();
    Asset[] occupied = check occupiedJson.cloneWithType();

    // Merge the two result sets into a single list of everything that is out.
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

# Menu option 5 - campus view filtered by institution.
#
# + api - The configured HTTP client.
# + return - An error when the call fails.
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

    // Allow selection by ordinal for convenience.
    int|error ordinal = int:fromString(answer);
    if ordinal is int && ordinal >= 1 && ordinal <= institutions.length() {
        institution = institutions[ordinal - 1];
    }

    json payload = check invoke(api, "GET", "/assets/institution/" + encodeSegment(institution));
    Asset[] assets = check payload.cloneWithType();
    renderAssetTable(assets, "ASSETS OWNED BY " + institution.toUpperAscii());
}

# Menu option 6 - campus view filtered by site.
#
# + api - The configured HTTP client.
# + return - An error when the call fails.
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

# Menu option 7 - the overdue maintenance dashboard.
#
# + api - The configured HTTP client.
# + return - An error when the call fails.
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

# Menu option 8 - adds a servicing / maintenance / booking schedule.
#
# + api - The configured HTTP client.
# + return - An error when the call fails.
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

# Menu option 9 - opens a work order with an arbitrary number of sub-tasks.
#
# + api - The configured HTTP client.
# + return - An error when the call fails.
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

// ============================================================================
//  SECTION 7 - MENU LOOP
// ============================================================================

# Prints the main menu.
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
    io:println("    8.  Add Schedule               (schedule manager)");
    io:println("    9.  Create Work Order          (fault reporting)");
    io:println("   10.  Exit");
    io:println(line("=", 62));
}

# Confirms the API is reachable before the menu is shown, so that a wrong 
# port or a server that is not running is reported once and clearly instead of
# failing on every menu option.
#
# + api - The configured HTTP client.
# + return - An error when the server cannot be reached.
function checkConnection(http:Client api) returns error? {
    json payload = check invoke(api, "GET", "/health");
    if payload is map<json> {
        // A string template only accepts simple types, and `json` also covers
        // arrays and maps, so the count is rendered explicitly.
        json? assets = payload["assets"];
        string count = assets is () ? "0" : assets.toString();
        io:println(string `  Connected to ${apiUrl} - ${count} asset(s) in the store.`);
    }
}

# Program entry point: builds the HTTP client, verifies connectivity and then
# runs the menu loop until the user chooses to exit.
#
# + return - An error only when the client itself cannot be constructed.
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

        // Each action is executed defensively: a server side failure is
        // reported and the menu is shown again rather than terminating.
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
                outcome = actionAddSchedule(api);
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
