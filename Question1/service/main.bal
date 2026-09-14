import ballerina/http;
import ballerina/io;
import ballerina/log;

configurable int servicePort = 8080;

configurable boolean loadSeedData = true;

listener http:Listener libraryListener = new (servicePort);

final int seededAssets = loadSeedData ? seedDatabase() : 0;

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

    resource function get health() returns map<json> {
        return {
            "status": "UP",
            "service": "library-resource-management",
            "version": "1.0.0",
            "timestamp": currentTimestamp(),
            "assets": countAssets()
        };
    }

    resource function get summary() returns map<json> {
        return dashboardSummary();
    }

    resource function post assets(@http:Payload Asset asset) returns AssetCreatedResponse|ApiError {
        Asset|AppError created = createAsset(asset);
        if created is AppError {
            return toErrorResponse(created, "/assets");
        }
        log:printInfo("Asset created", assetTag = created.assetTag);
        AssetCreatedResponse response = {body: created};
        return response;
    }

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

    resource function get assets/[string assetTag]() returns Asset|ApiError {
        Asset|AppError result = getAsset(assetTag);
        if result is AppError {
            return toErrorResponse(result, string `/assets/${assetTag}`);
        }
        return result;
    }

    resource function put assets/[string assetTag](@http:Payload AssetUpdate update)
            returns Asset|ApiError {
        Asset|AppError result = updateAsset(assetTag, update);
        if result is AppError {
            return toErrorResponse(result, string `/assets/${assetTag}`);
        }
        log:printInfo("Asset updated", assetTag = result.assetTag);
        return result;
    }

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

    resource function get assets/institution/[string institution]() returns Asset[]|ApiError {
        Asset[]|AppError result = listByInstitution(institution);
        if result is AppError {
            return toErrorResponse(result, string `/assets/institution/${institution}`);
        }
        return result;
    }

    resource function get assets/site/[string site]() returns Asset[]|ApiError {
        Asset[]|AppError result = listBySite(site);
        if result is AppError {
            return toErrorResponse(result, string `/assets/site/${site}`);
        }
        return result;
    }

    resource function get institutions() returns string[] {
        return listInstitutions();
    }

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

    resource function get sites(string? institution = ()) returns string[] {
        return listSites(institution);
    }

    resource function get maintenance/overdue(string? institution = (), string? site = (),
            boolean includeBookings = false) returns OverdueSchedule[]|ApiError {
        OverdueSchedule[]|AppError result = overdueSchedules(institution, site, includeBookings);
        if result is AppError {
            return toErrorResponse(result, "/maintenance/overdue");
        }
        return result;
    }

    resource function post assets/[string assetTag]/loan(@http:Payload LoanRequest request)
            returns Asset|ApiError {
        Asset|AppError result = loanAsset(assetTag, request);
        if result is AppError {
            return toErrorResponse(result, string `/assets/${assetTag}/loan`);
        }
        log:printInfo("Asset loaned", assetTag = result.assetTag, borrower = request.borrower);
        return result;
    }

    resource function post assets/[string assetTag]/'return(@http:Payload ReturnRequest request)
            returns Asset|ApiError {
        Asset|AppError result = returnAsset(assetTag, request);
        if result is AppError {
            return toErrorResponse(result, string `/assets/${assetTag}/return`);
        }
        log:printInfo("Asset returned", assetTag = result.assetTag);
        return result;
    }

    resource function get loans(string? assetTag = ()) returns LoanRecord[] {
        return loanHistory(assetTag);
    }

    resource function post assets/[string assetTag]/components(@http:Payload ComponentRequest request)
            returns Asset|ApiError {
        Asset|AppError result = addComponent(assetTag, request);
        if result is AppError {
            return toErrorResponse(result, string `/assets/${assetTag}/components`);
        }
        return result;
    }

    resource function delete assets/[string assetTag]/components/[string componentId]()
            returns Asset|ApiError {
        Asset|AppError result = removeComponent(assetTag, componentId);
        if result is AppError {
            return toErrorResponse(result,
                string `/assets/${assetTag}/components/${componentId}`);
        }
        return result;
    }

    resource function post assets/[string assetTag]/schedules(@http:Payload ScheduleRequest request)
            returns Asset|ApiError {
        Asset|AppError result = addSchedule(assetTag, request);
        if result is AppError {
            return toErrorResponse(result, string `/assets/${assetTag}/schedules`);
        }
        return result;
    }

    resource function put assets/[string assetTag]/schedules/[string scheduleId](
            @http:Payload ScheduleUpdate update) returns Asset|ApiError {
        Asset|AppError result = updateSchedule(assetTag, scheduleId, update);
        if result is AppError {
            return toErrorResponse(result, string `/assets/${assetTag}/schedules/${scheduleId}`);
        }
        return result;
    }

    resource function delete assets/[string assetTag]/schedules/[string scheduleId]()
            returns Asset|ApiError {
        Asset|AppError result = removeSchedule(assetTag, scheduleId);
        if result is AppError {
            return toErrorResponse(result,
                string `/assets/${assetTag}/schedules/${scheduleId}`);
        }
        return result;
    }

    resource function post assets/[string assetTag]/workorders(@http:Payload WorkOrderRequest request)
            returns Asset|ApiError {
        Asset|AppError result = createWorkOrder(assetTag, request);
        if result is AppError {
            return toErrorResponse(result, string `/assets/${assetTag}/workorders`);
        }
        log:printInfo("Work order created", assetTag = assetTag);
        return result;
    }

    resource function put assets/[string assetTag]/workorders/[string orderId](
            @http:Payload WorkOrderUpdate update) returns Asset|ApiError {
        Asset|AppError result = updateWorkOrder(assetTag, orderId, update);
        if result is AppError {
            return toErrorResponse(result,
                string `/assets/${assetTag}/workorders/${orderId}`);
        }
        return result;
    }

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
