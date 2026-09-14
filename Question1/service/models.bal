import ballerina/http;

# The life-cycle status of a library / campus resource.
#
# + AVAILABLE - Free to be loaned out or booked.
# + LOANED_OUT - Physically issued to a borrower (books, laptops, thin clients).
# + OCCUPIED - Currently in use as a physical space (labs, meeting rooms).
# + UNDER_MAINTENANCE - Withdrawn from circulation for servicing or repair.
# + DISPOSED - Written off; kept for audit purposes but no longer usable.
public enum AssetStatus {
    AVAILABLE = "AVAILABLE",
    LOANED_OUT = "LOANED_OUT",
    OCCUPIED = "OCCUPIED",
    UNDER_MAINTENANCE = "UNDER_MAINTENANCE",
    DISPOSED = "DISPOSED"
}

# The category of a schedule entry attached to an asset.
#
# + MAINTENANCE - Routine preventative maintenance (e.g. quarterly calibration).
# + SERVICING - Vendor / technician servicing visit.
# + INSPECTION - Compliance or safety inspection.
# + BOOKING - A reservation of a physical space for a period of time.
public enum ScheduleType {
    MAINTENANCE = "MAINTENANCE",
    SERVICING = "SERVICING",
    INSPECTION = "INSPECTION",
    BOOKING = "BOOKING"
}

# The state of a work order raised against a faulty resource.
#
# + OPEN - Logged but not yet started.
# + IN_PROGRESS - A technician is actively working on it.
# + CLOSED - Work finished and signed off.
# + CANCELLED - Abandoned (duplicate, raised in error, asset disposed).
public enum WorkOrderStatus {
    OPEN = "OPEN",
    IN_PROGRESS = "IN_PROGRESS",
    CLOSED = "CLOSED",
    CANCELLED = "CANCELLED"
}

# A replaceable sub-part of a complex asset (e.g. the stepper motor of a
# 3D printer, or the battery of a loan laptop).
#
# + compId - Unique identifier of the component *within its parent asset*.
# + name - Human readable component name.
# + description - Free text explaining the role of the component.
public type Component record {|
    string compId;
    string name;
    string description = "";
|};

# A dated entry attached to an asset: maintenance, servicing, inspection or a
# room booking. `dueDate` is always an ISO-8601 calendar date (YYYY-MM-DD),
# which conveniently sorts and compares correctly as a plain string.
#
# + scheduleId - Unique identifier of the schedule within its parent asset.
# + type - The category of this schedule entry.
# + dueDate - ISO-8601 calendar date (YYYY-MM-DD) on which the work falls due.
# + description - Free text describing the work to be carried out.
public type Schedule record {|
    string scheduleId;
    ScheduleType 'type = MAINTENANCE;
    string dueDate;
    string description = "";
|};

# A single unit of work belonging to a work order (e.g. "replace screen").
#
# + taskId - Unique identifier of the task within its parent work order.
# + description - What has to be done.
# + completed - Whether the technician has finished this task.
public type Task record {|
    string taskId;
    string description;
    boolean completed = false;
|};

# A repair / servicing job raised against an asset, made up of sub-tasks.
#
# + orderId - Unique identifier of the work order within its parent asset.
# + status - Current life-cycle state of the job.
# + description - Summary of the fault being addressed.
# + tasks - The individual steps required to complete the job.
public type WorkOrder record {|
    string orderId;
    WorkOrderStatus status = OPEN;
    string description;
    Task[] tasks = [];
|};

# The aggregate root of the whole system: a library or campus resource.
#
# `assetTag` is marked `readonly` because it is the primary key of the
# `table<Asset> key(assetTag)` in-memory store - Ballerina requires table key
# fields to be immutable.
#
# + assetTag - Ministry-wide unique tag, e.g. "NUST-LIB-3DP-001".
# + name - Human readable name of the resource.
# + description - Long form description of the resource.
# + institution - Registered institution of higher learning that owns it.
# + site - Campus / site / room where the asset physically lives.
# + status - Current availability status.
# + dateAcquired - ISO-8601 calendar date the asset was acquired.
# + components - Replaceable sub-parts of the asset.
# + schedules - Maintenance / servicing / booking schedule entries.
# + workOrders - Repair jobs raised against the asset.
public type Asset record {|
    readonly string assetTag;
    string name;
    string description = "";
    string institution;
    string site;
    AssetStatus status = AVAILABLE;
    string dateAcquired;
    Component[] components = [];
    Schedule[] schedules = [];
    WorkOrder[] workOrders = [];
|};

