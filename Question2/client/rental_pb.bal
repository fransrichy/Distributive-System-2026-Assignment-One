// ============================================================================
//  DSA612S - Assignment 1 - Question 2
//  Rental Accommodation System
//  ---------------------------------------------------------------------------
//  rental_pb.bal - PROTOCOL BUFFER STUB
//  ---------------------------------------------------------------------------
//  This file is the Ballerina representation of `proto/rental.proto`. It is
//  the artefact the Ballerina gRPC tool produces, and it is committed to the
//  repository so that the project builds without any extra tooling step.
//
//  To regenerate it after editing the contract, run from `Question2/`:
//
//      bal grpc --input proto/rental.proto --output server --mode service
//      bal grpc --input proto/rental.proto --output client --mode client
//
//  Contents
//    1. RENTAL_DESC          - the serialised FileDescriptorProto, in hex.
//    2. Enums                - PropertyStatus, UserRole, BookingState.
//    3. Message records      - one Ballerina record per proto message.
//    4. Context records      - message + gRPC headers, for header access.
//    5. RentalServiceClient  - the typed client stub (all eight RPCs).
//    6. Streaming helpers    - PropertyStream (server streaming) and
//                              Create_usersStreamingClient (client streaming).
//    7. Caller classes       - the server side callers for streaming replies.
//
//  DO NOT EDIT BY HAND unless you also update `proto/rental.proto`.
// ============================================================================

import ballerina/grpc;

// ============================================================================
//  1. SERVICE DESCRIPTOR
// ============================================================================

