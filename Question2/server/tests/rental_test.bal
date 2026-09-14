import ballerina/grpc;
import ballerina/test;

@test:Config {}
function testCalendarValidation() returns error? {
    test:assertEquals(check countNights("2028-02-28", "2028-03-01"), 2);
    test:assertEquals(check countNights("2100-02-28", "2100-03-01"), 1);
    test:assertEquals(check countNights("2026-12-31", "2027-01-01"), 1);
    test:assertTrue(parseDate("2027-02-29", "date") is error);
    test:assertTrue(parseDate("2028-+2-01", "date") is error);
    test:assertTrue(parseDate("2028-02-+1", "date") is error);
    test:assertTrue(parseDate("2028-04-31", "date") is error);
    test:assertFalse(rangesOverlap("2028-01-01", "2028-01-03", "2028-01-03", "2028-01-05"));
}

isolated function registerProfiles(RentalServiceClient rentalClient, CreateUserRequest[] users)
        returns CreateUsersSummary|error {
    Create_usersStreamingClient sender = check rentalClient->create_users();
    foreach CreateUserRequest user in users {
        check sender->sendCreateUserRequest(user);
    }
    check sender->complete();
    CreateUsersSummary? summary = check sender->receiveCreateUsersSummary();
    if summary is () {
        return error("The server returned no registration summary.");
    }
    return summary;
}

function collectProperties(RentalServiceClient rentalClient, ListAvailableRequest request)
        returns Property[]|error {
    stream<Property, grpc:Error?> results = check rentalClient->list_available_properties(request);
    Property[] properties = [];
    record {|Property value;|}|grpc:Error? row = results.next();
    while row is record {|Property value;|} {
        properties.push(row.value);
        row = results.next();
    }
    if row is grpc:Error {
        return row;
    }
    return properties;
}

function newListing(RentalServiceClient rentalClient, string hostId, string name,
        string location = "Test Coast", PropertyStatus status = AVAILABLE) returns Property|error {
    AddPropertyResponse response = check rentalClient->add_property({
        hostId, name, location, propertyType: "APARTMENT", pricePerNight: 100.5, status
    });
    test:assertTrue(response.success, response.message);
    test:assertTrue(response.propertyId.length() > 0);
    test:assertEquals(response.property.maxGuests, 1);
    return response.property;
}

