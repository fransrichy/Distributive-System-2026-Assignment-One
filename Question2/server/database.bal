// ============================================================================
//  DSA612S - Assignment 1 - Question 2
//  Rental Accommodation System - gRPC Server
//  ---------------------------------------------------------------------------
//  database.bal
//  ---------------------------------------------------------------------------
//  The *persistence and utility layer*. It owns every piece of mutable state
//  in the server and exposes it only through small, single-purpose functions.
//
//  THE STORE
//  ---------
//  All four collections live inside a single `Datastore` record:
//
//    properties - map<Property> keyed by propertyId, the listing catalogue
//    hosts      - map<Host>     keyed by hostId
//    guests     - map<Guest>    keyed by guestId
//    bookings   - map<Booking>  keyed by bookingId, cart + confirmed
//
//  Maps are used rather than keyed tables because the record types come from
//  the generated Protocol Buffer stub, and a `table<T> key(k)` requires `k` to
//  be declared `readonly` inside `T` - something a generated proto record
//  never is. The assignment explicitly permits either structure, and a map
//  gives the same O(1) primary key access.
//
//  One store holds both PENDING (the temporary "booking cart") and CONFIRMED
//  bookings. `state` distinguishes them, which keeps overlap detection to one
//  pass over one collection.
//
//  WHY ONE RECORD RATHER THAN FOUR VARIABLES
//  -----------------------------------------
//  Ballerina allows a single `lock` statement to touch only *one* variable
//  whose usage is restricted (that is, one `isolated` module-level variable).
//  `confirmBookingAtomic` has to read the property catalogue and write the
//  booking store in the same critical section, so those two collections must
//  live behind the same lock. Folding all four - and the identifier counters -
//  into one `Datastore` satisfies the compiler *and* gives the stronger
//  guarantee: the entire confirmation sequence is atomic with respect to
//  everything else in the system.
//
//  CONCURRENCY
//  -----------
//  A gRPC server handles every call on its own strand, so the store is
//  genuinely shared mutable state. It is declared `isolated`, which makes the
//  compiler reject any access that is not inside a `lock` block. Values are
//  `clone()`d across the lock boundary so no caller can ever hold a live
//  reference into it. Read-modify-write sequences that must be atomic - above
//  all `confirmBookingAtomic` - run the whole sequence inside a single `lock`,
//  which is what stops two guests confirming overlapping stays at the same
//  instant.
//
//  Sections
//    1. The store and identifier generation
//    2. Calendar utilities
//    3. Validation helpers
//    4. Property data access
//    5. User data access
//    6. Booking data access (including the atomic confirmation)
//    7. Seed data
// ============================================================================

import ballerina/time;

// ============================================================================
//  SECTION 1 - THE STORE AND IDENTIFIER GENERATION
// ============================================================================

# Everything the server remembers, in one lockable unit.
#
# + properties - The listing catalogue, keyed by `propertyId`.
# + hosts - Registered host profiles, keyed by `hostId`.
# + guests - Registered guest profiles, keyed by `guestId`.
# + bookings - Cart entries and confirmed reservations, keyed by `bookingId`.
# + propertySequence - Counter behind generated property identifiers.
# + hostSequence - Counter behind generated host identifiers.
# + guestSequence - Counter behind generated guest identifiers.
# + bookingSequence - Counter behind generated booking identifiers.
type Datastore record {|
    map<Property> properties = {};
    map<Host> hosts = {};
    map<Guest> guests = {};
    map<Booking> bookings = {};
    int propertySequence = 100;
    int hostSequence = 100;
    int guestSequence = 100;
    int bookingSequence = 1000;
|};

# The one and only piece of mutable state in the server.
isolated Datastore db = {};

# Issues the next unique property identifier, e.g. `PROP-101`.
#
# + return - A fresh property identifier.
public isolated function nextPropertyId() returns string {
    lock {
        db.propertySequence += 1;
        return string `PROP-${db.propertySequence}`;
    }
}

# Issues the next unique host identifier, e.g. `HOST-101`.
#
# + return - A fresh host identifier.
public isolated function nextHostId() returns string {
    lock {
        db.hostSequence += 1;
        return string `HOST-${db.hostSequence}`;
    }
}

# Issues the next unique guest identifier, e.g. `GUEST-101`.
#
# + return - A fresh guest identifier.
public isolated function nextGuestId() returns string {
    lock {
        db.guestSequence += 1;
        return string `GUEST-${db.guestSequence}`;
    }
}

