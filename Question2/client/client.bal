// ============================================================================
//  DSA612S - Assignment 1 - Question 2
//  Rental Accommodation System - gRPC Client
//  ---------------------------------------------------------------------------
//  client.bal
//  ---------------------------------------------------------------------------
//  An interactive command line client that exercises every RPC in the
//  contract, including both streaming styles.
//
//  Menu
//  ----
//     1  Create Users               (CLIENT STREAMING)
//     2  Add Property               (unary)
//     3  Update Property            (unary)
//     4  Delete Property            (unary)
//     5  List Available Properties  (SERVER STREAMING)
//     6  Search Property            (unary)
//     7  Book Property              (unary)
//     8  Confirm Booking            (unary)
//     9  Exit
//
//  The client keeps a little session state - the last host, guest and booking
//  identifiers it saw - and offers them as defaults, so a demonstration can be
//  driven end to end without copying identifiers around by hand.
// ============================================================================

import ballerina/grpc;
import ballerina/io;

// ============================================================================
//  SECTION 1 - CONFIGURATION AND SESSION STATE
// ============================================================================

# URL of the rental gRPC server. Override with `Config.toml` or
# `bal run -- -CserverUrl=http://10.0.0.5:9090`.
configurable string serverUrl = "http://localhost:9090";

# The host identifier offered as a default by the property menus.
string sessionHostId = "HOST-001";

# The guest identifier offered as a default by the booking menus.
string sessionGuestId = "GUEST-001";

# The most recent cart entry, offered as a default by "Confirm Booking".
string sessionBookingId = "";

# The most recent property the user created or searched for.
string sessionPropertyId = "";

// ============================================================================
//  SECTION 2 - TERMINAL PRESENTATION HELPERS
// ============================================================================

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

# Splits text on a single separator character.
#
# Written by hand rather than reaching for a regular expression, because the
# only thing needed here is a comma split and a hand rolled loop has no
# dependency on the regexp lang library at all.
#
# + text - The text to split.
# + separator - The character to split on.
# + return - The parts, including empty ones.
isolated function splitOn(string text, string:Char separator) returns string[] {
    string[] parts = [];
    string current = "";
    foreach string:Char ch in text {
        if ch == separator {
            parts.push(current);
            current = "";
        } else {
            current += ch;
        }
    }
    parts.push(current);
    return parts;
}

# Formats a monetary amount with two decimal places.
#
# + amount - The amount in Namibian Dollars.
# + return - A string such as `NAD 1250.00`.
isolated function money(float amount) returns string {
    float rounded = (amount * 100.0).round() / 100.0;
    string text = rounded.toString();

    // `toString` on a float drops trailing zeros, so pad the cents back on to
    // keep the columns aligned.
    int? dot = text.indexOf(".");
    if dot is () {
        return string `NAD ${text}.00`;
    }
    int decimals = text.length() - dot - 1;
    if decimals == 1 {
        return string `NAD ${text}0`;
    }
    if decimals > 2 {
        return string `NAD ${text.substring(0, dot + 3)}`;
    }
    return string `NAD ${text}`;
}

# Prints a section heading surrounded by a rule.
#
# + title - The heading text.
function heading(string title) {
    io:println("");
    io:println(line("=", 92));
    io:println("  " + title);
    io:println(line("=", 92));
}

# Prints a failure in a consistent, obvious format.
#
# + message - The failure text.
function printError(string message) {
    io:println("");
    io:println("  [FAILED] " + message);
}

# Prints a success notice in a consistent format.
#
# + message - The success text.
function printOk(string message) {
    io:println("");
    io:println("  [OK] " + message);
}

# Reads a line from the terminal and trims surrounding whitespace.
#
# + prompt - The prompt to display.
# + return - The trimmed input.
function ask(string prompt) returns string {
    return io:readln(prompt).trim();
}

