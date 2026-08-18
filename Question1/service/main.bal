// ============================================================================
//  DSA612S - Assignment 1 - Question 1
//  Distributed Library and Resource Management System
//  ---------------------------------------------------------------------------
//  main.bal
//  ---------------------------------------------------------------------------
//  The *transport layer*. This file is deliberately thin: each resource
//  function does three things and nothing else.
//
//     1. Hand the request parameters to the business layer in `services.bal`.
//     2. Wrap a success in the correct typed HTTP response record.
//     3. Delegate any failure to `toErrorResponse`, which selects between
//        400 / 404 / 409 / 500 based on the *type* of the error.
//
//  Because every resource function declares its full return union, the
//  OpenAPI contract that `bal openapi -i main.bal` generates is exact, and a
//  reader can see the complete set of outcomes at a glance.
// ============================================================================

import ballerina/http;
import ballerina/io;
import ballerina/log;

// ============================================================================
//  SECTION 1 - CONFIGURATION AND BOOTSTRAP
// ============================================================================

# TCP port the API listens on. Override at run time with
# `bal run -- -CservicePort=9090` or via `Config.toml`.
configurable int servicePort = 8080;

# Whether the demonstration data set should be loaded at start up.
configurable boolean loadSeedData = true;

# The shared HTTP listener. A single listener keeps the whole API on one port.
listener http:Listener libraryListener = new (servicePort);

# Number of demonstration assets loaded during module initialisation.
#
# Module level variable initialisers run *before* any listener starts
# accepting traffic, which guarantees the very first request already sees a
# fully populated store.
final int seededAssets = loadSeedData ? seedDatabase() : 0;

# Entry point. Services start automatically once module initialisation
# completes; `main` only prints the operator banner.
public function main() {
    io:println("============================================================");
    io:println("  DSA612S - Library and Resource Management System (REST)");
    io:println("  Ministry of Higher Education, Training and Innovations");
    io:println("============================================================");
    io:println(string `  Listening on : http://localhost:${servicePort}`);
    io:println(string `  Seeded assets: ${seededAssets}`);
    io:println(string `  Health check : http://localhost:${servicePort}/health`);
    io:println("  Press Ctrl+C to stop the server.");
    io:println("============================================================");
    log:printInfo("Library REST API started", port = servicePort, seeded = seededAssets);
}

// ============================================================================
//  SECTION 2 - THE API SERVICE
// ============================================================================