@test:Config {}
function testAllRentalOperations() returns error? {
    RentalServiceClient rentalClient = check new (string `http://localhost:${serverPort}`);
    CreateUsersSummary registered = check registerProfiles(rentalClient, [
                {userId: "TEST-HOST-A", name: "Host A", email: "hosta@tests.na", role: HOST, region: "Test Coast"},
                {userId: "TEST-HOST-B", name: "Host B", email: "hostb@tests.na", role: HOST, region: "Test Coast"},
                {userId: "TEST-GUEST-A", name: "Guest A", email: "guesta@tests.na", role: GUEST},
                {userId: "TEST-GUEST-B", name: "Guest B", email: "guestb@tests.na", role: GUEST},
                {name: "Invalid email", email: "invalid", role: GUEST},
                {name: "Invalid role", email: "role@tests.na"},
                {name: "Duplicate email", email: "HOSTA@tests.na", role: GUEST},
                {userId: "TEST-HOST-A", name: "Duplicate id", email: "duplicateid@tests.na", role: GUEST}
            ]);
    test:assertTrue(registered.success);
    test:assertEquals(registered.totalReceived, 8);
    test:assertEquals(registered.hostsCreated, 2);
    test:assertEquals(registered.guestsCreated, 2);
    test:assertEquals(registered.failures.length(), 4);
    test:assertEquals(registered.createdIds.length(), 4);
    CreateUsersSummary empty = check registerProfiles(rentalClient, []);
    test:assertFalse(empty.success);
    test:assertEquals(empty.totalReceived, 0);

    Property removable = check newListing(rentalClient, "TEST-HOST-A", "Delete me");
    Property property = check newListing(rentalClient, "TEST-HOST-B", "Book me");
    Property unavailable = check newListing(rentalClient, "TEST-HOST-A", "Closed", "Test Coast", UNAVAILABLE);
    Property elsewhere = check newListing(rentalClient, "TEST-HOST-B", "Other region", "Test Inland");
    test:assertTrue(removable.propertyId != property.propertyId);
    AddPropertyResponse unknownHost = check rentalClient->add_property({
        hostId: "MISSING", name: "Missing host", location: "Test Coast", propertyType: "LODGE", pricePerNight: 100.0
    });
    test:assertFalse(unknownHost.success);
    foreach float invalidPrice in [-1.0, 0.0, 0.001, float:NaN, float:Infinity] {
        AddPropertyResponse invalid = check rentalClient->add_property({
            hostId: "TEST-HOST-A", name: "Invalid", location: "Test Coast",
            propertyType: "LODGE", pricePerNight: invalidPrice
        });
        test:assertFalse(invalid.success);
    }
    UpdatePropertyResponse wrongOwner = check rentalClient->update_property({
        propertyId: property.propertyId, hostId: "TEST-HOST-A", pricePerNight: 10.0
    });
    test:assertFalse(wrongOwner.success);
    foreach float invalidPrice in [-1.0, 0.001, 1000001.0, float:NaN, float:Infinity] {
        UpdatePropertyResponse invalid = check rentalClient->update_property({
            propertyId: property.propertyId, hostId: property.hostId, pricePerNight: invalidPrice
        });
        test:assertFalse(invalid.success);
    }
    UpdatePropertyResponse badCapacity = check rentalClient->update_property({
        propertyId: property.propertyId, hostId: property.hostId, maxGuests: -2
    });
    test:assertFalse(badCapacity.success);
    UpdatePropertyResponse updated = check rentalClient->update_property({
        propertyId: property.propertyId, hostId: property.hostId, pricePerNight: 110.25, maxGuests: 3
    });
    test:assertTrue(updated.success, updated.message);
    test:assertEquals(updated.property.name, "Book me");
    SearchPropertyResponse found = check rentalClient->search_property({propertyId: property.propertyId});
    test:assertTrue(found.found);
    test:assertEquals(found.status, "AVAILABLE");
    test:assertEquals(found.property.pricePerNight, 110.25);
    SearchPropertyResponse closed = check rentalClient->search_property({propertyId: unavailable.propertyId});
    test:assertEquals(closed.status, "NOT AVAILABLE");
    SearchPropertyResponse missing = check rentalClient->search_property({propertyId: "MISSING"});
    test:assertFalse(missing.found);
    test:assertEquals(missing.status, "NOT AVAILABLE");

    Property[] allAvailable = check collectProperties(rentalClient, {location: "test coast"});
    test:assertEquals(allAvailable.length(), 2);
    Property[] filtered = check collectProperties(rentalClient, {
                                                        location: "TEST COAST", minPrice: 105.0, maxPrice: 120.0, propertyType: "apartment", minGuests: 3
                                                    });
    test:assertEquals(filtered.length(), 1);
    test:assertEquals(filtered[0].propertyId, property.propertyId);
    test:assertEquals((check collectProperties(rentalClient, {location: "NO SUCH PLACE"})).length(), 0);
    test:assertTrue(collectProperties(rentalClient, {minPrice: 200.0, maxPrice: 100.0}) is error);
    test:assertTrue(collectProperties(rentalClient, {minPrice: -1.0}) is error);
    test:assertTrue(collectProperties(rentalClient, {maxPrice: float:NaN}) is error);

    RemovePropertyResponse denied = check rentalClient->remove_property({
        propertyId: removable.propertyId, hostId: "TEST-HOST-B"
    });
    test:assertFalse(denied.success);
    RemovePropertyResponse removed = check rentalClient->remove_property({
        propertyId: removable.propertyId, hostId: removable.hostId
    });
    test:assertTrue(removed.success, removed.message);
    test:assertEquals(removed.region, "Test Coast");
    test:assertEquals(removed.remainingProperties.length(), 1);
    test:assertEquals(removed.remainingProperties[0].propertyId, property.propertyId);
    test:assertTrue(removed.remainingProperties[0].hostId != removable.hostId);
    SearchPropertyResponse deleted = check rentalClient->search_property({propertyId: removable.propertyId});
    test:assertFalse(deleted.found);

    string arrival = check addDays(today(), 30);
    string departure = check addDays(arrival, 3);
    foreach string invalidDeparture in [arrival, check addDays(arrival, -1), "2027-02-29", "2028-+2-01"] {
        BookPropertyResponse invalid = check rentalClient->book_property({
            propertyId: property.propertyId, guestId: "TEST-GUEST-A", checkIn: arrival, checkOut: invalidDeparture
        });
        test:assertFalse(invalid.success);
    }
    BookPropertyResponse past = check rentalClient->book_property({
        propertyId: property.propertyId, guestId: "TEST-GUEST-A", checkIn: check addDays(today(), -1), checkOut: departure
    });
    test:assertFalse(past.success);
    BookPropertyResponse unavailableStay = check rentalClient->book_property({
        propertyId: unavailable.propertyId, guestId: "TEST-GUEST-A", checkIn: arrival, checkOut: departure
    });
    test:assertFalse(unavailableStay.success);
    BookPropertyResponse cartA = check rentalClient->book_property({
        propertyId: property.propertyId, guestId: "TEST-GUEST-A", checkIn: arrival, checkOut: departure
    });
    BookPropertyResponse cartB = check rentalClient->book_property({
        propertyId: property.propertyId, guestId: "TEST-GUEST-B", checkIn: arrival, checkOut: departure
    });
    test:assertTrue(cartA.success, cartA.message);
    test:assertTrue(cartB.success, cartB.message);
    test:assertEquals(cartA.nights, 3);
    test:assertEquals(cartA.estimatedCost, 330.75);
    BookPropertyResponse duplicate = check rentalClient->book_property({
        propertyId: property.propertyId, guestId: "TEST-GUEST-A", checkIn: arrival, checkOut: departure
    });
    test:assertFalse(duplicate.success);
    ConfirmBookingResponse wrongGuest = check rentalClient->confirm_booking({bookingId: cartA.bookingId, guestId: "TEST-GUEST-B"});
    test:assertFalse(wrongGuest.success);
    UpdatePropertyResponse repriced = check rentalClient->update_property({
        propertyId: property.propertyId, hostId: property.hostId, pricePerNight: 111.25
    });
    test:assertTrue(repriced.success);
    future<ConfirmBookingResponse|grpc:Error> first = start rentalClient->confirm_booking({
        bookingId: cartA.bookingId, guestId: "TEST-GUEST-A"
    });
    future<ConfirmBookingResponse|grpc:Error> second = start rentalClient->confirm_booking({
        bookingId: cartB.bookingId, guestId: "TEST-GUEST-B"
    });
    ConfirmBookingResponse resultA = check wait first;
    ConfirmBookingResponse resultB = check wait second;
    test:assertTrue(resultA.success != resultB.success, "Exactly one competing reservation must confirm.");
    Booking winner = resultA.success ? resultA.booking : resultB.booking;
    test:assertEquals(winner.nights, 3);
    test:assertEquals(winner.totalCost, 333.75);
    test:assertEquals(winner.state, CONFIRMED);
    test:assertTrue(winner.confirmedAt.length() > 0);
    test:assertEquals(cartOf(winner.guestId).length(), 0);
    ConfirmBookingResponse reconfirmed = check rentalClient->confirm_booking({
        bookingId: winner.bookingId, guestId: winner.guestId
    });
    test:assertFalse(reconfirmed.success);
    RemovePropertyResponse removalBlocked = check rentalClient->remove_property({
        propertyId: property.propertyId, hostId: property.hostId
    });
    test:assertFalse(removalBlocked.success);
    BookPropertyResponse alreadyTaken = check rentalClient->book_property({
        propertyId: property.propertyId, guestId: "TEST-GUEST-A", checkIn: arrival, checkOut: departure
    });
    test:assertFalse(alreadyTaken.success);
    BookPropertyResponse adjacent = check rentalClient->book_property({
        propertyId: property.propertyId, guestId: "TEST-GUEST-A", checkIn: departure, checkOut: check addDays(departure, 1)
    });
    test:assertTrue(adjacent.success, adjacent.message);
    ConfirmBookingResponse adjacentConfirmed = check rentalClient->confirm_booking({
        bookingId: adjacent.bookingId, guestId: "TEST-GUEST-A"
    });
    test:assertTrue(adjacentConfirmed.success);

    BookPropertyResponse pending = check rentalClient->book_property({
        propertyId: elsewhere.propertyId, guestId: "TEST-GUEST-A", checkIn: arrival, checkOut: departure
    });
    test:assertTrue(pending.success);
    UpdatePropertyResponse closedForMaintenance = check rentalClient->update_property({
        propertyId: elsewhere.propertyId, hostId: elsewhere.hostId, status: UNDER_MAINTENANCE
    });
    test:assertTrue(closedForMaintenance.success);
    ConfirmBookingResponse blockedByStatus = check rentalClient->confirm_booking({
        bookingId: pending.bookingId, guestId: "TEST-GUEST-A"
    });
    test:assertFalse(blockedByStatus.success);
    RemovePropertyResponse delisted = check rentalClient->remove_property({
        propertyId: elsewhere.propertyId, hostId: elsewhere.hostId
    });
    test:assertTrue(delisted.success);
    ConfirmBookingResponse blockedByRemoval = check rentalClient->confirm_booking({
        bookingId: pending.bookingId, guestId: "TEST-GUEST-A"
    });
    test:assertFalse(blockedByRemoval.success);
}

