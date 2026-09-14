import ballerina/grpc;
import ballerina/io;
import ballerina/log;

configurable int serverPort = 9090;
configurable boolean loadSeedData = true;
listener grpc:Listener rentalListener = new (serverPort);
final int seededProperties = loadSeedData ? seedDatabase() : 0;

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