# Issues the next unique booking identifier, e.g. `BKG-1001`.
#
# + return - A fresh booking identifier.
public isolated function nextBookingId() returns string {
    lock {
        db.bookingSequence += 1;
        return string `BKG-${db.bookingSequence}`;
    }
}

// ============================================================================
//  SECTION 2 - CALENDAR UTILITIES
// ============================================================================

# Left pads a number below ten with a zero.
#
# + value - The number to render.
# + return - A two character string.
isolated function pad2(int value) returns string {
    return value < 10 ? string `0${value}` : value.toString();
}

# Days in a month, honouring leap years.
#
# + year - Four digit calendar year.
# + month - Month number 1..12.
# + return - The number of days in that month.
isolated function daysInMonth(int year, int month) returns int {
    match month {
        1|3|5|7|8|10|12 => {
            return 31;
        }
        4|6|9|11 => {
            return 30;
        }
    }
    boolean isLeap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    return isLeap ? 29 : 28;
}

# Parses a strict ISO-8601 date (`YYYY-MM-DD`) into midnight UTC.
#
# + value - The candidate date string.
# + fieldName - Name of the field, used to build the error message.
# + return - The instant, or an error describing what is wrong.
public isolated function parseDate(string value, string fieldName) returns time:Utc|error {
    string raw = value.trim();
    if raw.length() != 10 || raw.substring(4, 5) != "-" || raw.substring(7, 8) != "-" {
        return error(string `'${fieldName}' must be an ISO-8601 date (YYYY-MM-DD), received '${value}'.`);
    }

    int|error year = int:fromString(raw.substring(0, 4));
    int|error month = int:fromString(raw.substring(5, 7));
    int|error day = int:fromString(raw.substring(8, 10));
    if year is error || month is error || day is error {
        return error(string `'${fieldName}' contains non numeric characters: '${value}'.`);
    }
    if year < 1900 || year > 2200 {
        return error(string `'${fieldName}' has an out of range year: ${year}.`);
    }
    if month < 1 || month > 12 {
        return error(string `'${fieldName}' has an invalid month: ${month}.`);
    }
    if day < 1 || day > daysInMonth(year, month) {
        return error(string `'${fieldName}' has an invalid day for that month: ${day}.`);
    }

    time:Civil civil = {
        year: year,
        month: month,
        day: day,
        hour: 0,
        minute: 0,
        second: 0d,
        utcOffset: {hours: 0, minutes: 0}
    };
    time:Utc|time:Error instant = time:utcFromCivil(civil);
    if instant is time:Error {
        return error(string `'${fieldName}' could not be converted: ${instant.message()}`);
    }
    return instant;
}

# Renders an instant as an ISO-8601 calendar date.
#
# + instant - The instant to render.
# + return - A `YYYY-MM-DD` string.
isolated function formatDate(time:Utc instant) returns string {
    time:Civil civil = time:utcToCivil(instant);
    return string `${civil.year}-${pad2(civil.month)}-${pad2(civil.day)}`;
}

# Today's date on the server clock.
#
# + return - A `YYYY-MM-DD` string.
public isolated function today() returns string {
    return formatDate(time:utcNow());
}

# An RFC-3339 style timestamp, used to stamp confirmations.
#
# + return - A timestamp such as `2026-08-05T14:32:07Z`.
public isolated function nowTimestamp() returns string {
    time:Civil civil = time:utcToCivil(time:utcNow());
    decimal seconds = civil.second ?: 0d;
    int wholeSeconds = <int>seconds.floor();
    return string `${civil.year}-${pad2(civil.month)}-${pad2(civil.day)}` +
        string `T${pad2(civil.hour)}:${pad2(civil.minute)}:${pad2(wholeSeconds)}Z`;
}

# Adds whole days to an ISO-8601 date.
#
# + isoDate - The starting date.
# + days - Days to add; may be negative.
# + return - The shifted date, or an error when `isoDate` is malformed.
public isolated function addDays(string isoDate, int days) returns string|error {
    time:Utc instant = check parseDate(isoDate, "date");
    return formatDate(time:utcAddSeconds(instant, <decimal>days * 86400d));
}

