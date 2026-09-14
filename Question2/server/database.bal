import ballerina/time;

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

// One lock covers properties and bookings so confirmation cannot race with deletion.
isolated Datastore db = {};

public isolated function nextPropertyId() returns string {
    lock {
        db.propertySequence += 1;
        return string `PROP-${db.propertySequence}`;
    }
}

public isolated function nextHostId() returns string {
    lock {
        db.hostSequence += 1;
        return string `HOST-${db.hostSequence}`;
    }
}

public isolated function nextGuestId() returns string {
    lock {
        db.guestSequence += 1;
        return string `GUEST-${db.guestSequence}`;
    }
}

public isolated function nextBookingId() returns string {
    lock {
        db.bookingSequence += 1;
        return string `BKG-${db.bookingSequence}`;
    }
}

isolated function pad2(int value) returns string {
    return value < 10 ? string `0${value}` : value.toString();
}

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

public isolated function parseDate(string value, string fieldName) returns time:Utc|error {
    string raw = value.trim();
    if raw.length() != 10 || raw.substring(4, 5) != "-" || raw.substring(7, 8) != "-" {
        return error(string `'${fieldName}' must be an ISO-8601 date (YYYY-MM-DD), received '${value}'.`);
    }
    foreach int index in 0 ..< raw.length() {
        if index != 4 && index != 7 {
            string digit = raw.substring(index, index + 1);
            if digit < "0" || digit > "9" {
                return error(string `'${fieldName}' must contain digits in YYYY-MM-DD format.`);
            }
        }
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

isolated function formatDate(time:Utc instant) returns string {
    time:Civil civil = time:utcToCivil(instant);
    return string `${civil.year}-${pad2(civil.month)}-${pad2(civil.day)}`;
}

public isolated function today() returns string {
    return formatDate(time:utcNow());
}

public isolated function nowTimestamp() returns string {
    time:Civil civil = time:utcToCivil(time:utcNow());
    decimal seconds = civil.second ?: 0d;
    int wholeSeconds = <int>seconds.floor();
    return string `${civil.year}-${pad2(civil.month)}-${pad2(civil.day)}` +
        string `T${pad2(civil.hour)}:${pad2(civil.minute)}:${pad2(wholeSeconds)}Z`;
}

public isolated function addDays(string isoDate, int days) returns string|error {
    time:Utc instant = check parseDate(isoDate, "date");
    return formatDate(time:utcAddSeconds(instant, <decimal>days * 86400d));
}

public isolated function countNights(string checkIn, string checkOut) returns int|error {
    time:Utc arrival = check parseDate(checkIn, "checkIn");
    time:Utc departure = check parseDate(checkOut, "checkOut");
    decimal diffSeconds = time:utcDiffSeconds(departure, arrival);
    return <int>(diffSeconds / 86400d);
}

public isolated function rangesOverlap(string aIn, string aOut, string bIn, string bOut)
        returns boolean {
    // Check-out is exclusive: another guest may check in on that same date.
    return aIn < bOut && bIn < aOut;
}

public isolated function roundMoney(float amount) returns float {
    return (amount * 100.0).round() / 100.0;
}

public isolated function requireNonBlank(string value, string fieldName) returns error? {
    if value.trim().length() == 0 {
        return error(string `'${fieldName}' is required and must not be blank.`);
    }
    return ();
}

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

public isolated function insertProperty(Property property) returns Property|error {
    lock {
        if db.properties.hasKey(property.propertyId) {
            return error(string `Property '${property.propertyId}' already exists.`);
        }
        db.properties[property.propertyId] = property.clone();
        return property.clone();
    }
}

public isolated function findProperty(string propertyId) returns Property? {
    lock {
        Property? found = db.properties[propertyId];
        return found is () ? () : found.clone();
    }
}

public isolated function updatePropertyAtomic(UpdatePropertyRequest request) returns Property|error {
    lock {
        Property? existing = db.properties[request.propertyId.trim()];
        if existing is () {
            return error(string `Property '${request.propertyId}' does not exist.`);
        }
        if existing.hostId != request.hostId.trim() {
            return error(string `Property '${existing.propertyId}' belongs to host '${existing.hostId}'.`);
        }
        Property updated = existing.clone();
        if request.name.trim().length() > 0 {
            updated.name = request.name.trim();
        }
        if request.location.trim().length() > 0 {
            updated.location = request.location.trim();
        }
        if request.propertyType.trim().length() > 0 {
            updated.propertyType = request.propertyType.trim().toUpperAscii();
        }
        if request.pricePerNight > 0.0 {
            updated.pricePerNight = roundMoney(request.pricePerNight);
        }
        if request.status != PROPERTY_STATUS_UNKNOWN {
            updated.status = request.status;
        }
        if request.description.trim().length() > 0 {
            updated.description = request.description.trim();
        }
        if request.maxGuests > 0 {
            updated.maxGuests = request.maxGuests;
        }
        if request.amenities.length() > 0 {
            updated.amenities = request.amenities.clone();
        }
        db.properties[updated.propertyId] = updated.clone();
        return updated.clone();
    }
}

public isolated function removePropertyAtomic(string propertyId, string hostId) returns RemovePropertyResponse {
    lock {
        Property? existing = db.properties[propertyId];
        if existing is () {
            return {success: false, message: string `Property '${propertyId}' does not exist.`};
        }
        if existing.hostId != hostId {
            return {success: false, message: string `Property '${propertyId}' belongs to host '${existing.hostId}'.`};
        }
        foreach Booking booking in db.bookings {
            if booking.propertyId == propertyId && booking.state == CONFIRMED && booking.checkOut > today() {
                return {
                    success: false,
                    message: string `Property '${propertyId}' has a confirmed booking through ${booking.checkOut}.`
                };
            }
        }
        Property removed = db.properties.remove(propertyId);
        Host? host = db.hosts[hostId];
        string region = host is Host && host.region.trim().length() > 0 ? host.region.trim() : removed.location;
        Property[] remaining = from Property p in db.properties
            where p.status == AVAILABLE && p.location.trim().toLowerAscii() == region.toLowerAscii()
            order by p.propertyId ascending
            select p;
        string[] pendingIds = from Booking b in db.bookings
            where b.propertyId == propertyId && b.state == PENDING
            select b.bookingId;
        foreach string id in pendingIds {
            _ = db.bookings.remove(id);
        }
        return {
            success: true,
            message: string `Property '${removed.name}' was removed. ${remaining.length()} available listing(s) remain in ${region}.`,
            region: region,
            remainingProperties: remaining.clone()
        };
    }
}

public isolated function allProperties() returns Property[] {
    lock {
        Property[] rows = from Property p in db.properties
            order by p.propertyId ascending
            select p;
        return rows.clone();
    }
}

public isolated function propertiesOfHost(string hostId) returns Property[] {
    lock {
        Property[] rows = from Property p in db.properties
            where p.hostId == hostId
            order by p.propertyId ascending
            select p;
        return rows.clone();
    }
}

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

public isolated function countProperties() returns int {
    lock {
        return db.properties.length();
    }
}

public isolated function insertHost(Host host) returns Host|error {
    lock {
        if db.hosts.hasKey(host.hostId) || db.guests.hasKey(host.hostId) {
            return error(string `User '${host.hostId}' already exists.`);
        }
        check validateUniqueEmail(db, host.email);
        db.hosts[host.hostId] = host.clone();
        return host.clone();
    }
}

public isolated function insertGuest(Guest guest) returns Guest|error {
    lock {
        if db.guests.hasKey(guest.guestId) || db.hosts.hasKey(guest.guestId) {
            return error(string `User '${guest.guestId}' already exists.`);
        }
        check validateUniqueEmail(db, guest.email);
        db.guests[guest.guestId] = guest.clone();
        return guest.clone();
    }
}

public isolated function findHost(string hostId) returns Host? {
    lock {
        Host? found = db.hosts[hostId];
        return found is () ? () : found.clone();
    }
}

public isolated function findGuest(string guestId) returns Guest? {
    lock {
        Guest? found = db.guests[guestId];
        return found is () ? () : found.clone();
    }
}

public isolated function allHosts() returns Host[] {
    lock {
        Host[] rows = from Host h in db.hosts
            order by h.hostId ascending
            select h;
        return rows.clone();
    }
}

public isolated function allGuests() returns Guest[] {
    lock {
        Guest[] rows = from Guest g in db.guests
            order by g.guestId ascending
            select g;
        return rows.clone();
    }
}

isolated function validateUniqueEmail(Datastore store, string email) returns error? {
    string needle = email.trim().toLowerAscii();
    foreach Host h in store.hosts {
        if h.email.trim().toLowerAscii() == needle {
            return error(string `Email '${email}' is already registered.`);
        }
    }
    foreach Guest g in store.guests {
        if g.email.trim().toLowerAscii() == needle {
            return error(string `Email '${email}' is already registered.`);
        }
    }
}

public isolated function insertBooking(Booking booking) returns Booking|error {
    lock {
        if db.bookings.hasKey(booking.bookingId) {
            return error(string `Booking '${booking.bookingId}' already exists.`);
        }
        db.bookings[booking.bookingId] = booking.clone();
        return booking.clone();
    }
}

public isolated function findBooking(string bookingId) returns Booking? {
    lock {
        Booking? found = db.bookings[bookingId];
        return found is () ? () : found.clone();
    }
}

public isolated function allBookings() returns Booking[] {
    lock {
        Booking[] rows = from Booking b in db.bookings
            order by b.bookingId descending
            select b;
        return rows.clone();
    }
}

public isolated function cartOf(string guestId) returns Booking[] {
    lock {
        Booking[] rows = from Booking b in db.bookings
            where b.guestId == guestId && b.state == PENDING
            order by b.bookingId ascending
            select b;
        return rows.clone();
    }
}

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

public isolated function confirmBookingAtomic(string bookingId, string guestId)
        returns Booking|error {
    lock {
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
        Property? listing = db.properties[booking.propertyId];
        if listing is () {
            return error(string `The property '${booking.propertyId}' has been removed by its host.`);
        }
        Property property = listing.clone();
        if property.status != AVAILABLE {
            return error(string `Property '${property.propertyId}' is ${property.status} ` +
                string `and can no longer be booked.`);
        }
        foreach Booking other in db.bookings {
            if other.bookingId != bookingId && other.propertyId == booking.propertyId
                    && other.state == CONFIRMED
                    && rangesOverlap(booking.checkIn, booking.checkOut, other.checkIn, other.checkOut) {
                return error(string `Property '${property.propertyId}' is already booked from ` +
                    string `${other.checkIn} to ${other.checkOut}; the requested dates ` +
                    string `${booking.checkIn} to ${booking.checkOut} overlap it.`);
            }
        }
        int|error nights = validateStay(booking.checkIn, booking.checkOut);
        if nights is error {
            return error(string `Stored dates on booking '${bookingId}' are invalid: ${nights.message()}`);
        }

        booking.nights = nights;
        booking.totalCost = roundMoney(property.pricePerNight * <float>nights);
        // Confirmed records stay in booking history and are excluded from cartOf().
        booking.state = CONFIRMED;
        booking.confirmedAt = nowTimestamp();
        booking.propertyName = property.name;
        db.bookings[bookingId] = booking.clone();
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

public isolated function countBookings() returns int {
    lock {
        return db.bookings.length();
    }
}

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