# The serialised `FileDescriptorProto` of `rental.proto`, hex encoded.
#
# Both the client stub (`initStub`) and the service (`@grpc:Descriptor`) hand
# this string to the gRPC runtime, which uses it to resolve message shapes,
# method names and streaming modes at runtime.
public const string RENTAL_DESC = "0A0C72656E74616C2E70726F746F120672656E74616C22CA020A0850726F7065727479121E0A0A70726F70657274794964180120012809520A70726F7065727479496412160A06686F737449641802200128095206686F7374496412120A046E616D6518032001280952046E616D65121A0A086C6F636174696F6E18042001280952086C6F636174696F6E12220A0C70726F706572747954797065180520012809520C70726F70657274795479706512240A0D70726963655065724E69676874180620012801520D70726963655065724E69676874122E0A0673746174757318072001280E32162E72656E74616C2E50726F7065727479537461747573520673746174757312200A0B6465736372697074696F6E180820012809520B6465736372697074696F6E121C0A096D617847756573747318092001280552096D6178477565737473121C0A09616D656E6974696573180A200328095209616D656E697469657322760A04486F737412160A06686F737449641801200128095206686F7374496412120A046E616D6518022001280952046E616D6512140A05656D61696C1803200128095205656D61696C12140A0570686F6E65180420012809520570686F6E6512160A06726567696F6E1805200128095206726567696F6E22610A05477565737412180A076775657374496418012001280952076775657374496412120A046E616D6518022001280952046E616D6512140A05656D61696C1803200128095205656D61696C12140A0570686F6E65180420012809520570686F6E6522BF020A07426F6F6B696E67121C0A09626F6F6B696E6749641801200128095209626F6F6B696E674964121E0A0A70726F70657274794964180220012809520A70726F7065727479496412180A076775657374496418032001280952076775657374496412180A07636865636B496E1804200128095207636865636B496E121A0A08636865636B4F75741805200128095208636865636B4F7574121C0A09746F74616C436F73741806200128015209746F74616C436F7374122A0A05737461746518072001280E32142E72656E74616C2E426F6F6B696E6753746174655205737461746512160A066E696768747318082001280552066E696768747312200A0B636F6E6669726D65644174180920012809520B636F6E6669726D6564417412220A0C70726F70657274794E616D65180A20012809520C70726F70657274794E616D6522B4020A1241646450726F70657274795265717565737412160A06686F737449641801200128095206686F7374496412120A046E616D6518022001280952046E616D65121A0A086C6F636174696F6E18032001280952086C6F636174696F6E12220A0C70726F706572747954797065180420012809520C70726F70657274795479706512240A0D70726963655065724E69676874180520012801520D70726963655065724E69676874122E0A0673746174757318062001280E32162E72656E74616C2E50726F7065727479537461747573520673746174757312200A0B6465736372697074696F6E180720012809520B6465736372697074696F6E121C0A096D617847756573747318082001280552096D6178477565737473121C0A09616D656E69746965731809200328095209616D656E69746965732297010A1341646450726F7065727479526573706F6E736512180A077375636365737318012001280852077375636365737312180A076D65737361676518022001280952076D657373616765121E0A0A70726F70657274794964180320012809520A70726F70657274794964122C0A0870726F706572747918042001280B32102E72656E74616C2E50726F7065727479520870726F706572747922D7020A1555706461746550726F706572747952657175657374121E0A0A70726F70657274794964180120012809520A70726F7065727479496412160A06686F737449641802200128095206686F7374496412120A046E616D6518032001280952046E616D65121A0A086C6F636174696F6E18042001280952086C6F636174696F6E12220A0C70726F706572747954797065180520012809520C70726F70657274795479706512240A0D70726963655065724E69676874180620012801520D70726963655065724E69676874122E0A0673746174757318072001280E32162E72656E74616C2E50726F7065727479537461747573520673746174757312200A0B6465736372697074696F6E180820012809520B6465736372697074696F6E121C0A096D617847756573747318092001280552096D6178477565737473121C0A09616D656E6974696573180A200328095209616D656E6974696573227A0A1655706461746550726F7065727479526573706F6E736512180A077375636365737318012001280852077375636365737312180A076D65737361676518022001280952076D657373616765122C0A0870726F706572747918032001280B32102E72656E74616C2E50726F7065727479520870726F7065727479224F0A1552656D6F766550726F706572747952657175657374121E0A0A70726F70657274794964180120012809520A70726F7065727479496412160A06686F737449641802200128095206686F7374496422A8010A1652656D6F766550726F7065727479526573706F6E736512180A077375636365737318012001280852077375636365737312180A076D65737361676518022001280952076D65737361676512160A06726567696F6E1803200128095206726567696F6E12420A1372656D61696E696E6750726F7065727469657318042003280B32102E72656E74616C2E50726F7065727479521372656D61696E696E6750726F7065727469657322370A1553656172636850726F706572747952657175657374121E0A0A70726F70657274794964180120012809520A70726F70657274794964228E010A1653656172636850726F7065727479526573706F6E736512140A05666F756E641801200128085205666F756E6412160A06737461747573180220012809520673746174757312180A076D65737361676518032001280952076D657373616765122C0A0870726F706572747918042001280B32102E72656E74616C2E50726F7065727479520870726F70657274792285010A13426F6F6B50726F706572747952657175657374121E0A0A70726F70657274794964180120012809520A70726F7065727479496412180A076775657374496418022001280952076775657374496412180A07636865636B496E1803200128095207636865636B496E121A0A08636865636B4F75741804200128095208636865636B4F757422A6010A14426F6F6B50726F7065727479526573706F6E736512180A077375636365737318012001280852077375636365737312180A076D65737361676518022001280952076D657373616765121C0A09626F6F6B696E6749641803200128095209626F6F6B696E67496412160A066E696768747318042001280552066E696768747312240A0D657374696D61746564436F7374180520012801520D657374696D61746564436F7374224F0A15436F6E6669726D426F6F6B696E6752657175657374121C0A09626F6F6B696E6749641801200128095209626F6F6B696E67496412180A076775657374496418022001280952076775657374496422770A16436F6E6669726D426F6F6B696E67526573706F6E736512180A077375636365737318012001280852077375636365737312180A076D65737361676518022001280952076D65737361676512290A07626F6F6B696E6718032001280B320F2E72656E74616C2E426F6F6B696E675207626F6F6B696E6722A9010A11437265617465557365725265717565737412160A06757365724964180120012809520675736572496412120A046E616D6518022001280952046E616D6512140A05656D61696C1803200128095205656D61696C12240A04726F6C6518042001280E32102E72656E74616C2E55736572526F6C655204726F6C6512140A0570686F6E65180520012809520570686F6E6512160A06726567696F6E1806200128095206726567696F6E22F4010A12437265617465557365727353756D6D61727912180A077375636365737318012001280852077375636365737312180A076D65737361676518022001280952076D65737361676512240A0D746F74616C5265636569766564180320012805520D746F74616C526563656976656412220A0C686F73747343726561746564180420012805520C686F7374734372656174656412240A0D67756573747343726561746564180520012805520D67756573747343726561746564121A0A086661696C7572657318062003280952086661696C75726573121E0A0A63726561746564496473180720032809520A6372656174656449647322AC010A144C697374417661696C61626C6552657175657374121A0A086C6F636174696F6E18012001280952086C6F636174696F6E121A0A086D696E507269636518022001280152086D696E5072696365121A0A086D6178507269636518032001280152086D6178507269636512220A0C70726F706572747954797065180420012809520C70726F706572747954797065121C0A096D696E47756573747318052001280552096D696E4775657374732A640A0E50726F7065727479537461747573121B0A1750524F50455254595F5354415455535F554E4B4E4F574E1000120D0A09415641494C41424C451001120F0A0B554E415641494C41424C45100212150A11554E4445525F4D41494E54454E414E434510032A360A0855736572526F6C6512150A11555345525F524F4C455F554E4B4E4F574E100012080A04484F5354100112090A05475545535410022A540A0C426F6F6B696E67537461746512190A15424F4F4B494E475F53544154455F554E4B4E4F574E1000120B0A0750454E44494E471001120D0A09434F4E4649524D45441002120D0A0943414E43454C4C454410033284050A0D52656E74616C5365727669636512470A0C6164645F70726F7065727479121A2E72656E74616C2E41646450726F7065727479526571756573741A1B2E72656E74616C2E41646450726F7065727479526573706F6E736512500A0F7570646174655F70726F7065727479121D2E72656E74616C2E55706461746550726F7065727479526571756573741A1E2E72656E74616C2E55706461746550726F7065727479526573706F6E736512500A0F72656D6F76655F70726F7065727479121D2E72656E74616C2E52656D6F766550726F7065727479526571756573741A1E2E72656E74616C2E52656D6F766550726F7065727479526573706F6E736512500A0F7365617263685F70726F7065727479121D2E72656E74616C2E53656172636850726F7065727479526571756573741A1E2E72656E74616C2E53656172636850726F7065727479526573706F6E7365124A0A0D626F6F6B5F70726F7065727479121B2E72656E74616C2E426F6F6B50726F7065727479526571756573741A1C2E72656E74616C2E426F6F6B50726F7065727479526573706F6E736512500A0F636F6E6669726D5F626F6F6B696E67121D2E72656E74616C2E436F6E6669726D426F6F6B696E67526571756573741A1E2E72656E74616C2E436F6E6669726D426F6F6B696E67526573706F6E736512470A0C6372656174655F757365727312192E72656E74616C2E43726561746555736572526571756573741A1A2E72656E74616C2E437265617465557365727353756D6D6172792801124D0A196C6973745F617661696C61626C655F70726F70657274696573121C2E72656E74616C2E4C697374417661696C61626C65526571756573741A102E72656E74616C2E50726F70657274793001620670726F746F33";