# Counts the nights between an arrival and a departure date.
#
# `checkIn` is inclusive and `checkOut` is exclusive, which is the standard
# hospitality convention: arriving on the 1st and leaving on the 4th is three
# nights, not four.
#
# + checkIn - ISO-8601 arrival date.
# + checkOut - ISO-8601 departure date.
# + return - The night count, or an error when either date is malformed.
public isolated function countNights(string checkIn, string checkOut) returns int|error {
    time:Utc arrival = check parseDate(checkIn, "checkIn");
    time:Utc departure = check parseDate(checkOut, "checkOut");
    decimal diffSeconds = time:utcDiffSeconds(departure, arrival);
    return <int>(diffSeconds / 86400d);
}

# Tests whether two half-open date ranges overlap.
#
# Two stays `[aIn, aOut)` and `[bIn, bOut)` collide exactly when
# `aIn < bOut && bIn < aOut`. Because the dates are zero padded ISO-8601
# strings, a plain lexicographic comparison is equivalent to a calendar
# comparison, so no parsing is needed on this hot path.
#
# + aIn - Arrival of the first stay.
# + aOut - Departure of the first stay.
# + bIn - Arrival of the second stay.
# + bOut - Departure of the second stay.
# + return - `true` when the two stays cannot both happen.
public isolated function rangesOverlap(string aIn, string aOut, string bIn, string bOut)
        returns boolean {
    return aIn < bOut && bIn < aOut;
}

# Rounds a monetary amount to two decimal places.
#
# + amount - The raw amount.
# + return - The amount rounded to cents.
public isolated function roundMoney(float amount) returns float {
    return (amount * 100.0).round() / 100.0;
}

// ============================================================================
//  SECTION 3 - VALIDATION HELPERS
// ============================================================================

# Rejects empty or whitespace-only strings.
#
# + value - The value under test.
# + fieldName - Name of the field, used in the message.
# + return - An error when blank, otherwise `()`.
public isolated function requireNonBlank(string value, string fieldName) returns error? {
    if value.trim().length() == 0 {
        return error(string `'${fieldName}' is required and must not be blank.`);
    }
    return ();
}

# Rejects an email address that has no `@`, or no dot after it. Deliberately
# permissive: the goal is to catch typing mistakes, not to police RFC 5322.
#
# + value - The candidate address.
# + return - An error when the address is obviously malformed, otherwise `()`.
public isolated function validateEmail(string value) returns error? {
    string email = value.trim();
    check requireNonBlank(email, "email");
    int? at = email.indexOf("@");
    if at is () || at == 0 || at == email.length() - 1 {
        return error(string `'${email}' is not a valid email address.`);
    }
    if !email.substring(at + 1).includes(".") {
        return error(string `'${email}' is not a valid email address.`);
    }
    return ();
}

# Validates the date range of a stay against the calendar and against today.
#
# + checkIn - ISO-8601 arrival date.
# + checkOut - ISO-8601 departure date.
# + return - The number of nights, or an error explaining the rejection.
public isolated function validateStay(string checkIn, string checkOut) returns int|error {
    check requireNonBlank(checkIn, "checkIn");
    check requireNonBlank(checkOut, "checkOut");
    _ = check parseDate(checkIn, "checkIn");
    _ = check parseDate(checkOut, "checkOut");

    if checkOut.trim() <= checkIn.trim() {
        return error(string `'checkOut' (${checkOut}) must be strictly after 'checkIn' (${checkIn}).`);
    }
    if checkIn.trim() < today() {
        return error(string `'checkIn' (${checkIn}) is in the past; today is ${today()}.`);
    }

    int nights = check countNights(checkIn, checkOut);
    if nights <= 0 {
        return error("A stay must cover at least one night.");
    }
    if nights > 365 {
        return error(string `A stay may not exceed 365 nights; ${nights} were requested.`);
    }
    return nights;
}

// ============================================================================
//  SECTION 4 - PROPERTY DATA ACCESS
// ============================================================================

# Stores a new listing.
#
# + property - The listing to store; its id must be free.
# + return - A detached copy of what was stored, or an error on a clash.
public isolated function insertProperty(Property property) returns Property|error {
    lock {
        if db.properties.hasKey(property.propertyId) {
            return error(string `Property '${property.propertyId}' already exists.`);
        }
        db.properties[property.propertyId] = property.clone();
        return property.clone();
    }
}

