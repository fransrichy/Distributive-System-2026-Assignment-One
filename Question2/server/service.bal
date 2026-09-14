import ballerina/grpc;
import ballerina/log;

class PropertyGenerator {
    private final Property[] items;
    private int cursor = 0;

    isolated function init(Property[] items) {
        self.items = items.clone();
    }

    public isolated function next() returns record {|Property value;|}? {
        if self.cursor >= self.items.length() {
            return ();
        }
        Property current = self.items[self.cursor];
        self.cursor += 1;
        return {value: current};
    }
}

@grpc:Descriptor {value: RENTAL_DESC}
isolated service "RentalService" on rentalListener {
    isolated remote function add_property(AddPropertyRequest request) returns AddPropertyResponse|error {
        error? invalid = validateAddRequest(request);
        if invalid is error {
            log:printWarn("add_property rejected", reason = invalid.message());
            return {success: false, message: invalid.message()};
        }
        Host? host = findHost(request.hostId.trim());
        if host is () {
            return {
                success: false,
                message: string `Unknown host '${request.hostId}'. ` +
                    string `Register the host first with create_users.`
            };
        }
        Property property = {
            propertyId: nextPropertyId(),
            hostId: host.hostId,
            name: request.name.trim(),
            location: request.location.trim(),
            propertyType: request.propertyType.trim().toUpperAscii(),
            pricePerNight: roundMoney(request.pricePerNight),
            status: request.status == PROPERTY_STATUS_UNKNOWN ? AVAILABLE : request.status,
            description: request.description.trim(),
            maxGuests: request.maxGuests == 0 ? 1 : request.maxGuests,
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

    isolated remote function update_property(UpdatePropertyRequest request) returns UpdatePropertyResponse|error {
        error? blankId = requireNonBlank(request.propertyId, "propertyId");
        if blankId is error {
            return {success: false, message: blankId.message()};
        }
        error? blankHost = requireNonBlank(request.hostId, "hostId");
        if blankHost is error {
            return {success: false, message: blankHost.message()};
        }

        error? invalid = validateUpdateRequest(request);
        if invalid is error {
            return {success: false, message: invalid.message()};
        }
        Property|error saved = updatePropertyAtomic(request);
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

    isolated remote function remove_property(RemovePropertyRequest request) returns RemovePropertyResponse|error {
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

        return removePropertyAtomic(propertyId, hostId);
    }

    isolated remote function search_property(SearchPropertyRequest request) returns SearchPropertyResponse|error {
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

    isolated remote function book_property(BookPropertyRequest request) returns BookPropertyResponse|error {
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
        Guest? guest = findGuest(guestId);
        if guest is () {
            return {
                success: false,
                message: string `Unknown guest '${guestId}'. ` +
                    string `Register the guest first with create_users.`
            };
        }
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
        int|error nights = validateStay(request.checkIn, request.checkOut);
        if nights is error {
            return {success: false, message: nights.message()};
        }
        if hasConfirmedClash(propertyId, request.checkIn.trim(), request.checkOut.trim()) {
            return {
                success: false,
                message: string `Property '${propertyId}' is already booked for part of ` +
                    string `${request.checkIn} to ${request.checkOut}.`
            };
        }
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

    isolated remote function confirm_booking(ConfirmBookingRequest request) returns ConfirmBookingResponse|error {
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

    isolated remote function create_users(stream<CreateUserRequest, grpc:Error?> clientStream)
            returns CreateUsersSummary|error {

        int total = 0;
        int hostsCreated = 0;
        int guestsCreated = 0;
        string[] failures = [];
        string[] createdIds = [];
        record {|CreateUserRequest value;|}|grpc:Error? item = clientStream.next();

        while item is record {|CreateUserRequest value;|} {
            CreateUserRequest user = item.value;
            total += 1;

            string label = user.name.trim().length() > 0 ? user.name.trim() : string `record ${total}`;
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

    isolated remote function list_available_properties(ListAvailableRequest request)
            returns stream<Property, error?>|error {
        if !request.minPrice.isFinite() || !request.maxPrice.isFinite()
                || request.minPrice < 0.0 || request.maxPrice < 0.0 || request.minGuests < 0 {
            return error grpc:InvalidArgumentError("Prices and minimum guests must be finite, non-negative values.");
        }
        if request.maxPrice > 0.0 && request.minPrice > request.maxPrice {
            return error grpc:InvalidArgumentError(
                string `minPrice (${request.minPrice}) cannot exceed maxPrice (${request.maxPrice}).`);
        }

        Property[] matches = searchAvailable(request);
        log:printInfo("list_available_properties",
                location = request.location, matches = matches.length());
        if matches.length() == 0 {
            return error grpc:NotFoundError("No property matched those filters.");
        }
        return new stream<Property, error?>(new PropertyGenerator(matches));
    }
}

isolated function validateAddRequest(AddPropertyRequest request) returns error? {
    check requireNonBlank(request.hostId, "hostId");
    check requireNonBlank(request.name, "name");
    check requireNonBlank(request.location, "location");
    check requireNonBlank(request.propertyType, "propertyType");

    if request.name.trim().length() > 150 {
        return error("'name' must not exceed 150 characters.");
    }
    if !request.pricePerNight.isFinite() || request.pricePerNight < 0.01 {
        return error(string `'pricePerNight' must be greater than zero, received ${request.pricePerNight}.`);
    }
    if request.pricePerNight > 1000000.0 {
        return error("'pricePerNight' is implausibly high; please check the amount.");
    }
    if request.maxGuests < 0 {
        return error(string `'maxGuests' must not be negative, received ${request.maxGuests}.`);
    }
    if request.maxGuests > 100 {
        return error("'maxGuests' may not exceed 100 for a short-term rental.");
    }
    return ();
}

isolated function validateUpdateRequest(UpdatePropertyRequest request) returns error? {
    if request.name.trim().length() > 150 {
        return error("'name' must not exceed 150 characters.");
    }
    // Proto3 zero values mean that a patch leaves the field unchanged.
    if !request.pricePerNight.isFinite() || request.pricePerNight < 0.0
            || request.pricePerNight > 1000000.0
            || (request.pricePerNight > 0.0 && request.pricePerNight < 0.01) {
        return error("'pricePerNight' must be between NAD 0.01 and 1000000, or zero to leave unchanged.");
    }
    if request.maxGuests < 0 || request.maxGuests > 100 {
        return error("'maxGuests' must be between 1 and 100, or zero to leave unchanged.");
    }
}