// ============================================================================
//  2. ENUMS
// ============================================================================

# Availability of a listing. Mirrors `rental.PropertyStatus`.
public enum PropertyStatus {
    PROPERTY_STATUS_UNKNOWN,
    AVAILABLE,
    UNAVAILABLE,
    UNDER_MAINTENANCE
}

# The role a user account plays. Mirrors `rental.UserRole`.
public enum UserRole {
    USER_ROLE_UNKNOWN,
    HOST,
    GUEST
}

# Life-cycle of a booking. Mirrors `rental.BookingState`.
public enum BookingState {
    BOOKING_STATE_UNKNOWN,
    PENDING,
    CONFIRMED,
    CANCELLED
}

// ============================================================================
//  3. MESSAGE RECORDS
// ============================================================================
//  proto3 has no concept of a missing scalar, so every field carries the
//  proto3 default. That is why each record below is closed and fully
//  defaulted: `{}` is always a legal value.

# A short-term rental listing. Mirrors `rental.Property`.
#
# + propertyId - Server generated unique identifier.
# + hostId - Identifier of the owning host.
# + name - Display name of the listing.
# + location - Region or town.
# + propertyType - APARTMENT, GUESTHOUSE, LODGE, VILLA and so on.
# + pricePerNight - Nightly rate in Namibian Dollars.
# + status - Current availability.
# + description - Free text marketing copy.
# + maxGuests - Sleeping capacity.
# + amenities - Facilities offered.
public type Property record {|
    string propertyId = "";
    string hostId = "";
    string name = "";
    string location = "";
    string propertyType = "";
    float pricePerNight = 0.0;
    PropertyStatus status = PROPERTY_STATUS_UNKNOWN;
    string description = "";
    int maxGuests = 0;
    string[] amenities = [];
|};

# A host profile. Mirrors `rental.Host`.
#
# + hostId - Unique host identifier.
# + name - Full name.
# + email - Contact email address.
# + phone - Contact telephone number.
# + region - Region the host operates in.
public type Host record {|
    string hostId = "";
    string name = "";
    string email = "";
    string phone = "";
    string region = "";
|};

# A guest profile. Mirrors `rental.Guest`.
#
# + guestId - Unique guest identifier.
# + name - Full name.
# + email - Contact email address.
# + phone - Contact telephone number.
public type Guest record {|
    string guestId = "";
    string name = "";
    string email = "";
    string phone = "";
|};

# A reservation. Mirrors `rental.Booking`.
#
# + bookingId - Unique booking identifier.
# + propertyId - The property being booked.
# + guestId - The guest making the booking.
# + checkIn - ISO-8601 arrival date, inclusive.
# + checkOut - ISO-8601 departure date, exclusive.
# + totalCost - `pricePerNight * nights`.
# + state - PENDING, CONFIRMED or CANCELLED.
# + nights - Number of nights charged.
# + confirmedAt - Timestamp of confirmation, or "" while pending.
# + propertyName - Denormalised property name for display.
public type Booking record {|
    string bookingId = "";
    string propertyId = "";
    string guestId = "";
    string checkIn = "";
    string checkOut = "";
    float totalCost = 0.0;
    BookingState state = BOOKING_STATE_UNKNOWN;
    int nights = 0;
    string confirmedAt = "";
    string propertyName = "";
|};

# Request of `add_property`.
#
# + hostId - The registering host.
# + name - Display name of the listing.
# + location - Region or town.
# + propertyType - Category of accommodation.
# + pricePerNight - Nightly rate in NAD.
# + status - Initial availability.
# + description - Free text marketing copy.
# + maxGuests - Sleeping capacity.
# + amenities - Facilities offered.
public type AddPropertyRequest record {|
    string hostId = "";
    string name = "";
    string location = "";
    string propertyType = "";
    float pricePerNight = 0.0;
    PropertyStatus status = PROPERTY_STATUS_UNKNOWN;
    string description = "";
    int maxGuests = 0;
    string[] amenities = [];
|};

# Response of `add_property`.
#
# + success - Whether the listing was created.
# + message - Human readable outcome.
# + propertyId - The newly issued identifier.
# + property - The stored listing.
public type AddPropertyResponse record {|
    boolean success = false;
    string message = "";
    string propertyId = "";
    Property property = {};
|};