# An audit trail entry describing one loan / booking of an asset.
#
# The assignment's asset payload does not carry borrower information, so loans
# are tracked in a dedicated store instead of polluting the `Asset` record.
#
# + loanId - Unique identifier of this loan record.
# + assetTag - The asset that was loaned or booked.
# + borrower - Staff number, student number or name of the borrower.
# + loanedOn - ISO-8601 date on which the asset left the shelf.
# + dueDate - ISO-8601 date on which the asset is expected back.
# + returnedOn - ISO-8601 date the asset came back, or `()` while still out.
# + active - `true` while the asset is still in the borrower's hands.
public type LoanRecord record {|
    readonly string loanId;
    string assetTag;
    string borrower;
    string loanedOn;
    string dueDate;
    string? returnedOn = ();
    boolean active = true;
|};

# A registered institution of higher learning.
#
# An institution is normally implied by the assets that belong to it, but the
# ministry also needs to register one before any of its assets arrive. This
# record is that standalone registry entry; `listInstitutions` merges these
# names with the ones derived from the asset table, so an institution appears
# in the listing whether it was registered explicitly or simply owns an asset.
#
# + name - The institution's full registered name; the unique key.
# + description - Free text, for example the institution's abbreviation.
# + registeredOn - ISO-8601 date the institution was added to the platform.
public type Institution record {|
    readonly string name;
    string description = "";
    string registeredOn;
|};

# Partial update payload for `PUT /assets/{assetTag}`.
#
# Every field is optional: only the fields present in the JSON body are
# applied to the stored asset. `assetTag` is deliberately absent because the
# primary key may never be changed through an update.
#
# + name - New human readable name.
# + description - New long form description.
# + institution - New owning institution.
# + site - New campus / site.
# + status - New availability status.
# + dateAcquired - Corrected acquisition date.
# + components - Wholesale replacement of the component list.
# + schedules - Wholesale replacement of the schedule list.
# + workOrders - Wholesale replacement of the work order list.
public type AssetUpdate record {|
    string name?;
    string description?;
    string institution?;
    string site?;
    AssetStatus status?;
    string dateAcquired?;
    Component[] components?;
    Schedule[] schedules?;
    WorkOrder[] workOrders?;
|};

# Payload for `POST /assets/{assetTag}/components`.
#
# + compId - Optional client supplied id; the server generates one if omitted.
# + name - Human readable component name (required, must not be blank).
# + description - Free text explaining the role of the component.
public type ComponentRequest record {|
    string compId?;
    string name;
    string description = "";
|};

# Payload for `POST /assets/{assetTag}/schedules`.
#
# + scheduleId - Optional client supplied id; generated by the server if absent.
# + type - Category of the schedule entry.
# + dueDate - ISO-8601 calendar date (YYYY-MM-DD); validated by the service.
# + description - Free text describing the work.
public type ScheduleRequest record {|
    string scheduleId?;
    ScheduleType 'type = MAINTENANCE;
    string dueDate;
    string description = "";
|};

public type ScheduleUpdate record {|
    ScheduleType 'type?;
    string dueDate?;
    string description?;
|};

# A task supplied as part of a work order request.
#
# + taskId - Optional client supplied id; generated by the server if absent.
# + description - What has to be done (required, must not be blank).
# + completed - Whether this task is already finished.
public type TaskRequest record {|
    string taskId?;
    string description;
    boolean completed = false;
|};

# Payload for `POST /assets/{assetTag}/workorders`.
#
# + orderId - Optional client supplied id; generated by the server if absent.
# + status - Initial life-cycle state, defaults to OPEN.
# + description - Summary of the fault (required, must not be blank).
# + tasks - Initial list of sub-tasks.
public type WorkOrderRequest record {|
    string orderId?;
    WorkOrderStatus status = OPEN;
    string description;
    TaskRequest[] tasks = [];
|};

# Payload for `PUT /assets/{assetTag}/workorders/{orderId}`.
#
# + status - New life-cycle state.
# + description - New fault summary.
# + tasks - Wholesale replacement of the sub-task list.
public type WorkOrderUpdate record {|
    WorkOrderStatus status?;
    string description?;
    TaskRequest[] tasks?;
|};

