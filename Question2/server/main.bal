// ============================================================================
//  DSA612S - Assignment 1 - Question 2
//  Rental Accommodation System - gRPC Server
//  ---------------------------------------------------------------------------
//  main.bal
//  ---------------------------------------------------------------------------
//  The *bootstrap layer*. It owns three things and nothing else:
//
//    1. The configurable knobs (`serverPort`, `loadSeedData`).
//    2. The gRPC listener that `service.bal` attaches to.
//    3. Module initialisation - loading the demonstration data set - and the
//       operator banner printed on start up.
//
//  Keeping bootstrap separate from the RPC implementations means the service
//  can be moved onto a different port, or run with an empty store, without a
//  single line of business logic changing.
// ============================================================================

import ballerina/grpc;
import ballerina/io;
import ballerina/log;

// ============================================================================
//  SECTION 1 - CONFIGURATION
// ============================================================================

# TCP port the gRPC server listens on. Override with a `Config.toml` entry or
# `bal run -- -CserverPort=9091`.
configurable int serverPort = 9090;

# Whether the demonstration data set should be loaded at start up. Set to
# `false` to start with a completely empty catalogue.
configurable boolean loadSeedData = true;

// ============================================================================
//  SECTION 2 - THE LISTENER
// ============================================================================

# The shared gRPC listener. `service.bal` attaches `RentalService` to it.
#
# HTTP/2 is used, which is what allows a single TCP connection to carry the
# client-side stream of `create_users` and the server-side stream of
# `list_available_properties` without opening extra sockets.
listener grpc:Listener rentalListener = new (serverPort);

// ============================================================================
//  SECTION 3 - MODULE INITIALISATION
// ============================================================================

# Number of demonstration properties loaded during module initialisation.
#
# A module level variable initialiser runs *before* the listener starts
# accepting calls, so the very first RPC already sees a populated catalogue.
final int seededProperties = loadSeedData ? seedDatabase() : 0;

# Entry point. The listener is started automatically once module
# initialisation completes; `main` only prints the operator banner.
public function main() {
    io:println("================================================================");
    io:println("   DSA612S - RENTAL ACCOMMODATION SYSTEM (gRPC)");
    io:println("   Ministry of Tourism - Republic of Namibia");
    io:println("================================================================");
    io:println(string `   Listening on   : http://localhost:${serverPort}`);
    io:println(string `   Service        : rental.RentalService`);
    io:println(string `   Properties     : ${seededProperties} seeded`);
    io:println(string `   Hosts / Guests : ${allHosts().length()} / ${allGuests().length()}`);
    io:println("----------------------------------------------------------------");
    io:println("   RPCs exposed:");
    io:println("     add_property               (unary)");
    io:println("     update_property            (unary)");
    io:println("     remove_property            (unary)");
    io:println("     search_property            (unary)");
    io:println("     book_property              (unary)");
    io:println("     confirm_booking            (unary)");
    io:println("     create_users               (client streaming)");
    io:println("     list_available_properties  (server streaming)");
    io:println("----------------------------------------------------------------");
    io:println("   Seeded host ids : HOST-001, HOST-002, HOST-003");
    io:println("   Seeded guest ids: GUEST-001, GUEST-002, GUEST-003");
    io:println("   Press Ctrl+C to stop the server.");
    io:println("================================================================");

    log:printInfo("Rental gRPC server started",
        port = serverPort,
        properties = seededProperties,
        hosts = allHosts().length(),
        guests = allGuests().length());
}