# Reads a line, falling back to a default when the user just presses Enter.
#
# + prompt - The prompt to display, without the default.
# + fallback - The value to use for empty input.
# + return - The user's answer, or `fallback`.
function askOr(string prompt, string fallback) returns string {
    string answer = ask(string `${prompt} [${fallback}]: `);
    return answer.length() > 0 ? answer : fallback;
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

# Reads a floating point number, re-prompting until the input parses.
#
# + prompt - The prompt to display.
# + fallback - The value to use for empty input.
# + return - The parsed number.
function askFloat(string prompt, float fallback) returns float {
    while true {
        string raw = ask(string `${prompt} [${fallback}]: `);
        if raw.length() == 0 {
            return fallback;
        }
        float|error parsed = float:fromString(raw);
        if parsed is float {
            return parsed;
        }
        io:println(string `  '${raw}' is not a number, please try again.`);
    }
}

# Reads a whole number, re-prompting until the input parses.
#
# + prompt - The prompt to display.
# + fallback - The value to use for empty input.
# + return - The parsed number.
function askInt(string prompt, int fallback) returns int {
    while true {
        string raw = ask(string `${prompt} [${fallback}]: `);
        if raw.length() == 0 {
            return fallback;
        }
        int|error parsed = int:fromString(raw);
        if parsed is int {
            return parsed;
        }
        io:println(string `  '${raw}' is not a whole number, please try again.`);
    }
}

// ============================================================================
//  SECTION 3 - RENDERING
// ============================================================================

# Prints the header row of the property table.
function printPropertyHeader() {
    io:println("  " + fit("PROPERTY ID", 13) + fit("NAME", 30) + fit("LOCATION", 14) +
        fit("TYPE", 12) + fit("PRICE/NIGHT", 15) + fit("SLEEPS", 7) + "STATUS");
    io:println("  " + line("-", 100));
}

# Prints one property as a table row.
#
# + property - The listing to display.
function printPropertyRow(Property property) {
    io:println("  " + fit(property.propertyId, 13) + fit(property.name, 30) +
        fit(property.location, 14) + fit(property.propertyType, 12) +
        fit(money(property.pricePerNight), 15) +
        fit(property.maxGuests.toString(), 7) + property.status);
}

# Prints the full detail of one property.
#
# + property - The listing to display.
function printPropertyDetail(Property property) {
    io:println("");
    io:println("  Property id  : " + property.propertyId);
    io:println("  Name         : " + property.name);
    io:println("  Host         : " + property.hostId);
    io:println("  Location     : " + property.location);
    io:println("  Type         : " + property.propertyType);
    io:println("  Price/night  : " + money(property.pricePerNight));
    io:println("  Sleeps       : " + property.maxGuests.toString());
    io:println("  Status       : " + property.status);
    io:println("  Description  : " + property.description);
    io:println("  Amenities    : " +
        (property.amenities.length() == 0 ? "(none listed)" : string:'join(", ", ...property.amenities)));
}

# Prints a confirmed booking.
#
# + booking - The booking to display.
function printBooking(Booking booking) {
    io:println("");
    io:println("  Booking id   : " + booking.bookingId);
    io:println("  Property     : " + booking.propertyName + " (" + booking.propertyId + ")");
    io:println("  Guest        : " + booking.guestId);
    io:println("  Check in     : " + booking.checkIn);
    io:println("  Check out    : " + booking.checkOut);
    io:println("  Nights       : " + booking.nights.toString());
    io:println("  Total cost   : " + money(booking.totalCost));
    io:println("  State        : " + booking.state);
    if booking.confirmedAt.length() > 0 {
        io:println("  Confirmed at : " + booking.confirmedAt);
    }
}

// ============================================================================
//  SECTION 4 - MENU ACTIONS
// ============================================================================

// ---------------------------------------------------------------------------
//  4.1  Create Users - CLIENT-SIDE STREAMING
// ---------------------------------------------------------------------------

# Collects several user profiles and pushes them to the server over a single
# client-side stream, then reads the one summary the server sends back.
#
# This is the client half of the client-streaming pattern: many requests, one
# response, one HTTP/2 stream.
#
# + ep - The connected gRPC stub.
# + return - A `grpc:Error` when the stream itself fails.
function actionCreateUsers(RentalServiceClient ep) returns error? {
    heading("CREATE USERS  (client-side streaming)");
    io:println("  Profiles are collected first, then streamed to the server in one call.");
    io:println("  The server replies once, after the stream has been closed.");
    io:println("");

    CreateUserRequest[] batch = [];

    string useSample = ask("  Stream the built-in sample batch of 4 profiles? (Y/n): ").toLowerAscii();
    if useSample != "n" && useSample != "no" {
        batch = [
            {name: "Frans Kapenda", email: "frans.kapenda@dunerentals.na", role: HOST, phone: "+264 81 700 1001", region: "Luderitz"},
            {name: "Anna Nghifikwa", email: "anna.nghifikwa@zambezistays.na", role: HOST, phone: "+264 81 700 1002", region: "Katima Mulilo"},
            {name: "Lukas Tjitendero", email: "lukas.t@example.na", role: GUEST, phone: "+264 85 700 2001"},
            {name: "Rauha Shivute", email: "rauha.shivute@example.na", role: GUEST, phone: "+264 85 700 2002"}
        ];
    } else {
        io:println("  Enter profiles one at a time. Leave the name blank to finish.");
        while true {
            io:println("");
            string name = ask(string `  Profile ${batch.length() + 1} - full name (blank to finish): `);
            if name.length() == 0 {
                break;
            }
            string email = askRequired("    Email: ");
            string roleAnswer = ask("    Role - 1) HOST  2) GUEST [2]: ");
            UserRole role = roleAnswer == "1" ? HOST : GUEST;
            string phone = ask("    Phone: ");
            string region = role == HOST ? ask("    Operating region: ") : "";

            batch.push({
                name: name,
                email: email,
                role: role,
                phone: phone,
                region: region
            });
        }
    }

    if batch.length() == 0 {
        printError("No profiles were entered, so nothing was streamed.");
        return;
    }

    // ---- Open the stream ------------------------------------------------
    Create_usersStreamingClient streamingClient = check ep->create_users();

    io:println("");
    io:println(string `  Streaming ${batch.length()} profile(s) to the server...`);
    foreach int i in 0 ..< batch.length() {
        CreateUserRequest profile = batch[i];
        check streamingClient->sendCreateUserRequest(profile);
        io:println(string `    -> sent [${i + 1}] ${profile.name} (${profile.role})`);
    }

    // ---- Half-close: no more messages will be sent ----------------------
    check streamingClient->complete();
    io:println("  Stream closed; waiting for the server summary...");

    // ---- Read the single response --------------------------------------
    CreateUsersSummary? summary = check streamingClient->receiveCreateUsersSummary();
    if summary is () {
        printError("The server closed the stream without sending a summary.");
        return;
    }

    heading("SERVER SUMMARY");
    io:println("  Success        : " + summary.success.toString());
    io:println("  Message        : " + summary.message);
    io:println("  Received       : " + summary.totalReceived.toString());
    io:println("  Hosts created  : " + summary.hostsCreated.toString());
    io:println("  Guests created : " + summary.guestsCreated.toString());

    if summary.createdIds.length() > 0 {
        io:println("  New identifiers:");
        foreach string id in summary.createdIds {
            io:println("    + " + id);
            // Remember the newest ids so later menus can default to them.
            if id.startsWith("HOST-") {
                sessionHostId = id;
            } else if id.startsWith("GUEST-") {
                sessionGuestId = id;
            }
        }
    }
    if summary.failures.length() > 0 {
        io:println("  Rejected:");
        foreach string failure in summary.failures {
            io:println("    - " + failure);
        }
    }
}

// ---------------------------------------------------------------------------
//  4.2  Add Property
// ---------------------------------------------------------------------------

# Registers a new listing.
#
# + ep - The connected gRPC stub.
# + return - A `grpc:Error` when the call fails at the transport level.
function actionAddProperty(RentalServiceClient ep) returns error? {
    heading("ADD PROPERTY  (unary)");

    string hostId = askOr("  Host id", sessionHostId);
    string name = askRequired("  Property name: ");
    string location = askRequired("  Location / region: ");
    string propertyType = askOr("  Type (APARTMENT / GUESTHOUSE / LODGE / VILLA / COTTAGE)", "APARTMENT");
    float price = askFloat("  Price per night in NAD", 1000.0);
    int maxGuests = askInt("  Maximum guests", 2);
    string description = ask("  Description: ");
    string amenityText = ask("  Amenities, comma separated (e.g. WIFI,POOL,PARKING): ");

    string[] amenities = [];
    if amenityText.length() > 0 {
        foreach string raw in splitOn(amenityText, ",") {
            string amenity = raw.trim().toUpperAscii();
            if amenity.length() > 0 {
                amenities.push(amenity);
            }
        }
    }

    AddPropertyRequest request = {
        hostId: hostId,
        name: name,
        location: location,
        propertyType: propertyType,
        pricePerNight: price,
        status: AVAILABLE,
        description: description,
        maxGuests: maxGuests,
        amenities: amenities
    };

    AddPropertyResponse response = check ep->add_property(request);
    if !response.success {
        printError(response.message);
        return;
    }

    sessionHostId = hostId;
    sessionPropertyId = response.propertyId;
    printOk(response.message);
    printPropertyDetail(response.property);
}

// ---------------------------------------------------------------------------
//  4.3  Update Property
// ---------------------------------------------------------------------------

# Patches an existing listing. Blank answers leave a field unchanged.
#
# + ep - The connected gRPC stub.
# + return - A `grpc:Error` when the call fails at the transport level.
function actionUpdateProperty(RentalServiceClient ep) returns error? {
    heading("UPDATE PROPERTY  (unary)");
    io:println("  Press Enter on any field to leave it unchanged.");
    io:println("");

    string propertyId = sessionPropertyId.length() > 0
        ? askOr("  Property id", sessionPropertyId)
        : askRequired("  Property id: ");
    string hostId = askOr("  Host id (must own the listing)", sessionHostId);

    string name = ask("  New name: ");
    string location = ask("  New location: ");
    string propertyType = ask("  New type: ");
    float price = askFloat("  New price per night (0 to keep)", 0.0);
    int maxGuests = askInt("  New maximum guests (0 to keep)", 0);
    string description = ask("  New description: ");

    io:println("  New status:  1) AVAILABLE  2) UNAVAILABLE  3) UNDER_MAINTENANCE  (blank to keep)");
    string statusChoice = ask("  Select: ");
    PropertyStatus status = PROPERTY_STATUS_UNKNOWN;
    match statusChoice {
        "1" => {
            status = AVAILABLE;
        }
        "2" => {
            status = UNAVAILABLE;
        }
        "3" => {
            status = UNDER_MAINTENANCE;
        }
    }

    UpdatePropertyRequest request = {
        propertyId: propertyId,
        hostId: hostId,
        name: name,
        location: location,
        propertyType: propertyType,
        pricePerNight: price,
        status: status,
        description: description,
        maxGuests: maxGuests,
        amenities: []
    };

    UpdatePropertyResponse response = check ep->update_property(request);
    if !response.success {
        printError(response.message);
        return;
    }

    sessionPropertyId = propertyId;
    printOk(response.message);
    printPropertyDetail(response.property);
}

// ---------------------------------------------------------------------------
//  4.4  Delete Property
// ---------------------------------------------------------------------------

# Removes a listing and prints what the host still has in that region.
#
# + ep - The connected gRPC stub.
# + return - A `grpc:Error` when the call fails at the transport level.
function actionDeleteProperty(RentalServiceClient ep) returns error? {
    heading("DELETE PROPERTY  (unary)");

    string propertyId = askRequired("  Property id to remove: ");
    string hostId = askOr("  Host id (must own the listing)", sessionHostId);

    string confirm = ask(string `  Really remove '${propertyId}'? (y/N): `).toLowerAscii();
    if confirm != "y" && confirm != "yes" {
        io:println("  Cancelled; nothing was removed.");
        return;
    }

    RemovePropertyResponse response = check ep->remove_property({
        propertyId: propertyId,
        hostId: hostId
    });

    if !response.success {
        printError(response.message);
    } else {
        printOk(response.message);
    }

    heading(string `REMAINING LISTINGS FOR ${hostId} IN ${response.region}`);
    if response.remainingProperties.length() == 0 {
        io:println("  This host has no further listings in that region.");
        return;
    }
    printPropertyHeader();
    foreach Property property in response.remainingProperties {
        printPropertyRow(property);
    }
    io:println("  " + line("-", 100));
    io:println(string `  ${response.remainingProperties.length()} listing(s).`);
}

// ---------------------------------------------------------------------------
//  4.5  List Available Properties - SERVER-SIDE STREAMING
// ---------------------------------------------------------------------------

# Asks the server for available listings and consumes the reply as a stream,
# printing each listing the moment it arrives rather than waiting for the
# whole result set.
#
# This is the client half of the server-streaming pattern: one request, many
# responses, one HTTP/2 stream.
#
# + ep - The connected gRPC stub.
# + return - A `grpc:Error` when the stream fails.
function actionListAvailable(RentalServiceClient ep) returns error? {
    heading("LIST AVAILABLE PROPERTIES  (server-side streaming)");
    io:println("  Leave a filter blank to ignore it.");
    io:println("");

    string location = ask("  Location contains: ");
    string propertyType = ask("  Property type: ");
    float minPrice = askFloat("  Minimum price per night", 0.0);
    float maxPrice = askFloat("  Maximum price per night (0 = no limit)", 0.0);
    int minGuests = askInt("  Minimum sleeping capacity (0 = any)", 0);

    ListAvailableRequest request = {
        location: location,
        propertyType: propertyType.toUpperAscii(),
        minPrice: minPrice,
        maxPrice: maxPrice,
        minGuests: minGuests
    };

    stream<Property, grpc:Error?> resultStream = check ep->list_available_properties(request);

    io:println("");
    io:println("  Receiving stream...");
    io:println("");
    printPropertyHeader();

    int received = 0;
    record {|Property value;|}|grpc:Error? item = resultStream.next();
    while item is record {|Property value;|} {
        received += 1;
        printPropertyRow(item.value);
        item = resultStream.next();
    }

    // A `grpc:Error` here means the stream was broken mid-flight, which is
    // different from an empty result set and worth reporting distinctly.
    if item is grpc:Error {
        io:println("  " + line("-", 100));
        printError("The stream was interrupted: " + item.message());
        return;
    }

    // The stream is exhausted; closing releases the underlying HTTP/2 stream.
    // A wildcard cannot be used here because `error?` is not a subtype of
    // `any`, so the outcome is bound and reported rather than discarded.
    error? closeOutcome = resultStream.close();
    if closeOutcome is error {
        io:println("  (the stream reported '" + closeOutcome.message() + "' while closing)");
    }

    io:println("  " + line("-", 100));
    if received == 0 {
        io:println("  No property matched those filters.");
    } else {
        io:println(string `  ${received} propert${received == 1 ? "y" : "ies"} streamed from the server.`);
    }
}

// ---------------------------------------------------------------------------
//  4.6  Search Property
// ---------------------------------------------------------------------------

# Looks one listing up by its identifier.
#
# + ep - The connected gRPC stub.
# + return - A `grpc:Error` when the call fails at the transport level.
function actionSearchProperty(RentalServiceClient ep) returns error? {
    heading("SEARCH PROPERTY  (unary)");

    string propertyId = sessionPropertyId.length() > 0
        ? askOr("  Property id", sessionPropertyId)
        : askRequired("  Property id: ");

    SearchPropertyResponse response = check ep->search_property({propertyId: propertyId});

    io:println("");
    io:println("  Found  : " + response.found.toString());
    io:println("  Status : " + response.status);
    io:println("  Message: " + response.message);

    if response.found {
        sessionPropertyId = propertyId;
        printPropertyDetail(response.property);
    }
}

// ---------------------------------------------------------------------------
//  4.7  Book Property
// ---------------------------------------------------------------------------

# Places a requested stay into the guest's temporary booking cart.
#
# + ep - The connected gRPC stub.
# + return - A `grpc:Error` when the call fails at the transport level.
function actionBookProperty(RentalServiceClient ep) returns error? {
    heading("BOOK PROPERTY  (unary - adds to the temporary cart)");
    io:println("  Dates are ISO-8601 (YYYY-MM-DD). Check-out must be after check-in.");
    io:println("");

    string propertyId = sessionPropertyId.length() > 0
        ? askOr("  Property id", sessionPropertyId)
        : askRequired("  Property id: ");
    string guestId = askOr("  Guest id", sessionGuestId);
    string checkIn = askRequired("  Check-in date (YYYY-MM-DD): ");
    string checkOut = askRequired("  Check-out date (YYYY-MM-DD): ");

    BookPropertyResponse response = check ep->book_property({
        propertyId: propertyId,
        guestId: guestId,
        checkIn: checkIn,
        checkOut: checkOut
    });

    if !response.success {
        printError(response.message);
        return;
    }

    sessionGuestId = guestId;
    sessionPropertyId = propertyId;
    sessionBookingId = response.bookingId;

    printOk(response.message);
    io:println("");
    io:println("  Cart entry   : " + response.bookingId);
    io:println("  Nights       : " + response.nights.toString());
    io:println("  Estimated    : " + money(response.estimatedCost));
    io:println("");
    io:println("  Nothing is reserved yet. Choose option 8 to confirm the booking.");
}

// ---------------------------------------------------------------------------
//  4.8  Confirm Booking
// ---------------------------------------------------------------------------

# Finalises a cart entry into a real reservation.
#
# + ep - The connected gRPC stub.
# + return - A `grpc:Error` when the call fails at the transport level.
function actionConfirmBooking(RentalServiceClient ep) returns error? {
    heading("CONFIRM BOOKING  (unary)");

    string bookingId = sessionBookingId.length() > 0
        ? askOr("  Booking id", sessionBookingId)
        : askRequired("  Booking id: ");
    string guestId = askOr("  Guest id", sessionGuestId);

    ConfirmBookingResponse response = check ep->confirm_booking({
        bookingId: bookingId,
        guestId: guestId
    });

    if !response.success {
        printError(response.message);
        return;
    }

    printOk(response.message);
    printBooking(response.booking);
    io:println("");
    io:println("  The temporary request has been cleared from your cart.");
    sessionBookingId = "";
}

// ============================================================================
//  SECTION 5 - MENU LOOP
// ============================================================================

# Prints the main menu.
function printMenu() {
    io:println("");
    io:println(line("=", 66));
    io:println("   RENTAL ACCOMMODATION SYSTEM - MAIN MENU");
    io:println(line("=", 66));
    io:println("    1.  Create Users                (CLIENT STREAMING)");
    io:println("    2.  Add Property                (unary)");
    io:println("    3.  Update Property             (unary)");
    io:println("    4.  Delete Property             (unary)");
    io:println("    5.  List Available Properties   (SERVER STREAMING)");
    io:println("    6.  Search Property             (unary)");
    io:println("    7.  Book Property               (unary)");
    io:println("    8.  Confirm Booking             (unary)");
    io:println("    9.  Exit");
    io:println(line("-", 66));
    io:println(string `   Session: host=${sessionHostId}  guest=${sessionGuestId}` +
        (sessionBookingId.length() > 0 ? string `  cart=${sessionBookingId}` : ""));
    io:println(line("=", 66));
}

# Program entry point: connects the stub, then runs the menu loop until the
# user chooses to exit.
#
# + return - An error only when the stub itself cannot be constructed.
public function main() returns error? {
    io:println(line("=", 66));
    io:println("   DSA612S - RENTAL ACCOMMODATION SYSTEM");
    io:println("   Ministry of Tourism - gRPC command line client");
    io:println(line("=", 66));
    io:println(string `   Connecting to ${serverUrl} ...`);

    RentalServiceClient|grpc:Error connection = new RentalServiceClient(serverUrl);
    if connection is grpc:Error {
        printError(string `Cannot connect to ${serverUrl}: ${connection.message()}`);
        io:println("   Start the server first:  cd Question2/server && bal run");
        return;
    }
    RentalServiceClient ep = connection;

    // A cheap unary call doubles as a connectivity probe: if the server is
    // not listening, this fails immediately with a clear message rather than
    // leaving the user to discover it on their first real operation.
    SearchPropertyResponse|grpc:Error probe = ep->search_property({propertyId: "PROP-001"});
    if probe is grpc:Error {
        printError(string `The server at ${serverUrl} did not answer: ${probe.message()}`);
        io:println("   Start the server first:  cd Question2/server && bal run");
        return;
    }
    io:println("   Connected. Seeded ids: HOST-001..003, GUEST-001..003, PROP-001..006");

    while true {
        printMenu();
        string choice = ask("   Select an option [1-9]: ");

        // Each action is executed defensively: a server side or transport
        // failure is reported and the menu is shown again.
        error? outcome = ();
        match choice {
            "1" => {
                outcome = actionCreateUsers(ep);
            }
            "2" => {
                outcome = actionAddProperty(ep);
            }
            "3" => {
                outcome = actionUpdateProperty(ep);
            }
            "4" => {
                outcome = actionDeleteProperty(ep);
            }
            "5" => {
                outcome = actionListAvailable(ep);
            }
            "6" => {
                outcome = actionSearchProperty(ep);
            }
            "7" => {
                outcome = actionBookProperty(ep);
            }
            "8" => {
                outcome = actionConfirmBooking(ep);
            }
            "9"|"q"|"Q"|"exit" => {
                io:println("");
                io:println("   Goodbye. Thank you for using the Ministry of Tourism platform.");
                return;
            }
            _ => {
                printError(string `'${choice}' is not a valid option. Please choose 1 to 9.`);
            }
        }

        if outcome is error {
            printError(outcome.message());
        }
    }
}

// The client maintains lightweight session state to simplify repeated demonstration operations.

// Streaming results are consumed incrementally so each property can be displayed as it arrives.