@test:Config {dependsOn: [testAllRentalOperations]}
function testConcurrentUpdatesAndRegistration() returns error? {
    RentalServiceClient rentalClient = check new (string `http://localhost:${serverPort}`);
    Property listing = check newListing(rentalClient, "TEST-HOST-A", "Before concurrent patches");
    future<UpdatePropertyResponse|grpc:Error> price = start rentalClient->update_property({
        propertyId: listing.propertyId, hostId: listing.hostId, pricePerNight: 567.89
    });
    future<UpdatePropertyResponse|grpc:Error> name = start rentalClient->update_property({
        propertyId: listing.propertyId, hostId: listing.hostId, name: "After concurrent patches"
    });
    UpdatePropertyResponse pricePatch = check wait price;
    UpdatePropertyResponse namePatch = check wait name;
    test:assertTrue(pricePatch.success);
    test:assertTrue(namePatch.success);
    SearchPropertyResponse result = check rentalClient->search_property({propertyId: listing.propertyId});
    test:assertEquals(result.property.pricePerNight, 567.89);
    test:assertEquals(result.property.name, "After concurrent patches");
    future<CreateUsersSummary|error> first = start registerProfiles(rentalClient, [
                {name: "Concurrent guest A", email: "concurrent@tests.na", role: GUEST}
            ]);
    future<CreateUsersSummary|error> second = start registerProfiles(rentalClient, [
                {name: "Concurrent guest B", email: "CONCURRENT@tests.na", role: GUEST}
            ]);
    CreateUsersSummary resultA = check wait first;
    CreateUsersSummary resultB = check wait second;
    test:assertEquals(resultA.guestsCreated + resultB.guestsCreated, 1);
    test:assertEquals(resultA.failures.length() + resultB.failures.length(), 1);
}