# The complete Library and Resource Management API.
#
# CORS is enabled for every origin so that the bonus HTML/CSS/JavaScript
# dashboard can call the API directly from a `file://` page or from any local
# web server without a proxy.
@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allowHeaders: ["Content-Type", "Accept", "Origin", "Authorization"],
        exposeHeaders: ["Content-Type"],
        maxAge: 86400
    }
}
service / on libraryListener {

    // ------------------------------------------------------------------
    //  2.1  Health and dashboard summary
    // ------------------------------------------------------------------

    # Liveness probe used by the CLI client and the web dashboard to confirm
    # the API is reachable before showing the menu.
    #
    # + return - A small status document.
    resource function get health() returns map<json> {
        return {
            "status": "UP",
            "service": "library-resource-management",
            "version": "1.0.0",
            "timestamp": currentTimestamp(),
            "assets": countAssets()
        };
    }

    # Headline counters for the dashboard tiles.
    #
    # + return - Totals per status plus overdue and active loan counts.
    resource function get summary() returns map<json> {
        return dashboardSummary();
    }

    // ------------------------------------------------------------------
    //  2.2  Asset CRUD
    // ------------------------------------------------------------------

    # `POST /assets` - creates a new asset.
    #
    # + asset - The asset to create. `assetTag` must be globally unique.
    # + return - `201` with the stored asset, `400` when the payload is
    #            invalid, `409` when the tag is already in use, or `500`.
    resource function post assets(@http:Payload Asset asset) returns AssetCreatedResponse|ApiError {
        Asset|AppError created = createAsset(asset);
        if created is AppError {
            return toErrorResponse(created, "/assets");
        }
        log:printInfo("Asset created", assetTag = created.assetTag);
        AssetCreatedResponse response = {body: created};
        return response;
    }

    # `GET /assets` - lists every asset, with optional filtering.
    #
    # All four query parameters are optional and combine with AND semantics,
    # so `GET /assets?institution=UNAM&status=AVAILABLE` is valid.
    #
    # + q - Free text matched against tag, name, description, institution, site.
    # + institution - Exact institution filter, case insensitive.
    # + site - Exact campus / site filter, case insensitive.
    # + status - Exact status filter.
    # + return - The matching assets, or `400` when `status` is not a legal
    #            value, or `500`.
    resource function get assets(string? q = (), string? institution = (),
            string? site = (), string? status = ()) returns Asset[]|ApiError {

        AssetStatus? parsedStatus = ();
        if status is string && status.trim().length() > 0 {
            AssetStatus|error candidate = status.trim().toUpperAscii().ensureType();
            if candidate is error {
                return toErrorResponse(
                    error ValidationError(
                        string `Query parameter 'status' must be one of AVAILABLE, LOANED_OUT, ` +
                        string `OCCUPIED, UNDER_MAINTENANCE or DISPOSED; received '${status}'.`),
                    "/assets");
            }
            parsedStatus = candidate;
        }
        return searchAssets(q, institution, site, parsedStatus);
    }

    # `GET /assets/{assetTag}` - reads one asset.
    #
    # + assetTag - The unique tag of the asset.
    # + return - The asset, `404` when it does not exist, or `500`.
    resource function get assets/[string assetTag]() returns Asset|ApiError {
        Asset|AppError result = getAsset(assetTag);
        if result is AppError {
            return toErrorResponse(result, string `/assets/${assetTag}`);
        }
        return result;
    }

    # `PUT /assets/{assetTag}` - applies a partial update.
    #
    # + assetTag - The unique tag of the asset to modify.
    # + update - The fields to change; omitted fields keep their stored value.
    # + return - The updated asset, `400`, `404`, `409` or `500`.
    resource function put assets/[string assetTag](@http:Payload AssetUpdate update)
            returns Asset|ApiError {
        Asset|AppError result = updateAsset(assetTag, update);
        if result is AppError {
            return toErrorResponse(result, string `/assets/${assetTag}`);
        }
        log:printInfo("Asset updated", assetTag = result.assetTag);
        return result;
    }

    # `DELETE /assets/{assetTag}` - permanently removes an asset.
    #
    # + assetTag - The unique tag of the asset to remove.
    # + return - A confirmation, `404`, `409` when the asset is out on loan,
    #            or `500`.
    resource function delete assets/[string assetTag]() returns OperationResult|ApiError {
        Asset|AppError result = deleteAsset(assetTag);
        if result is AppError {
            return toErrorResponse(result, string `/assets/${assetTag}`);
        }
        log:printInfo("Asset deleted", assetTag = result.assetTag);
        return {
            message: string `Asset '${result.assetTag}' was deleted successfully.`,
            assetTag: result.assetTag
        };
    }

    // ------------------------------------------------------------------
    //  2.3  Institution and campus views
    // ------------------------------------------------------------------

    # `GET /assets/institution/{institution}` - every asset owned by one
    # institution. Remember to percent-encode names that contain spaces.
    #
    # + institution - The institution name, matched case insensitively.
    # + return - The matching assets, `400` for a blank name, or `500`.
    resource function get assets/institution/[string institution]() returns Asset[]|ApiError {
        Asset[]|AppError result = listByInstitution(institution);
        if result is AppError {
            return toErrorResponse(result, string `/assets/institution/${institution}`);
        }
        return result;
    }

    # `GET /assets/site/{site}` - every asset located at one campus or site.
    #
    # + site - The site name, matched case insensitively.
    # + return - The matching assets, `400` for a blank name, or `500`.
    resource function get assets/site/[string site]() returns Asset[]|ApiError {
        Asset[]|AppError result = listBySite(site);
        if result is AppError {
            return toErrorResponse(result, string `/assets/site/${site}`);
        }
        return result;
    }

    # `GET /institutions` - the distinct institutions in the listing.
    #
    # + return - A sorted list of institution names.
    resource function get institutions() returns string[] {
        return listInstitutions();
    }

    # `POST /institutions` - adds an institution to the listing.
    #
    # This is the counterpart to `DELETE /institutions/{institution}`: an
    # institution can be accredited and listed before any of its assets have
    # been captured.
    #
    # + request - The institution's name and an optional description.
    # + return - `201` with the stored institution, `400` when the name is
    #            blank or too long, `409` when it is already listed, or `500`.
    resource function post institutions(@http:Payload InstitutionRequest request)
            returns InstitutionCreatedResponse|ApiError {
        Institution|AppError registered = registerInstitution(request);
        if registered is AppError {
            return toErrorResponse(registered, "/institutions");
        }
        log:printInfo("Institution registered", institution = registered.name);
        InstitutionCreatedResponse response = {body: registered};
        return response;
    }

    # `DELETE /institutions/{institution}` - withdraws an institution from the
    # listing, removing its registry row and every asset it owns.
    #
    # + institution - The institution to withdraw.
    # + return - The tags that were removed, `404`, `409` or `500`.
    resource function delete institutions/[string institution]() returns map<json>|ApiError {
        string[]|AppError removed = removeInstitution(institution);
        if removed is AppError {
            return toErrorResponse(removed, string `/institutions/${institution}`);
        }
        log:printInfo("Institution withdrawn", institution = institution, assets = removed.length());
        return {
            "message": string `Institution '${institution}' and ${removed.length()} asset(s) were removed.`,
            "institution": institution,
            "removedAssetTags": removed
        };
    }

    # `GET /sites` - the distinct campuses / sites, optionally narrowed.
    #
    # + institution - Optional institution to narrow the list by.
    # + return - A sorted list of site names.
    resource function get sites(string? institution = ()) returns string[] {
        return listSites(institution);
    }

    // ------------------------------------------------------------------
    //  2.4  Maintenance and overdue reporting
    // ------------------------------------------------------------------

    # `GET /maintenance/overdue` - every schedule whose due date has passed.
    #
    # + institution - Optional institution filter.
    # + site - Optional campus / site filter.
    # + includeBookings - Set to `true` to also list past room bookings.
    # + return - The overdue rows, most overdue first, `400` or `500`.
    resource function get maintenance/overdue(string? institution = (), string? site = (),
            boolean includeBookings = false) returns OverdueSchedule[]|ApiError {
        OverdueSchedule[]|AppError result = overdueSchedules(institution, site, includeBookings);
        if result is AppError {
            return toErrorResponse(result, "/maintenance/overdue");
        }
        return result;
    }

    // ------------------------------------------------------------------
    //  2.5  Loaning and returning
    // ------------------------------------------------------------------

    # `POST /assets/{assetTag}/loan` - issues an asset or books a space.
    #
    # + assetTag - The asset to issue.
    # + request - Borrower details and the optional return date.
    # + return - The asset in its new status, `400`, `404`, `409` or `500`.
    resource function post assets/[string assetTag]/loan(@http:Payload LoanRequest request)
            returns Asset|ApiError {
        Asset|AppError result = loanAsset(assetTag, request);
        if result is AppError {
            return toErrorResponse(result, string `/assets/${assetTag}/loan`);
        }
        log:printInfo("Asset loaned", assetTag = result.assetTag, borrower = request.borrower);
        return result;
    }

    # `POST /assets/{assetTag}/return` - accepts an asset back.
    #
    # Send `{}` as the body when there is nothing special to report.
    #
    # + assetTag - The asset being handed back.
    # + request - Optional condition notes and the maintenance flag.
    # + return - The asset in its new status, `400`, `404`, `409` or `500`.
    resource function post assets/[string assetTag]/'return(@http:Payload ReturnRequest request)
            returns Asset|ApiError {
        Asset|AppError result = returnAsset(assetTag, request);
        if result is AppError {
            return toErrorResponse(result, string `/assets/${assetTag}/return`);
        }
        log:printInfo("Asset returned", assetTag = result.assetTag);
        return result;
    }

    # `GET /loans` - the loan and booking audit trail, newest first.
    #
    # + assetTag - Optional asset to narrow the history to.
    # + return - The matching loan records.
    resource function get loans(string? assetTag = ()) returns LoanRecord[] {
        return loanHistory(assetTag);
    }

    // ------------------------------------------------------------------
    //  2.6  Component management
    // ------------------------------------------------------------------

    # `POST /assets/{assetTag}/components` - attaches a component.
    #
    # + assetTag - The parent asset.
    # + request - The component to add; `compId` is generated when omitted.
    # + return - The parent asset, `400`, `404`, `409` or `500`.
    resource function post assets/[string assetTag]/components(@http:Payload ComponentRequest request)
            returns Asset|ApiError {
        Asset|AppError result = addComponent(assetTag, request);
        if result is AppError {
            return toErrorResponse(result, string `/assets/${assetTag}/components`);
        }
        return result;
    }

    # `DELETE /assets/{assetTag}/components/{componentId}` - detaches a
    # component.
    #
    # + assetTag - The parent asset.
    # + componentId - The component to remove.
    # + return - The parent asset, `400`, `404` or `500`.
    resource function delete assets/[string assetTag]/components/[string componentId]()
            returns Asset|ApiError {
        Asset|AppError result = removeComponent(assetTag, componentId);
        if result is AppError {
            return toErrorResponse(result,
                string `/assets/${assetTag}/components/${componentId}`);
        }
        return result;
    }

    // ------------------------------------------------------------------
    //  2.7  Schedule management
    // ------------------------------------------------------------------

    # `POST /assets/{assetTag}/schedules` - adds a maintenance, servicing,
    # inspection or booking schedule.
    #
    # + assetTag - The parent asset.
    # + request - The schedule to add; `scheduleId` is generated when omitted.
    # + return - The parent asset, `400`, `404`, `409` or `500`.
    resource function post assets/[string assetTag]/schedules(@http:Payload ScheduleRequest request)
            returns Asset|ApiError {
        Asset|AppError result = addSchedule(assetTag, request);
        if result is AppError {
            return toErrorResponse(result, string `/assets/${assetTag}/schedules`);
        }
        return result;
    }

    # `DELETE /assets/{assetTag}/schedules/{scheduleId}` - removes a schedule.
    #
    # + assetTag - The parent asset.
    # + scheduleId - The schedule to remove.
    # + return - The parent asset, `400`, `404` or `500`.
    resource function delete assets/[string assetTag]/schedules/[string scheduleId]()
            returns Asset|ApiError {
        Asset|AppError result = removeSchedule(assetTag, scheduleId);
        if result is AppError {
            return toErrorResponse(result,
                string `/assets/${assetTag}/schedules/${scheduleId}`);
        }
        return result;
    }

    // ------------------------------------------------------------------
    //  2.8  Work order and task management
    // ------------------------------------------------------------------

    # `POST /assets/{assetTag}/workorders` - opens a work order.
    #
    # + assetTag - The parent asset.
    # + request - The work order to create, including its initial tasks.
    # + return - The parent asset, `400`, `404`, `409` or `500`.
    resource function post assets/[string assetTag]/workorders(@http:Payload WorkOrderRequest request)
            returns Asset|ApiError {
        Asset|AppError result = createWorkOrder(assetTag, request);
        if result is AppError {
            return toErrorResponse(result, string `/assets/${assetTag}/workorders`);
        }
        log:printInfo("Work order created", assetTag = assetTag);
        return result;
    }

    # `PUT /assets/{assetTag}/workorders/{orderId}` - updates a work order.
    #
    # + assetTag - The parent asset.
    # + orderId - The work order to modify.
    # + update - The fields to change.
    # + return - The parent asset, `400`, `404` or `500`.
    resource function put assets/[string assetTag]/workorders/[string orderId](
            @http:Payload WorkOrderUpdate update) returns Asset|ApiError {
        Asset|AppError result = updateWorkOrder(assetTag, orderId, update);
        if result is AppError {
            return toErrorResponse(result,
                string `/assets/${assetTag}/workorders/${orderId}`);
        }
        return result;
    }

    # `DELETE /assets/{assetTag}/workorders/{orderId}` - deletes a work order.
    #
    # + assetTag - The parent asset.
    # + orderId - The work order to delete.
    # + return - The parent asset, `400`, `404` or `500`.
    resource function delete assets/[string assetTag]/workorders/[string orderId]()
            returns Asset|ApiError {
        Asset|AppError result = deleteWorkOrder(assetTag, orderId);
        if result is AppError {
            return toErrorResponse(result,
                string `/assets/${assetTag}/workorders/${orderId}`);
        }
        return result;
    }
}