# Reads one listing.
#
# + propertyId - The key to look up.
# + return - A detached copy, or `()` when the id is unknown.
public isolated function findProperty(string propertyId) returns Property? {
    lock {
        Property? found = db.properties[propertyId];
        return found is () ? () : found.clone();
    }
}

# Overwrites an existing listing.
#
# + property - The full replacement value.
# + return - A detached copy of what was stored, or an error when unknown.
public isolated function saveProperty(Property property) returns Property|error {
    lock {
        if !db.properties.hasKey(property.propertyId) {
            return error(string `Property '${property.propertyId}' does not exist.`);
        }
        db.properties[property.propertyId] = property.clone();
        return property.clone();
    }
}

# Deletes a listing.
#
# + propertyId - The key to remove.
# + return - A detached copy of the removed row, or an error when unknown.
public isolated function deleteProperty(string propertyId) returns Property|error {
    lock {
        if !db.properties.hasKey(propertyId) {
            return error(string `Property '${propertyId}' does not exist.`);
        }
        Property removed = db.properties.remove(propertyId);
        return removed.clone();
    }
}

# Every listing in the catalogue.
#
# + return - A detached snapshot, ordered by id.
public isolated function allProperties() returns Property[] {
    lock {
        Property[] rows = from Property p in db.properties
            order by p.propertyId ascending
            select p;
        return rows.clone();
    }
}

# Every listing that belongs to one host.
#
# + hostId - The owning host.
# + return - A detached snapshot, ordered by id.
public isolated function propertiesOfHost(string hostId) returns Property[] {
    lock {
        Property[] rows = from Property p in db.properties
            where p.hostId == hostId
            order by p.propertyId ascending
            select p;
        return rows.clone();
    }
}

# Every listing a host still has in one region, used by `remove_property`.
#
# + hostId - The owning host.
# + region - The region to narrow by; blank means every region.
# + return - A detached snapshot, ordered by id.
public isolated function propertiesOfHostInRegion(string hostId, string region) returns Property[] {
    string needle = region.trim().toLowerAscii();
    lock {
        Property[] rows = from Property p in db.properties
            where p.hostId == hostId &&
                (needle.length() == 0 || p.location.trim().toLowerAscii() == needle)
            order by p.propertyId ascending
            select p;
        return rows.clone();
    }
}

# Applies the `list_available_properties` filters.
#
# Only `AVAILABLE` listings are ever returned - an unavailable or under
# maintenance listing is not something a guest can rent.
#
# + request - The filter criteria; blank / zero fields mean "no filter".
# + return - A detached snapshot of the matching listings, cheapest first.
public isolated function searchAvailable(ListAvailableRequest request) returns Property[] {
    string location = request.location.trim().toLowerAscii();
    string propertyType = request.propertyType.trim().toLowerAscii();
    float minPrice = request.minPrice;
    float maxPrice = request.maxPrice;
    int minGuests = request.minGuests;

    lock {
        Property[] rows = from Property p in db.properties
            where p.status == AVAILABLE
                && (location.length() == 0 || p.location.trim().toLowerAscii().includes(location))
                && (propertyType.length() == 0 || p.propertyType.trim().toLowerAscii() == propertyType)
                && p.pricePerNight >= minPrice
                && (maxPrice <= 0.0 || p.pricePerNight <= maxPrice)
                && (minGuests <= 0 || p.maxGuests >= minGuests)
            order by p.pricePerNight ascending
            select p;
        return rows.clone();
    }
}

# The number of listings currently held.
#
# + return - The entry count.
public isolated function countProperties() returns int {
    lock {
        return db.properties.length();
    }
}

// ============================================================================
//  SECTION 5 - USER DATA ACCESS
// ============================================================================

# Stores a host profile.
#
# + host - The profile to store.
# + return - A detached copy, or an error when the id is taken.
public isolated function insertHost(Host host) returns Host|error {
    lock {
        if db.hosts.hasKey(host.hostId) {
            return error(string `Host '${host.hostId}' already exists.`);
        }
        db.hosts[host.hostId] = host.clone();
        return host.clone();
    }
}

# Stores a guest profile.
#
# + guest - The profile to store.
# + return - A detached copy, or an error when the id is taken.
public isolated function insertGuest(Guest guest) returns Guest|error {
    lock {
        if db.guests.hasKey(guest.guestId) {
            return error(string `Guest '${guest.guestId}' already exists.`);
        }
        db.guests[guest.guestId] = guest.clone();
        return guest.clone();
    }
}

