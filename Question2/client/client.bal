import ballerina/grpc;
import ballerina/io;

configurable string serverUrl = "http://localhost:9090";
string sessionHostId = "HOST-001";
string sessionGuestId = "GUEST-001";
string sessionBookingId = "";
string sessionPropertyId = "";

isolated function line(string ch, int count) returns string {
    string result = "";
    foreach int _ in 0 ..< count {
        result += ch;
    }
    return result;
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

isolated function money(float amount) returns string {
    float rounded = (amount * 100.0).round() / 100.0;
    string text = rounded.toString();
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

function heading(string title) {
    io:println("");
    io:println(line("=", 92));
    io:println("  " + title);
    io:println(line("=", 92));
}

function printError(string message) {
    io:println("");
    io:println("  [FAILED] " + message);
}

function printOk(string message) {
    io:println("");
    io:println("  [OK] " + message);
}

function ask(string prompt) returns string {
    return io:readln(prompt).trim();
}

function askOr(string prompt, string fallback) returns string {
    string answer = ask(string `${prompt} [${fallback}]: `);
    return answer.length() > 0 ? answer : fallback;
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

function printPropertyHeader() {
    io:println("  " + fit("PROPERTY ID", 13) + fit("NAME", 30) + fit("LOCATION", 14) +
            fit("TYPE", 12) + fit("PRICE/NIGHT", 15) + fit("SLEEPS", 7) + "STATUS");
    io:println("  " + line("-", 100));
}

function printPropertyRow(Property property) {
    io:println("  " + fit(property.propertyId, 13) + fit(property.name, 30) +
            fit(property.location, 14) + fit(property.propertyType, 12) +
            fit(money(property.pricePerNight), 15) +
            fit(property.maxGuests.toString(), 7) + property.status);
}

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
    Create_usersStreamingClient streamingClient = check ep->create_users();

    io:println("");
    io:println(string `  Streaming ${batch.length()} profile(s) to the server...`);
    foreach int i in 0 ..< batch.length() {
        CreateUserRequest profile = batch[i];
        check streamingClient->sendCreateUserRequest(profile);
        io:println(string `    -> sent [${i + 1}] ${profile.name} (${profile.role})`);
    }
    check streamingClient->complete();
    io:println("  Stream closed; waiting for the server summary...");
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

    heading(string `AVAILABLE LISTINGS IN ${response.region}`);
    if response.remainingProperties.length() == 0 {
        io:println("  No available listings remain in that region.");
        return;
    }
    printPropertyHeader();
    foreach Property property in response.remainingProperties {
        printPropertyRow(property);
    }
    io:println("  " + line("-", 100));
    io:println(string `  ${response.remainingProperties.length()} listing(s).`);
}

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
    if item is grpc:Error {
        io:println("  " + line("-", 100));
        printError("The stream was interrupted: " + item.message());
        return;
    }
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