# Request of `update_property`. Blank / zero fields mean "leave unchanged".
#
# + propertyId - Key of the listing to patch.
# + hostId - Identifier proving ownership.
# + name - New display name.
# + location - New region or town.
# + propertyType - New category.
# + pricePerNight - New nightly rate.
# + status - New availability.
# + description - New marketing copy.
# + maxGuests - New sleeping capacity.
# + amenities - New facility list.
public type UpdatePropertyRequest record {|
    string propertyId = "";
    string hostId = "";
    string name = "";
    string location = "";
    string propertyType = "";
    float pricePerNight = 0.0;
    PropertyStatus status = PROPERTY_STATUS_UNKNOWN;
    string description = "";
    int maxGuests = 0;
    string[] amenities = [];
|};

# Response of `update_property`.
#
# + success - Whether the patch was applied.
# + message - Human readable outcome.
# + property - The listing after the patch.
public type UpdatePropertyResponse record {|
    boolean success = false;
    string message = "";
    Property property = {};
|};

# Request of `remove_property`.
#
# + propertyId - Key of the listing to delete.
# + hostId - Identifier proving ownership.
public type RemovePropertyRequest record {|
    string propertyId = "";
    string hostId = "";
|};

# Response of `remove_property`, carrying the host's remaining listings.
#
# + success - Whether the listing was deleted.
# + message - Human readable outcome.
# + region - The region the listings belong to.
# + remainingProperties - What the host still has listed in that region.
public type RemovePropertyResponse record {|
    boolean success = false;
    string message = "";
    string region = "";
    Property[] remainingProperties = [];
|};

# Request of `search_property`.
#
# + propertyId - The listing to look up.
public type SearchPropertyRequest record {|
    string propertyId = "";
|};

# Response of `search_property`.
#
# + found - Whether a listing with that id exists.
# + status - "AVAILABLE" or "NOT AVAILABLE".
# + message - Human readable outcome.
# + property - The listing, when found.
public type SearchPropertyResponse record {|
    boolean found = false;
    string status = "";
    string message = "";
    Property property = {};
|};

# Request of `book_property`.
#
# + propertyId - The listing to reserve.
# + guestId - The guest making the reservation.
# + checkIn - ISO-8601 arrival date.
# + checkOut - ISO-8601 departure date.
public type BookPropertyRequest record {|
    string propertyId = "";
    string guestId = "";
    string checkIn = "";
    string checkOut = "";
|};

# Response of `book_property`.
#
# + success - Whether the request entered the cart.
# + message - Human readable outcome.
# + bookingId - Cart entry id, needed by `confirm_booking`.
# + nights - Number of nights requested.
# + estimatedCost - Indicative total, re-checked on confirmation.
public type BookPropertyResponse record {|
    boolean success = false;
    string message = "";
    string bookingId = "";
    int nights = 0;
    float estimatedCost = 0.0;
|};

# Request of `confirm_booking`.
#
# + bookingId - The cart entry to finalise.
# + guestId - The guest that owns the cart entry.
public type ConfirmBookingRequest record {|
    string bookingId = "";
    string guestId = "";
|};

# Response of `confirm_booking`.
#
# + success - Whether the booking was finalised.
# + message - Human readable outcome.
# + booking - The confirmed booking.
public type ConfirmBookingResponse record {|
    boolean success = false;
    string message = "";
    Booking booking = {};
|};

# One element of the `create_users` client stream.
#
# + userId - Optional client supplied id; generated when blank.
# + name - Full name.
# + email - Contact email address.
# + role - HOST or GUEST.
# + phone - Contact telephone number.
# + region - Operating region; hosts only.
public type CreateUserRequest record {|
    string userId = "";
    string name = "";
    string email = "";
    UserRole role = USER_ROLE_UNKNOWN;
    string phone = "";
    string region = "";
|};

# The single response of `create_users`, sent after the stream closes.
#
# + success - `true` when at least one profile was created.
# + message - Human readable outcome.
# + totalReceived - How many elements arrived on the stream.
# + hostsCreated - How many host profiles were stored.
# + guestsCreated - How many guest profiles were stored.
# + failures - One line per rejected element.
# + createdIds - The identifiers that were issued.
public type CreateUsersSummary record {|
    boolean success = false;
    string message = "";
    int totalReceived = 0;
    int hostsCreated = 0;
    int guestsCreated = 0;
    string[] failures = [];
    string[] createdIds = [];
|};

# Request of `list_available_properties`. Every filter is optional.
#
# + location - Region or town filter.
# + minPrice - Lower bound on the nightly rate.
# + maxPrice - Upper bound on the nightly rate; `0.0` means no bound.
# + propertyType - Category filter.
# + minGuests - Minimum sleeping capacity.
public type ListAvailableRequest record {|
    string location = "";
    float minPrice = 0.0;
    float maxPrice = 0.0;
    string propertyType = "";
    int minGuests = 0;
|};

// ============================================================================
//  4. CONTEXT RECORDS
// ============================================================================
//  A "context" record pairs a message with the gRPC metadata headers that
//  travelled with it. Every RPC has a context variant so an application can
//  read or set headers without leaving the typed API.

# `Property` together with its gRPC headers.
#
# + content - The message.
# + headers - The gRPC metadata headers.
public type ContextProperty record {|
    Property content;
    map<string|string[]> headers;
|};