# Reads one host profile.
#
# + hostId - The key to look up.
# + return - A detached copy, or `()` when unknown.
public isolated function findHost(string hostId) returns Host? {
    lock {
        Host? found = db.hosts[hostId];
        return found is () ? () : found.clone();
    }
}

# Reads one guest profile.
#
# + guestId - The key to look up.
# + return - A detached copy, or `()` when unknown.
public isolated function findGuest(string guestId) returns Guest? {
    lock {
        Guest? found = db.guests[guestId];
        return found is () ? () : found.clone();
    }
}

# Every host profile, ordered by id.
#
# + return - A detached snapshot.
public isolated function allHosts() returns Host[] {
    lock {
        Host[] rows = from Host h in db.hosts
            order by h.hostId ascending
            select h;
        return rows.clone();
    }
}

# Every guest profile, ordered by id.
#
# + return - A detached snapshot.
public isolated function allGuests() returns Guest[] {
    lock {
        Guest[] rows = from Guest g in db.guests
            order by g.guestId ascending
            select g;
        return rows.clone();
    }
}

# Tests whether an email address is already registered by a host or a guest.
#
# + email - The address to probe, matched case insensitively.
# + return - `true` when the address is already in use.
public isolated function emailInUse(string email) returns boolean {
    string needle = email.trim().toLowerAscii();
    lock {
        foreach Host h in db.hosts {
            if h.email.trim().toLowerAscii() == needle {
                return true;
            }
        }
        foreach Guest g in db.guests {
            if g.email.trim().toLowerAscii() == needle {
                return true;
            }
        }
        return false;
    }
}

// ============================================================================
//  SECTION 6 - BOOKING DATA ACCESS
// ============================================================================

# Adds a booking row, normally in the PENDING (cart) state.
#
# + booking - The row to add.
# + return - A detached copy, or an error when the id is taken.
public isolated function insertBooking(Booking booking) returns Booking|error {
    lock {
        if db.bookings.hasKey(booking.bookingId) {
            return error(string `Booking '${booking.bookingId}' already exists.`);
        }
        db.bookings[booking.bookingId] = booking.clone();
        return booking.clone();
    }
}

# Reads one booking.
#
# + bookingId - The key to look up.
# + return - A detached copy, or `()` when unknown.
public isolated function findBooking(string bookingId) returns Booking? {
    lock {
        Booking? found = db.bookings[bookingId];
        return found is () ? () : found.clone();
    }
}

# Every booking, newest first.
#
# + return - A detached snapshot.
public isolated function allBookings() returns Booking[] {
    lock {
        Booking[] rows = from Booking b in db.bookings
            order by b.bookingId descending
            select b;
        return rows.clone();
    }
}

# The pending cart entries of one guest.
#
# + guestId - The guest whose cart to read.
# + return - A detached snapshot of the guest's cart.
public isolated function cartOf(string guestId) returns Booking[] {
    lock {
        Booking[] rows = from Booking b in db.bookings
            where b.guestId == guestId && b.state == PENDING
            order by b.bookingId ascending
            select b;
        return rows.clone();
    }
}

# Tests whether a proposed stay clashes with an already CONFIRMED booking.
#
# Only confirmed rows block a date range: a pending cart entry is a wish, not
# a reservation, so two guests may hold overlapping carts and the first one to
# confirm wins.
#
# + propertyId - The listing being checked.
# + checkIn - Proposed arrival.
# + checkOut - Proposed departure.
# + return - `true` when a confirmed booking already covers part of the range.
public isolated function hasConfirmedClash(string propertyId, string checkIn, string checkOut)
        returns boolean {
    lock {
        foreach Booking b in db.bookings {
            if b.propertyId == propertyId && b.state == CONFIRMED
                    && rangesOverlap(checkIn, checkOut, b.checkIn, b.checkOut) {
                return true;
            }
        }
        return false;
    }
}

