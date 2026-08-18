// ============================================================================
//  DSA612S - Assignment 1 - Question 2
//  Rental Accommodation System - gRPC Server
//  ---------------------------------------------------------------------------
//  service.bal
//  ---------------------------------------------------------------------------
//  The *service layer*: the implementation of the eight RPCs declared in
//  `proto/rental.proto`.
//
//  ERROR HANDLING POLICY
//  ---------------------
//  Every response message in the contract carries a `success` (or `found`)
//  flag together with a `message` string. A *business* rejection - unknown
//  host, dates in the past, a clashing booking - is therefore returned as a
//  normal response with `success = false` and an explanatory message. That is
//  what the contract asks for (`search_property` must answer "Not Available"
//  rather than fail) and it keeps the client's control flow simple.
//
//  A gRPC status error is reserved for genuinely exceptional situations, such
//  as a broken client stream, where there is no meaningful response to send.
//
//  STREAMING
//  ---------
//  `create_users` is client-side streaming: Ballerina hands the method a
//  `stream<CreateUserRequest, grpc:Error?>` which is drained message by
//  message; the single summary is returned once the client half-closes.
//
//  `list_available_properties` is server-side streaming: the method returns a
//  `stream<Property, error?>` and the runtime pulls one value at a time,
//  writing each one onto the wire as its own gRPC message.
// ============================================================================

import ballerina/grpc;
import ballerina/log;

// ============================================================================
//  SECTION 1 - SERVER STREAMING SUPPORT
// ============================================================================

# Turns a materialised result set into a pull-based iterator.
#
# The gRPC runtime pulls one value per message it puts on the wire, so the
# guest starts receiving listings before the whole result set has been walked.
class PropertyGenerator {
    private final Property[] items;
    private int cursor = 0;

    # Takes a private copy of the result set.
    #
    # + items - The listings to stream back.
    isolated function init(Property[] items) {
        self.items = items.clone();
    }

    # Produces the next listing, or `()` once the result set is exhausted.
    #
    # + return - The next value, or `()` at the end of the stream.
    public isolated function next() returns record {|Property value;|}? {
        if self.cursor >= self.items.length() {
            return ();
        }
        Property current = self.items[self.cursor];
        self.cursor += 1;
        return {value: current};
    }
}

// ============================================================================
//  SECTION 2 - THE SERVICE
// ============================================================================