# A stream of `Property` together with its gRPC headers.
#
# + content - The message stream.
# + headers - The gRPC metadata headers.
public type ContextPropertyStream record {|
    stream<Property, error?> content;
    map<string|string[]> headers;
|};

# `AddPropertyRequest` together with its gRPC headers.
#
# + content - The message.
# + headers - The gRPC metadata headers.
public type ContextAddPropertyRequest record {|
    AddPropertyRequest content;
    map<string|string[]> headers;
|};

# `AddPropertyResponse` together with its gRPC headers.
#
# + content - The message.
# + headers - The gRPC metadata headers.
public type ContextAddPropertyResponse record {|
    AddPropertyResponse content;
    map<string|string[]> headers;
|};

# `UpdatePropertyRequest` together with its gRPC headers.
#
# + content - The message.
# + headers - The gRPC metadata headers.
public type ContextUpdatePropertyRequest record {|
    UpdatePropertyRequest content;
    map<string|string[]> headers;
|};

# `UpdatePropertyResponse` together with its gRPC headers.
#
# + content - The message.
# + headers - The gRPC metadata headers.
public type ContextUpdatePropertyResponse record {|
    UpdatePropertyResponse content;
    map<string|string[]> headers;
|};

# `RemovePropertyRequest` together with its gRPC headers.
#
# + content - The message.
# + headers - The gRPC metadata headers.
public type ContextRemovePropertyRequest record {|
    RemovePropertyRequest content;
    map<string|string[]> headers;
|};

# `RemovePropertyResponse` together with its gRPC headers.
#
# + content - The message.
# + headers - The gRPC metadata headers.
public type ContextRemovePropertyResponse record {|
    RemovePropertyResponse content;
    map<string|string[]> headers;
|};

# `SearchPropertyRequest` together with its gRPC headers.
#
# + content - The message.
# + headers - The gRPC metadata headers.
public type ContextSearchPropertyRequest record {|
    SearchPropertyRequest content;
    map<string|string[]> headers;
|};

# `SearchPropertyResponse` together with its gRPC headers.
#
# + content - The message.
# + headers - The gRPC metadata headers.
public type ContextSearchPropertyResponse record {|
    SearchPropertyResponse content;
    map<string|string[]> headers;
|};

# `BookPropertyRequest` together with its gRPC headers.
#
# + content - The message.
# + headers - The gRPC metadata headers.
public type ContextBookPropertyRequest record {|
    BookPropertyRequest content;
    map<string|string[]> headers;
|};

# `BookPropertyResponse` together with its gRPC headers.
#
# + content - The message.
# + headers - The gRPC metadata headers.
public type ContextBookPropertyResponse record {|
    BookPropertyResponse content;
    map<string|string[]> headers;
|};

# `ConfirmBookingRequest` together with its gRPC headers.
#
# + content - The message.
# + headers - The gRPC metadata headers.
public type ContextConfirmBookingRequest record {|
    ConfirmBookingRequest content;
    map<string|string[]> headers;
|};

# `ConfirmBookingResponse` together with its gRPC headers.
#
# + content - The message.
# + headers - The gRPC metadata headers.
public type ContextConfirmBookingResponse record {|
    ConfirmBookingResponse content;
    map<string|string[]> headers;
|};

# `CreateUserRequest` together with its gRPC headers.
#
# + content - The message.
# + headers - The gRPC metadata headers.
public type ContextCreateUserRequest record {|
    CreateUserRequest content;
    map<string|string[]> headers;
|};

# A stream of `CreateUserRequest` together with its gRPC headers.
#
# + content - The message stream.
# + headers - The gRPC metadata headers.
public type ContextCreateUserRequestStream record {|
    stream<CreateUserRequest, error?> content;
    map<string|string[]> headers;
|};

# `CreateUsersSummary` together with its gRPC headers.
#
# + content - The message.
# + headers - The gRPC metadata headers.
public type ContextCreateUsersSummary record {|
    CreateUsersSummary content;
    map<string|string[]> headers;
|};

# `ListAvailableRequest` together with its gRPC headers.
#
# + content - The message.
# + headers - The gRPC metadata headers.
public type ContextListAvailableRequest record {|
    ListAvailableRequest content;
    map<string|string[]> headers;
|};

// ============================================================================
//  5. THE TYPED CLIENT STUB
// ============================================================================