# Finalises a pending cart entry.
#
# THIS IS THE CRITICAL SECTION OF THE WHOLE SERVER. The availability re-check,
# the price calculation, the state transition and the clearing of the guest's
# cart all happen inside one `lock`, so two guests racing to confirm
# overlapping stays on the same property can never both succeed: whichever
# strand acquires the lock first wins, and the second one sees the freshly
# written CONFIRMED row and is rejected.
#
# + bookingId - The cart entry to finalise.
# + guestId - The guest that owns the cart entry, for an ownership check.
# + return - The confirmed booking, or an error explaining the rejection.
public isolated function confirmBookingAtomic(string bookingId, string guestId)
        returns Booking|error {
    lock {
        // ---- 1. The cart entry must exist and belong to this guest -----
        Booking? candidate = db.bookings[bookingId];
        if candidate is () {
            return error(string `No booking request found with id '${bookingId}'.`);
        }
        Booking booking = candidate.clone();

        if booking.guestId != guestId {
            return error(string `Booking '${bookingId}' does not belong to guest '${guestId}'.`);
        }
        if booking.state == CONFIRMED {
            return error(string `Booking '${bookingId}' has already been confirmed.`);
        }
        if booking.state != PENDING {
            return error(string `Booking '${bookingId}' is ${booking.state} and cannot be confirmed.`);
        }

        // ---- 2. The listing must still exist and still be available ----
        Property? listing = db.properties[booking.propertyId];
        if listing is () {
            return error(string `The property '${booking.propertyId}' has been removed by its host.`);
        }
        Property property = listing.clone();
        if property.status != AVAILABLE {
            return error(string `Property '${property.propertyId}' is ${property.status} ` +
                string `and can no longer be booked.`);
        }

        // ---- 3. No confirmed booking may overlap the requested dates ---
        foreach Booking other in db.bookings {
            if other.bookingId != bookingId && other.propertyId == booking.propertyId
                    && other.state == CONFIRMED
                    && rangesOverlap(booking.checkIn, booking.checkOut, other.checkIn, other.checkOut) {
                return error(string `Property '${property.propertyId}' is already booked from ` +
                    string `${other.checkIn} to ${other.checkOut}; the requested dates ` +
                    string `${booking.checkIn} to ${booking.checkOut} overlap it.`);
            }
        }

        // ---- 4. Price = nightly rate x number of nights ----------------
        int|error nights = countNights(booking.checkIn, booking.checkOut);
        if nights is error {
            return error(string `Stored dates on booking '${bookingId}' are invalid: ${nights.message()}`);
        }

        booking.nights = nights;
        booking.totalCost = roundMoney(property.pricePerNight * <float>nights);
        booking.state = CONFIRMED;
        booking.confirmedAt = nowTimestamp();
        booking.propertyName = property.name;
        db.bookings[bookingId] = booking.clone();

        // ---- 5. Clear the guest's temporary cart -----------------------
        // The brief requires the guest's temporary request to be cleared on
        // confirmation. The row just confirmed has already left the cart by
        // changing state; any *other* pending wish of the same guest that now
        // collides with the confirmed stay is dropped, because it can never
        // succeed.
        string[] doomed = [];
        foreach Booking other in db.bookings {
            if other.state == PENDING && other.guestId == guestId
                    && other.propertyId == booking.propertyId
                    && rangesOverlap(booking.checkIn, booking.checkOut, other.checkIn, other.checkOut) {
                doomed.push(other.bookingId);
            }
        }
        foreach string id in doomed {
            _ = db.bookings.remove(id);
        }

        return booking.clone();
    }
}

# Removes a pending cart entry outright.
#
# + bookingId - The cart entry to drop.
# + return - The removed row, or an error when it is unknown or confirmed.
public isolated function cancelPending(string bookingId) returns Booking|error {
    lock {
        Booking? found = db.bookings[bookingId];
        if found is () {
            return error(string `No booking found with id '${bookingId}'.`);
        }
        if found.state == CONFIRMED {
            return error(string `Booking '${bookingId}' is confirmed and cannot simply be dropped.`);
        }
        Booking removed = db.bookings.remove(bookingId);
        return removed.clone();
    }
}

# The number of bookings currently held, in any state.
#
# + return - The entry count.
public isolated function countBookings() returns int {
    lock {
        return db.bookings.length();
    }
}

// ============================================================================
//  SECTION 7 - SEED DATA
// ============================================================================