# The `rental.RentalService` implementation.
#
# The service object itself holds no state at all: every mutation goes through
# the lock-protected stores in `database.bal`, which is what makes the server
# safe to run under concurrent load.
@grpc:Descriptor {value: RENTAL_DESC}
service "RentalService" on rentalListener {

    // ------------------------------------------------------------------
    //  2.1  add_property  (unary)
    // ------------------------------------------------------------------

    # Registers a new listing on behalf of a host.
    #
    # + request - The listing details.
    # + return - The stored listing and its new id, or a rejection message.
    remote function add_property(AddPropertyRequest request) returns AddPropertyResponse|error {
        // --- Validation ------------------------------------------------
        error? invalid = validateAddRequest(request);
        if invalid is error {
            log:printWarn("add_property rejected", reason = invalid.message());
            return {success: false, message: invalid.message()};
        }

        // --- The host must be registered -------------------------------
        Host? host = findHost(request.hostId.trim());
        if host is () {
            return {
                success: false,
                message: string `Unknown host '${request.hostId}'. ` +
                    string `Register the host first with create_users.`
            };
        }

        // --- Build and store the listing -------------------------------
        Property property = {
            propertyId: nextPropertyId(),
            hostId: host.hostId,
            name: request.name.trim(),
            location: request.location.trim(),
            propertyType: request.propertyType.trim().toUpperAscii(),
            pricePerNight: roundMoney(request.pricePerNight),
            // proto3 sends 0 when the client leaves the enum unset, so an
            // unspecified status defaults to a listing that is open for
            // business.
            status: request.status == PROPERTY_STATUS_UNKNOWN ? AVAILABLE : request.status,
            description: request.description.trim(),
            maxGuests: request.maxGuests,
            amenities: request.amenities
        };

        Property|error stored = insertProperty(property);
        if stored is error {
            log:printError("add_property failed", 'error = stored);
            return {success: false, message: stored.message()};
        }

        log:printInfo("Property registered", propertyId = stored.propertyId, hostId = host.hostId);
        return {
            success: true,
            message: string `Property '${stored.name}' was registered as ${stored.propertyId}.`,
            propertyId: stored.propertyId,
            property: stored
        };
    }

    // ------------------------------------------------------------------
    //  2.2  update_property  (unary)
    // ------------------------------------------------------------------

    # Patches an existing listing. Blank strings and zero numbers are treated
    # as "leave unchanged", so a host can update only the price or only the
    # status without resending the whole record.
    #
    # + request - The fields to change, plus the key and the owning host.
    # + return - The listing after the patch, or a rejection message.
    remote function update_property(UpdatePropertyRequest request) returns UpdatePropertyResponse|error {
        error? blankId = requireNonBlank(request.propertyId, "propertyId");
        if blankId is error {
            return {success: false, message: blankId.message()};
        }
        error? blankHost = requireNonBlank(request.hostId, "hostId");
        if blankHost is error {
            return {success: false, message: blankHost.message()};
        }

        Property? existing = findProperty(request.propertyId.trim());
        if existing is () {
            return {
                success: false,
                message: string `No property found with id '${request.propertyId}'.`
            };
        }

        // Ownership check: a host may only touch their own listings.
        if existing.hostId != request.hostId.trim() {
            return {
                success: false,
                message: string `Property '${existing.propertyId}' belongs to host ` +
                    string `'${existing.hostId}', not to '${request.hostId}'.`
            };
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
            updated.amenities = request.amenities;
        }

        Property|error saved = saveProperty(updated);
        if saved is error {
            log:printError("update_property failed", 'error = saved);
            return {success: false, message: saved.message()};
        }

        log:printInfo("Property updated", propertyId = saved.propertyId);
        return {
            success: true,
            message: string `Property ${saved.propertyId} was updated.`,
            property: saved
        };
    }

    // ------------------------------------------------------------------
    //  2.3  remove_property  (unary)
    // ------------------------------------------------------------------

    # Deletes a listing and answers with everything the host still has listed
    # in that same region, exactly as the brief requires.
    #
    # + request - The listing key and the owning host.
    # + return - The refreshed regional listing, or a rejection message.
    remote function remove_property(RemovePropertyRequest request) returns RemovePropertyResponse|error {
        error? blankId = requireNonBlank(request.propertyId, "propertyId");
        if blankId is error {
            return {success: false, message: blankId.message()};
        }
        error? blankHost = requireNonBlank(request.hostId, "hostId");
        if blankHost is error {
            return {success: false, message: blankHost.message()};
        }

        string propertyId = request.propertyId.trim();
        string hostId = request.hostId.trim();

        Property? existing = findProperty(propertyId);
        if existing is () {
            return {
                success: false,
                message: string `No property found with id '${propertyId}'.`,
                remainingProperties: propertiesOfHost(hostId)
            };
        }
        if existing.hostId != hostId {
            return {
                success: false,
                message: string `Property '${propertyId}' belongs to host '${existing.hostId}'.`,
                region: existing.location,
                remainingProperties: propertiesOfHostInRegion(hostId, existing.location)
            };
        }

        // A listing with a confirmed stay still to come may not vanish, or the
        // guest would arrive to find nothing booked.
        Booking[] bookings = allBookings();
        string todayIso = today();
        foreach Booking b in bookings {
            if b.propertyId == propertyId && b.state == CONFIRMED && b.checkOut > todayIso {
                return {
                    success: false,
                    message: string `Property '${propertyId}' has a confirmed booking ` +
                        string `(${b.bookingId}) running to ${b.checkOut} and cannot be removed.`,
                    region: existing.location,
                    remainingProperties: propertiesOfHostInRegion(hostId, existing.location)
                };
            }
        }

        string region = existing.location;
        Property|error removed = deleteProperty(propertyId);
        if removed is error {
            return {success: false, message: removed.message(), region: region};
        }

        log:printInfo("Property removed", propertyId = propertyId, hostId = hostId);
        Property[] remaining = propertiesOfHostInRegion(hostId, region);
        return {
            success: true,
            message: string `Property '${removed.name}' (${propertyId}) was removed. ` +
                string `${remaining.length()} listing(s) remain for this host in ${region}.`,
            region: region,
            remainingProperties: remaining
        };
    }

    // ------------------------------------------------------------------
    //  2.4  search_property  (unary)
    // ------------------------------------------------------------------

    # Looks one listing up by its identifier.
    #
    # + request - The identifier to resolve.
    # + return - The full listing when available, otherwise a "NOT AVAILABLE"
    #            answer, as required by the brief.
    remote function search_property(SearchPropertyRequest request) returns SearchPropertyResponse|error {
        error? blank = requireNonBlank(request.propertyId, "propertyId");
        if blank is error {
            return {found: false, status: "NOT AVAILABLE", message: blank.message()};
        }

        string propertyId = request.propertyId.trim();
        Property? found = findProperty(propertyId);
        if found is () {
            return {
                found: false,
                status: "NOT AVAILABLE",
                message: string `No property is listed under id '${propertyId}'.`
            };
        }

        if found.status != AVAILABLE {
            return {
                found: true,
                status: "NOT AVAILABLE",
                message: string `Property '${propertyId}' exists but is currently ${found.status}.`,
                property: found
            };
        }

        return {
            found: true,
            status: "AVAILABLE",
            message: string `Property '${propertyId}' is available at ` +
                string `NAD ${found.pricePerNight} per night.`,
            property: found
        };
    }

    // ------------------------------------------------------------------
    //  2.5  book_property  (unary) - adds to the temporary cart
    // ------------------------------------------------------------------

    # Validates a requested stay and places it into the guest's temporary
    # booking cart. Nothing is reserved yet - `confirm_booking` does that.
    #
    # + request - The property, the guest and the requested dates.
    # + return - The cart entry id and an indicative cost, or a rejection.
    remote function book_property(BookPropertyRequest request) returns BookPropertyResponse|error {
        error? blankProperty = requireNonBlank(request.propertyId, "propertyId");
        if blankProperty is error {
            return {success: false, message: blankProperty.message()};
        }
        error? blankGuest = requireNonBlank(request.guestId, "guestId");
        if blankGuest is error {
            return {success: false, message: blankGuest.message()};
        }

        string propertyId = request.propertyId.trim();
        string guestId = request.guestId.trim();

        // --- The guest must be registered ------------------------------
        Guest? guest = findGuest(guestId);
        if guest is () {
            return {
                success: false,
                message: string `Unknown guest '${guestId}'. ` +
                    string `Register the guest first with create_users.`
            };
        }

        // --- The listing must exist and be open for business -----------
        Property? property = findProperty(propertyId);
        if property is () {
            return {
                success: false,
                message: string `No property is listed under id '${propertyId}'.`
            };
        }
        if property.status != AVAILABLE {
            return {
                success: false,
                message: string `Property '${propertyId}' is ${property.status} and cannot be booked.`
            };
        }

        // --- The dates must make sense ---------------------------------
        int|error nights = validateStay(request.checkIn, request.checkOut);
        if nights is error {
            return {success: false, message: nights.message()};
        }

        // --- Early feedback: is it already taken? ----------------------
        // This is only an optimisation. `confirm_booking` re-checks under a
        // lock, because another guest may confirm in between the two calls.
        if hasConfirmedClash(propertyId, request.checkIn.trim(), request.checkOut.trim()) {
            return {
                success: false,
                message: string `Property '${propertyId}' is already booked for part of ` +
                    string `${request.checkIn} to ${request.checkOut}.`
            };
        }

        // --- Do not let one guest fill the cart with duplicates --------
        foreach Booking existing in cartOf(guestId) {
            if existing.propertyId == propertyId
                    && existing.checkIn == request.checkIn.trim()
                    && existing.checkOut == request.checkOut.trim() {
                return {
                    success: false,
                    message: string `This stay is already in your cart as '${existing.bookingId}'. ` +
                        string `Confirm it instead of adding it twice.`,
                    bookingId: existing.bookingId,
                    nights: existing.nights,
                    estimatedCost: existing.totalCost
                };
            }
        }

        // --- Park it in the cart ---------------------------------------
        float estimate = roundMoney(property.pricePerNight * <float>nights);
        Booking cartEntry = {
            bookingId: nextBookingId(),
            propertyId: propertyId,
            guestId: guestId,
            checkIn: request.checkIn.trim(),
            checkOut: request.checkOut.trim(),
            totalCost: estimate,
            state: PENDING,
            nights: nights,
            confirmedAt: "",
            propertyName: property.name
        };

        Booking|error parked = insertBooking(cartEntry);
        if parked is error {
            log:printError("book_property failed", 'error = parked);
            return {success: false, message: parked.message()};
        }

        log:printInfo("Booking request parked", bookingId = parked.bookingId, guestId = guestId);
        return {
            success: true,
            message: string `Request '${parked.bookingId}' added to your cart: ${nights} night(s) ` +
                string `at ${property.name}, estimated NAD ${estimate}. ` +
                string `Call confirm_booking to finalise it.`,
            bookingId: parked.bookingId,
            nights: nights,
            estimatedCost: estimate
        };
    }

    // ------------------------------------------------------------------
    //  2.6  confirm_booking  (unary)
    // ------------------------------------------------------------------

    # Finalises a cart entry: re-verifies availability, calculates the total
    # cost and clears the guest's temporary request. The whole sequence runs
    # inside one lock in `confirmBookingAtomic`, which is what makes it safe
    # against two guests confirming at the same moment.
    #
    # + request - The cart entry and the guest that owns it.
    # + return - The confirmed booking, or a rejection message.
    remote function confirm_booking(ConfirmBookingRequest request) returns ConfirmBookingResponse|error {
        error? blankBooking = requireNonBlank(request.bookingId, "bookingId");
        if blankBooking is error {
            return {success: false, message: blankBooking.message()};
        }
        error? blankGuest = requireNonBlank(request.guestId, "guestId");
        if blankGuest is error {
            return {success: false, message: blankGuest.message()};
        }

        Booking|error confirmed = confirmBookingAtomic(request.bookingId.trim(), request.guestId.trim());
        if confirmed is error {
            log:printWarn("confirm_booking rejected", reason = confirmed.message());
            return {success: false, message: confirmed.message()};
        }

        log:printInfo("Booking confirmed",
            bookingId = confirmed.bookingId,
            nights = confirmed.nights,
            total = confirmed.totalCost);

        return {
            success: true,
            message: string `Booking ${confirmed.bookingId} confirmed: ${confirmed.nights} night(s) ` +
                string `at ${confirmed.propertyName}, total NAD ${confirmed.totalCost}.`,
            booking: confirmed
        };
    }

    // ------------------------------------------------------------------
    //  2.7  create_users  (CLIENT-SIDE STREAMING)
    // ------------------------------------------------------------------

    # Consumes a stream of user profiles and replies once, after the client
    # has half-closed the stream.
    #
    # Each element is validated independently: one bad profile is recorded in
    # `failures` and the rest of the stream still gets processed, which is the
    # behaviour a bulk import needs.
    #
    # + clientStream - The inbound stream of profiles.
    # + return - A single summary of everything that was processed.
    remote function create_users(stream<CreateUserRequest, grpc:Error?> clientStream)
            returns CreateUsersSummary|error {

        int total = 0;
        int hostsCreated = 0;
        int guestsCreated = 0;
        string[] failures = [];
        string[] createdIds = [];

        // Drain the stream one message at a time. `next()` returns `()` when
        // the client half-closes, and a `grpc:Error` if the transport breaks.
        record {|CreateUserRequest value;|}|grpc:Error? item = clientStream.next();

        while item is record {|CreateUserRequest value;|} {
            CreateUserRequest user = item.value;
            total += 1;

            string label = user.name.trim().length() > 0 ? user.name.trim() : string `record ${total}`;

            // --- Per-record validation ---------------------------------
            error? nameCheck = requireNonBlank(user.name, "name");
            if nameCheck is error {
                failures.push(string `[${total}] ${nameCheck.message()}`);
                item = clientStream.next();
                continue;
            }
            error? emailCheck = validateEmail(user.email);
            if emailCheck is error {
                failures.push(string `[${total}] ${label}: ${emailCheck.message()}`);
                item = clientStream.next();
                continue;
            }
            if user.role == USER_ROLE_UNKNOWN {
                failures.push(string `[${total}] ${label}: role must be HOST or GUEST.`);
                item = clientStream.next();
                continue;
            }
            if emailInUse(user.email) {
                failures.push(string `[${total}] ${label}: email '${user.email.trim()}' is already registered.`);
                item = clientStream.next();
                continue;
            }

            // --- Store the profile -------------------------------------
            string suppliedId = user.userId.trim();
            if user.role == HOST {
                Host host = {
                    hostId: suppliedId.length() > 0 ? suppliedId : nextHostId(),
                    name: user.name.trim(),
                    email: user.email.trim(),
                    phone: user.phone.trim(),
                    region: user.region.trim()
                };
                Host|error stored = insertHost(host);
                if stored is error {
                    failures.push(string `[${total}] ${label}: ${stored.message()}`);
                } else {
                    hostsCreated += 1;
                    createdIds.push(stored.hostId);
                }
            } else {
                Guest guest = {
                    guestId: suppliedId.length() > 0 ? suppliedId : nextGuestId(),
                    name: user.name.trim(),
                    email: user.email.trim(),
                    phone: user.phone.trim()
                };
                Guest|error stored = insertGuest(guest);
                if stored is error {
                    failures.push(string `[${total}] ${label}: ${stored.message()}`);
                } else {
                    guestsCreated += 1;
                    createdIds.push(stored.guestId);
                }
            }

            item = clientStream.next();
        }

        // A transport failure is the one case where there is no useful
        // response to send, so it is surfaced as a gRPC status error.
        if item is grpc:Error {
            log:printError("create_users stream failed", 'error = item);
            return error grpc:AbortedError(
                string `The user stream was interrupted after ${total} record(s): ${item.message()}`);
        }

        int created = hostsCreated + guestsCreated;
        log:printInfo("create_users completed",
            received = total, created = created, failed = failures.length());

        return {
            success: created > 0,
            message: created > 0
                ? string `Received ${total} profile(s): ${hostsCreated} host(s) and ` +
                  string `${guestsCreated} guest(s) registered, ${failures.length()} rejected.`
                : string `Received ${total} profile(s) but none could be registered.`,
            totalReceived: total,
            hostsCreated: hostsCreated,
            guestsCreated: guestsCreated,
            failures: failures,
            createdIds: createdIds
        };
    }

    // ------------------------------------------------------------------
    //  2.8  list_available_properties  (SERVER-SIDE STREAMING)
    // ------------------------------------------------------------------

    # Streams the listings a guest can actually rent, one gRPC message each.
    #
    # + request - The optional location, price and capacity filters.
    # + return - A stream of matching listings, cheapest first.
    remote function list_available_properties(ListAvailableRequest request)
            returns stream<Property, error?>|error {

        // A malformed price window is worth rejecting outright, because an
        // empty stream would otherwise look like "nothing is available".
        if request.maxPrice > 0.0 && request.minPrice > request.maxPrice {
            return error grpc:InvalidArgumentError(
                string `minPrice (${request.minPrice}) cannot exceed maxPrice (${request.maxPrice}).`);
        }

        Property[] matches = searchAvailable(request);
        log:printInfo("list_available_properties",
            location = request.location, matches = matches.length());

        // Returning a stream rather than an array is what makes this RPC a
        // server-streaming call: the runtime pulls one value per wire message.
        return new stream<Property, error?>(new PropertyGenerator(matches));
    }
}

// ============================================================================
//  SECTION 3 - SHARED VALIDATION
// ============================================================================

# Validates an `add_property` request before anything is stored.
#
# + request - The incoming request.
# + return - The first problem found, or `()` when the request is sound.
isolated function validateAddRequest(AddPropertyRequest request) returns error? {
    check requireNonBlank(request.hostId, "hostId");
    check requireNonBlank(request.name, "name");
    check requireNonBlank(request.location, "location");
    check requireNonBlank(request.propertyType, "propertyType");

    if request.name.trim().length() > 150 {
        return error("'name' must not exceed 150 characters.");
    }
    if request.pricePerNight <= 0.0 {
        return error(string `'pricePerNight' must be greater than zero, received ${request.pricePerNight}.`);
    }
    if request.pricePerNight > 1000000.0 {
        return error("'pricePerNight' is implausibly high; please check the amount.");
    }
    if request.maxGuests <= 0 {
        return error(string `'maxGuests' must be at least 1, received ${request.maxGuests}.`);
    }
    if request.maxGuests > 100 {
        return error("'maxGuests' may not exceed 100 for a short-term rental.");
    }
    return ();
}