# Strongly typed client for the `rental.RentalService` gRPC service.
#
# One remote method is generated per RPC, plus a `...Context` variant that
# also surfaces the response headers. Streaming RPCs return the dedicated
# helper types declared in section 6.
public isolated client class RentalServiceClient {
    *grpc:AbstractClientEndpoint;

    private final grpc:Client grpcClient;

    # Connects the stub to a running server.
    #
    # + url - The server URL, e.g. `http://localhost:9090`.
    # + config - Optional transport configuration.
    # + return - A `grpc:Error` when the connection cannot be established.
    public isolated function init(string url, *grpc:ClientConfiguration config) returns grpc:Error? {
        self.grpcClient = check new (url, config);
        check self.grpcClient.initStub(self, RENTAL_DESC);
    }

    // ---- add_property (unary) ----------------------------------------

    # Registers a new listing.
    #
    # + req - The request message, with or without headers.
    # + return - The response message, or a `grpc:Error`.
    isolated remote function add_property(AddPropertyRequest|ContextAddPropertyRequest req)
            returns AddPropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        AddPropertyRequest message;
        if req is ContextAddPropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC(
            "rental.RentalService/add_property", message, headers);
        [anydata, map<string|string[]>][result, _] = payload;
        return <AddPropertyResponse>result;
    }

    # Registers a new listing and also returns the response headers.
    #
    # + req - The request message, with or without headers.
    # + return - The response message and headers, or a `grpc:Error`.
    isolated remote function add_propertyContext(AddPropertyRequest|ContextAddPropertyRequest req)
            returns ContextAddPropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        AddPropertyRequest message;
        if req is ContextAddPropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC(
            "rental.RentalService/add_property", message, headers);
        [anydata, map<string|string[]>][result, respHeaders] = payload;
        return {content: <AddPropertyResponse>result, headers: respHeaders};
    }

    // ---- update_property (unary) -------------------------------------

    # Patches an existing listing.
    #
    # + req - The request message, with or without headers.
    # + return - The response message, or a `grpc:Error`.
    isolated remote function update_property(UpdatePropertyRequest|ContextUpdatePropertyRequest req)
            returns UpdatePropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        UpdatePropertyRequest message;
        if req is ContextUpdatePropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC(
            "rental.RentalService/update_property", message, headers);
        [anydata, map<string|string[]>][result, _] = payload;
        return <UpdatePropertyResponse>result;
    }

    # Patches an existing listing and also returns the response headers.
    #
    # + req - The request message, with or without headers.
    # + return - The response message and headers, or a `grpc:Error`.
    isolated remote function update_propertyContext(UpdatePropertyRequest|ContextUpdatePropertyRequest req)
            returns ContextUpdatePropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        UpdatePropertyRequest message;
        if req is ContextUpdatePropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC(
            "rental.RentalService/update_property", message, headers);
        [anydata, map<string|string[]>][result, respHeaders] = payload;
        return {content: <UpdatePropertyResponse>result, headers: respHeaders};
    }

    // ---- remove_property (unary) -------------------------------------

    # Deletes a listing and returns what the host still has in that region.
    #
    # + req - The request message, with or without headers.
    # + return - The response message, or a `grpc:Error`.
    isolated remote function remove_property(RemovePropertyRequest|ContextRemovePropertyRequest req)
            returns RemovePropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        RemovePropertyRequest message;
        if req is ContextRemovePropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC(
            "rental.RentalService/remove_property", message, headers);
        [anydata, map<string|string[]>][result, _] = payload;
        return <RemovePropertyResponse>result;
    }

    # Deletes a listing and also returns the response headers.
    #
    # + req - The request message, with or without headers.
    # + return - The response message and headers, or a `grpc:Error`.
    isolated remote function remove_propertyContext(RemovePropertyRequest|ContextRemovePropertyRequest req)
            returns ContextRemovePropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        RemovePropertyRequest message;
        if req is ContextRemovePropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC(
            "rental.RentalService/remove_property", message, headers);
        [anydata, map<string|string[]>][result, respHeaders] = payload;
        return {content: <RemovePropertyResponse>result, headers: respHeaders};
    }

    // ---- search_property (unary) -------------------------------------

    # Looks a listing up by its identifier.
    #
    # + req - The request message, with or without headers.
    # + return - The response message, or a `grpc:Error`.
    isolated remote function search_property(SearchPropertyRequest|ContextSearchPropertyRequest req)
            returns SearchPropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        SearchPropertyRequest message;
        if req is ContextSearchPropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC(
            "rental.RentalService/search_property", message, headers);
        [anydata, map<string|string[]>][result, _] = payload;
        return <SearchPropertyResponse>result;
    }

    # Looks a listing up and also returns the response headers.
    #
    # + req - The request message, with or without headers.
    # + return - The response message and headers, or a `grpc:Error`.
    isolated remote function search_propertyContext(SearchPropertyRequest|ContextSearchPropertyRequest req)
            returns ContextSearchPropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        SearchPropertyRequest message;
        if req is ContextSearchPropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC(
            "rental.RentalService/search_property", message, headers);
        [anydata, map<string|string[]>][result, respHeaders] = payload;
        return {content: <SearchPropertyResponse>result, headers: respHeaders};
    }

    // ---- book_property (unary) ---------------------------------------

    # Places a date range into the guest's temporary booking cart.
    #
    # + req - The request message, with or without headers.
    # + return - The response message, or a `grpc:Error`.
    isolated remote function book_property(BookPropertyRequest|ContextBookPropertyRequest req)
            returns BookPropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        BookPropertyRequest message;
        if req is ContextBookPropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC(
            "rental.RentalService/book_property", message, headers);
        [anydata, map<string|string[]>][result, _] = payload;
        return <BookPropertyResponse>result;
    }

    # Places a date range into the cart and also returns the response headers.
    #
    # + req - The request message, with or without headers.
    # + return - The response message and headers, or a `grpc:Error`.
    isolated remote function book_propertyContext(BookPropertyRequest|ContextBookPropertyRequest req)
            returns ContextBookPropertyResponse|grpc:Error {
        map<string|string[]> headers = {};
        BookPropertyRequest message;
        if req is ContextBookPropertyRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC(
            "rental.RentalService/book_property", message, headers);
        [anydata, map<string|string[]>][result, respHeaders] = payload;
        return {content: <BookPropertyResponse>result, headers: respHeaders};
    }

    // ---- confirm_booking (unary) -------------------------------------

    # Finalises a cart entry into a confirmed booking.
    #
    # + req - The request message, with or without headers.
    # + return - The response message, or a `grpc:Error`.
    isolated remote function confirm_booking(ConfirmBookingRequest|ContextConfirmBookingRequest req)
            returns ConfirmBookingResponse|grpc:Error {
        map<string|string[]> headers = {};
        ConfirmBookingRequest message;
        if req is ContextConfirmBookingRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC(
            "rental.RentalService/confirm_booking", message, headers);
        [anydata, map<string|string[]>][result, _] = payload;
        return <ConfirmBookingResponse>result;
    }

    # Finalises a cart entry and also returns the response headers.
    #
    # + req - The request message, with or without headers.
    # + return - The response message and headers, or a `grpc:Error`.
    isolated remote function confirm_bookingContext(ConfirmBookingRequest|ContextConfirmBookingRequest req)
            returns ContextConfirmBookingResponse|grpc:Error {
        map<string|string[]> headers = {};
        ConfirmBookingRequest message;
        if req is ContextConfirmBookingRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeSimpleRPC(
            "rental.RentalService/confirm_booking", message, headers);
        [anydata, map<string|string[]>][result, respHeaders] = payload;
        return {content: <ConfirmBookingResponse>result, headers: respHeaders};
    }

    // ---- create_users (client streaming) ------------------------------

    # Opens a client-side stream over which many user profiles can be pushed.
    #
    # + return - A streaming client, or a `grpc:Error`.
    isolated remote function create_users() returns Create_usersStreamingClient|grpc:Error {
        grpc:StreamingClient sClient =
            check self.grpcClient->executeClientStreaming("rental.RentalService/create_users");
        return new Create_usersStreamingClient(sClient);
    }

    // ---- list_available_properties (server streaming) -----------------

    # Requests the available listings; the server pushes them back one by one.
    #
    # + req - The request message, with or without headers.
    # + return - A stream of listings, or a `grpc:Error`.
    isolated remote function list_available_properties(ListAvailableRequest|ContextListAvailableRequest req)
            returns stream<Property, grpc:Error?>|grpc:Error {
        map<string|string[]> headers = {};
        ListAvailableRequest message;
        if req is ContextListAvailableRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeServerStreaming(
            "rental.RentalService/list_available_properties", message, headers);
        [stream<anydata, grpc:Error?>, map<string|string[]>][result, _] = payload;
        PropertyStream outputStream = new PropertyStream(result);
        return new stream<Property, grpc:Error?>(outputStream);
    }

    # Requests the available listings and also returns the response headers.
    #
    # + req - The request message, with or without headers.
    # + return - A stream of listings plus headers, or a `grpc:Error`.
    isolated remote function list_available_propertiesContext(
            ListAvailableRequest|ContextListAvailableRequest req)
            returns ContextPropertyStream|grpc:Error {
        map<string|string[]> headers = {};
        ListAvailableRequest message;
        if req is ContextListAvailableRequest {
            message = req.content;
            headers = req.headers;
        } else {
            message = req;
        }
        var payload = check self.grpcClient->executeServerStreaming(
            "rental.RentalService/list_available_properties", message, headers);
        [stream<anydata, grpc:Error?>, map<string|string[]>][result, respHeaders] = payload;
        PropertyStream outputStream = new PropertyStream(result);
        return {content: new stream<Property, grpc:Error?>(outputStream), headers: respHeaders};
    }
}