# Loads a small, realistic Namibian data set so that the client demo has
# something to search, book and confirm the moment the server starts.
#
# + return - The number of properties that were seeded.
public isolated function seedDatabase() returns int {
    Host[] hosts = [
        {
            hostId: "HOST-001",
            name: "Ndapewa Amutenya",
            email: "ndapewa@coastalstays.na",
            phone: "+264 81 123 4567",
            region: "Swakopmund"
        },
        {
            hostId: "HOST-002",
            name: "Johannes Shikongo",
            email: "johannes@kalaharilodges.na",
            phone: "+264 81 234 5678",
            region: "Windhoek"
        },
        {
            hostId: "HOST-003",
            name: "Maria Gaoses",
            email: "maria@etoshaviews.na",
            phone: "+264 81 345 6789",
            region: "Etosha"
        }
    ];

    Guest[] guests = [
        {
            guestId: "GUEST-001",
            name: "Tobias Nangolo",
            email: "tobias.nangolo@example.na",
            phone: "+264 85 111 2222"
        },
        {
            guestId: "GUEST-002",
            name: "Selma Iipinge",
            email: "selma.iipinge@example.na",
            phone: "+264 85 333 4444"
        },
        {
            guestId: "GUEST-003",
            name: "Petrus Haufiku",
            email: "petrus.haufiku@example.na",
            phone: "+264 85 555 6666"
        }
    ];

    Property[] properties = [
        {
            propertyId: "PROP-001",
            hostId: "HOST-001",
            name: "Atlantic Dune Apartment",
            location: "Swakopmund",
            propertyType: "APARTMENT",
            pricePerNight: 950.00,
            status: AVAILABLE,
            description: "Two bedroom apartment one block from the beachfront promenade.",
            maxGuests: 4,
            amenities: ["WIFI", "PARKING", "SEA_VIEW", "KITCHEN"]
        },
        {
            propertyId: "PROP-002",
            hostId: "HOST-001",
            name: "Mole Beach Cottage",
            location: "Swakopmund",
            propertyType: "COTTAGE",
            pricePerNight: 1250.00,
            status: AVAILABLE,
            description: "Restored colonial cottage with a walled garden and braai area.",
            maxGuests: 6,
            amenities: ["WIFI", "PARKING", "BRAAI", "PET_FRIENDLY"]
        },
        {
            propertyId: "PROP-003",
            hostId: "HOST-002",
            name: "Klein Windhoek Guesthouse",
            location: "Windhoek",
            propertyType: "GUESTHOUSE",
            pricePerNight: 780.00,
            status: AVAILABLE,
            description: "Quiet guesthouse ten minutes from the CBD, breakfast included.",
            maxGuests: 2,
            amenities: ["WIFI", "BREAKFAST", "PARKING", "POOL"]
        },
        {
            propertyId: "PROP-004",
            hostId: "HOST-002",
            name: "Auas Hills Villa",
            location: "Windhoek",
            propertyType: "VILLA",
            pricePerNight: 2400.00,
            status: AVAILABLE,
            description: "Four bedroom villa on the Auas escarpment with panoramic views.",
            maxGuests: 8,
            amenities: ["WIFI", "POOL", "PARKING", "AIR_CONDITIONING", "BRAAI"]
        },
        {
            propertyId: "PROP-005",
            hostId: "HOST-003",
            name: "Okaukuejo Safari Chalet",
            location: "Etosha",
            propertyType: "LODGE",
            pricePerNight: 3100.00,
            status: AVAILABLE,
            description: "Waterhole facing chalet inside the park's southern gate.",
            maxGuests: 4,
            amenities: ["WIFI", "GAME_DRIVES", "RESTAURANT", "AIR_CONDITIONING"]
        },
        {
            propertyId: "PROP-006",
            hostId: "HOST-003",
            name: "Namutoni Rest Camp Room",
            location: "Etosha",
            propertyType: "LODGE",
            pricePerNight: 1650.00,
            status: UNDER_MAINTENANCE,
            description: "Twin room in the historic fort; roof repairs until further notice.",
            maxGuests: 2,
            amenities: ["RESTAURANT", "PARKING"]
        }
    ];

    // A clash on re-seeding simply means the row is already present, which is
    // harmless, so the outcome of each insert is inspected rather than checked.
    foreach Host h in hosts {
        if insertHost(h) is error {
            continue;
        }
    }
    foreach Guest g in guests {
        if insertGuest(g) is error {
            continue;
        }
    }

    int inserted = 0;
    foreach Property p in properties {
        if insertProperty(p) is Property {
            inserted += 1;
        }
    }
    return inserted;
}
