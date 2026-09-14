import ballerina/http;

public enum AssetStatus {
    AVAILABLE = "AVAILABLE",
    LOANED_OUT = "LOANED_OUT",
    OCCUPIED = "OCCUPIED",
    UNDER_MAINTENANCE = "UNDER_MAINTENANCE",
    DISPOSED = "DISPOSED"
}

public enum ScheduleType {
    MAINTENANCE = "MAINTENANCE",
    SERVICING = "SERVICING",
    INSPECTION = "INSPECTION",
    BOOKING = "BOOKING"
}

public enum WorkOrderStatus {
    OPEN = "OPEN",
    IN_PROGRESS = "IN_PROGRESS",
    CLOSED = "CLOSED",
    CANCELLED = "CANCELLED"
}

public type Component record {|
    string compId;
    string name;
    string description = "";
|};

public type Schedule record {|
    string scheduleId;
    ScheduleType 'type = MAINTENANCE;
    string dueDate;
    string description = "";
|};

public type Task record {|
    string taskId;
    string description;
    boolean completed = false;
|};

public type WorkOrder record {|
    string orderId;
    WorkOrderStatus status = OPEN;
    string description;
    Task[] tasks = [];
|};

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

public type LoanRecord record {|
    readonly string loanId;
    string assetTag;
    string borrower;
    string loanedOn;
    string dueDate;
    string? returnedOn = ();
    boolean active = true;
|};

public type Institution record {|
    readonly string name;
    string description = "";
    string registeredOn;
|};

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

public type ComponentRequest record {|
    string compId?;
    string name;
    string description = "";
|};

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

public type TaskRequest record {|
    string taskId?;
    string description;
    boolean completed = false;
|};

public type WorkOrderRequest record {|
    string orderId?;
    WorkOrderStatus status = OPEN;
    string description;
    TaskRequest[] tasks = [];
|};

public type WorkOrderUpdate record {|
    WorkOrderStatus status?;
    string description?;
    TaskRequest[] tasks?;
|};

public type LoanRequest record {|
    string borrower;
    string dueDate?;
    boolean spaceBooking = false;
|};

public type ReturnRequest record {|
    string notes = "";
    boolean sendForMaintenance = false;
|};

public type InstitutionRequest record {|
    string name;
    string description = "";
|};

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

public type OperationResult record {|
    string message;
    string assetTag;
    string resourceId = "";
|};

public type ErrorDetail record {|
    string timestamp;
    int status;
    string 'error;
    string message;
    string path;
|};

public type AssetCreatedResponse record {|
    *http:Created;
    Asset body;
|};

public type InstitutionCreatedResponse record {|
    *http:Created;
    Institution body;
|};

public type BadRequestResponse record {|
    *http:BadRequest;
    ErrorDetail body;
|};

public type NotFoundResponse record {|
    *http:NotFound;
    ErrorDetail body;
|};

public type ConflictResponse record {|
    *http:Conflict;
    ErrorDetail body;
|};

public type InternalErrorResponse record {|
    *http:InternalServerError;
    ErrorDetail body;
|};

public type ApiError BadRequestResponse|NotFoundResponse|ConflictResponse|InternalErrorResponse;