// ============================================================================
//  6. STREAMING HELPERS
// ============================================================================

# Adapts the untyped `anydata` stream produced by the gRPC runtime into a
# typed `stream<Property, grpc:Error?>`.
public class PropertyStream {
    private stream<anydata, grpc:Error?> anydataStream;

    # Wraps an untyped stream.
    #
    # + anydataStream - The stream handed over by the gRPC runtime.
    public isolated function init(stream<anydata, grpc:Error?> anydataStream) {
        self.anydataStream = anydataStream;
    }

    # Pulls the next listing off the wire.
    #
    # + return - The next value, `()` at end of stream, or a `grpc:Error`.
    public isolated function next() returns record {|Property value;|}|grpc:Error? {
        var streamValue = self.anydataStream.next();
        if streamValue is () {
            return streamValue;
        } else if streamValue is grpc:Error {
            return streamValue;
        } else {
            record {|Property value;|} nextRecord = {value: <Property>streamValue.value};
            return nextRecord;
        }
    }

    # Closes the underlying stream and releases the connection.
    #
    # + return - A `grpc:Error` when the stream cannot be closed.
    public isolated function close() returns grpc:Error? {
        return self.anydataStream.close();
    }
}

# The client side handle of the `create_users` client-streaming RPC.
#
# The caller pushes as many `CreateUserRequest` messages as it likes, calls
# the complete() method to half-close the stream, then reads the one summary.
public client class Create_usersStreamingClient {
    private grpc:StreamingClient sClient;

    # Wraps the low level streaming client.
    #
    # + sClient - The streaming client handed over by the gRPC runtime.
    public isolated function init(grpc:StreamingClient sClient) {
        self.sClient = sClient;
    }

    # Pushes one user profile onto the stream.
    #
    # + message - The profile to send.
    # + return - A `grpc:Error` when the message cannot be sent.
    isolated remote function sendCreateUserRequest(CreateUserRequest message) returns grpc:Error? {
        return self.sClient->send(message);
    }

    # Pushes one user profile together with gRPC headers.
    #
    # + message - The profile and headers to send.
    # + return - A `grpc:Error` when the message cannot be sent.
    isolated remote function sendContextCreateUserRequest(ContextCreateUserRequest message)
            returns grpc:Error? {
        return self.sClient->send(message);
    }

    # Reads the single summary the server sends once the stream is closed.
    #
    # + return - The summary, `()` at end of stream, or a `grpc:Error`.
    isolated remote function receiveCreateUsersSummary() returns CreateUsersSummary|grpc:Error? {
        var response = check self.sClient->receive();
        if response is () {
            return response;
        } else {
            [anydata, map<string|string[]>][payload, _] = response;
            return <CreateUsersSummary>payload;
        }
    }

    # Reads the summary together with the response headers.
    #
    # + return - The summary and headers, `()` at end of stream, or an error.
    isolated remote function receiveContextCreateUsersSummary() returns ContextCreateUsersSummary|grpc:Error? {
        var response = check self.sClient->receive();
        if response is () {
            return response;
        } else {
            [anydata, map<string|string[]>][payload, headers] = response;
            return {content: <CreateUsersSummary>payload, headers: headers};
        }
    }

    # Aborts the stream with an error.
    #
    # + response - The error to raise on the server.
    # + return - A `grpc:Error` when the error cannot be delivered.
    isolated remote function sendError(grpc:Error response) returns grpc:Error? {
        return self.sClient->sendError(response);
    }

    # Half-closes the stream, telling the server no more profiles will arrive.
    #
    # + return - A `grpc:Error` when the stream cannot be closed.
    isolated remote function complete() returns grpc:Error? {
        return self.sClient->complete();
    }
}