# Payload for `POST /assets/{assetTag}/loan`.
#
# + borrower - Staff / student number or full name of the borrower.
# + dueDate - Optional ISO-8601 return date; defaults to 14 days from today.
# + spaceBooking - When `true` the asset is a room or lab, so the resulting
#                  status is OCCUPIED instead of LOANED_OUT.
public type LoanRequest record {|
    string borrower;
    string dueDate?;
    boolean spaceBooking = false;
|};

# Payload for `POST /assets/{assetTag}/return`.
#
# Both fields carry defaults so a client may simply send `{}`.
#
# + notes - Optional condition notes recorded on hand-back.
# + sendForMaintenance - When `true` the asset moves to UNDER_MAINTENANCE
#                        instead of AVAILABLE (e.g. it came back damaged).
public type ReturnRequest record {|
    string notes = "";
    boolean sendForMaintenance = false;
|};

# Payload for `POST /institutions`.
#
# + name - The institution's full registered name; must be unique.
# + description - Optional free text, for example the institution's abbreviation.
public type InstitutionRequest record {|
    string name;
    string description = "";
|};

# One overdue schedule entry, flattened together with its parent asset so the
# overdue dashboard can be rendered without any further lookups.
#
# + assetTag - Tag of the asset the schedule belongs to.
# + assetName - Name of the asset, for display purposes.
# + institution - Owning institution.
# + site - Campus / site of the asset.
# + status - Current status of the asset.
# + scheduleId - Id of the overdue schedule entry.
# + scheduleType - Category of the overdue schedule entry.
# + dueDate - The date that has already passed.
# + description - Description of the outstanding work.
# + daysOverdue - Whole days between `dueDate` and today.
public type OverdueSchedule record {|
    string assetTag;
    string assetName;
    string institution;
    string site;
    AssetStatus status;
    string scheduleId;
    ScheduleType scheduleType;
    string dueDate;
    string description;
    int daysOverdue;
|};

# A short confirmation returned by DELETE endpoints and other operations that
# have no meaningful body to send back.
#
# + message - Human readable summary of what happened.
# + assetTag - The asset the operation applied to.
# + resourceId - The id of the nested resource that was affected, if any.
public type OperationResult record {|
    string message;
    string assetTag;
    string resourceId = "";
|};

# The single, uniform error envelope used by every failing endpoint.
#
# + timestamp - RFC-3339 instant at which the failure was produced.
# + status - The HTTP status code that accompanies this body.
# + 'error - Short machine friendly error code, e.g. "NOT_FOUND".
# + message - Human readable explanation aimed at the API consumer.
# + path - The request path that produced the failure.
public type ErrorDetail record {|
    string timestamp;
    int status;
    string 'error;
    string message;
    string path;
|};

# 201 Created - returned when a new asset has been stored.
#
# + body - The asset exactly as it was persisted.
public type AssetCreatedResponse record {|
    *http:Created;
    Asset body;
|};

# 201 Created - returned when a new institution has been registered.
#
# + body - The institution exactly as it was persisted.
public type InstitutionCreatedResponse record {|
    *http:Created;
    Institution body;
|};

# 400 Bad Request - the payload or a path/query parameter was invalid.
#
# + body - The uniform error envelope.
public type BadRequestResponse record {|
    *http:BadRequest;
    ErrorDetail body;
|};

# 404 Not Found - the addressed asset or nested resource does not exist.
#
# + body - The uniform error envelope.
public type NotFoundResponse record {|
    *http:NotFound;
    ErrorDetail body;
|};

# 409 Conflict - the request clashes with the current state (duplicate key,
# asset already on loan, and so on).
#
# + body - The uniform error envelope.
public type ConflictResponse record {|
    *http:Conflict;
    ErrorDetail body;
|};

# 500 Internal Server Error - an unexpected failure escaped the service layer.
#
# + body - The uniform error envelope.
public type InternalErrorResponse record {|
    *http:InternalServerError;
    ErrorDetail body;
|};

# Convenience union listing every error response the API can produce.
# Used as the failure half of every resource function's return type.
public type ApiError BadRequestResponse|NotFoundResponse|ConflictResponse|InternalErrorResponse;