// ============================================================================
//  7. SERVER SIDE CALLERS
// ============================================================================
//  These are used when a service method takes an explicit `grpc:Caller`
//  instead of returning its response. The service in `service.bal` uses the
//  simpler "return the value" style, so these are provided for completeness
//  and for any future handler that needs fine grained control of the wire.

# Caller for RPCs that answer with a `Property` (server streaming).
public client class RentalServicePropertyCaller {
    private grpc:Caller caller;

    # Wraps a runtime caller.
    #
    # + caller - The caller handed over by the gRPC runtime.
    public isolated function init(grpc:Caller caller) {
        self.caller = caller;
    }

    # The unique connection id of this caller.
    #
    # + return - The connection id.
    public isolated function getId() returns int {
        return self.caller.getId();
    }

    # Pushes one listing back to the client.
    #
    # + response - The listing to send.
    # + return - A `grpc:Error` when the message cannot be sent.
    isolated remote function sendProperty(Property response) returns grpc:Error? {
        return self.caller->send(response);
    }

    # Pushes one listing together with gRPC headers.
    #
    # + response - The listing and headers to send.
    # + return - A `grpc:Error` when the message cannot be sent.
    isolated remote function sendContextProperty(ContextProperty response) returns grpc:Error? {
        return self.caller->send(response);
    }

    # Terminates the stream with an error.
    #
    # + response - The error to raise on the client.
    # + return - A `grpc:Error` when the error cannot be delivered.
    isolated remote function sendError(grpc:Error response) returns grpc:Error? {
        return self.caller->sendError(response);
    }

    # Closes the stream cleanly.
    #
    # + return - A `grpc:Error` when the stream cannot be closed.
    isolated remote function complete() returns grpc:Error? {
        return self.caller->complete();
    }
}

# Caller for the `create_users` client-streaming RPC.
public client class RentalServiceCreateUsersSummaryCaller {
    private grpc:Caller caller;

    # Wraps a runtime caller.
    #
    # + caller - The caller handed over by the gRPC runtime.
    public isolated function init(grpc:Caller caller) {
        self.caller = caller;
    }

    # The unique connection id of this caller.
    #
    # + return - The connection id.
    public isolated function getId() returns int {
        return self.caller.getId();
    }

    # Sends the single summary back to the client.
    #
    # + response - The summary to send.
    # + return - A `grpc:Error` when the message cannot be sent.
    isolated remote function sendCreateUsersSummary(CreateUsersSummary response) returns grpc:Error? {
        return self.caller->send(response);
    }

    # Sends the summary together with gRPC headers.
    #
    # + response - The summary and headers to send.
    # + return - A `grpc:Error` when the message cannot be sent.
    isolated remote function sendContextCreateUsersSummary(ContextCreateUsersSummary response)
            returns grpc:Error? {
        return self.caller->send(response);
    }

    # Terminates the call with an error.
    #
    # + response - The error to raise on the client.
    # + return - A `grpc:Error` when the error cannot be delivered.
    isolated remote function sendError(grpc:Error response) returns grpc:Error? {
        return self.caller->sendError(response);
    }

    # Closes the call cleanly.
    #
    # + return - A `grpc:Error` when the call cannot be closed.
    isolated remote function complete() returns grpc:Error? {
        return self.caller->complete();
    }
}
