// ============================================================================
//  DSA612S - Assignment 1 - Question 1
//  Distributed Library and Resource Management System
//  ---------------------------------------------------------------------------
//  util.bal
//  ---------------------------------------------------------------------------
//  Cross-cutting helpers shared by every other layer:
//
//    * The application's distinct error hierarchy.
//    * Calendar arithmetic on ISO-8601 (YYYY-MM-DD) dates.
//    * Identifier generation for nested resources.
//    * Input validation primitives.
//    * Translation of a domain error into the correct typed HTTP response.
//
//  Every function here is `isolated`: it touches no mutable module state
//  except through an explicit `lock`, which lets the Ballerina compiler prove
//  the whole service is safe to run concurrently.
// ============================================================================

import ballerina/time;

// ============================================================================
//  SECTION 1 - ERROR HIERARCHY
// ============================================================================
//  Distinct error types let the transport layer map a failure onto the right
//  HTTP status code by *type* rather than by inspecting message strings.

# Raised when a client supplies syntactically or semantically invalid input.
# Mapped to HTTP 400 Bad Request.
public type ValidationError distinct error;

# Raised when the addressed asset, component, schedule or work order does not
# exist. Mapped to HTTP 404 Not Found.
public type NotFoundError distinct error;

# Raised when a request clashes with the current state of the system, such as
# creating a duplicate `assetTag` or loaning an asset that is already out.
# Mapped to HTTP 409 Conflict.
public type ConflictError distinct error;

# Raised when an unexpected failure occurs inside the service.
# Mapped to HTTP 500 Internal Server Error.
public type InternalError distinct error;

# Union of everything the service layer is allowed to fail with.
public type AppError ValidationError|NotFoundError|ConflictError|InternalError;

// ============================================================================
//  SECTION 2 - IDENTIFIER GENERATION
// ============================================================================

# Monotonically increasing counter behind every generated identifier.
# Declared `isolated` so it can only ever be touched inside a `lock` block.
isolated int idSequence = 1000;

# Atomically returns the next value of the global sequence.
#
# + return - A number that is unique for the lifetime of the server process.
isolated function nextSequence() returns int {
    lock {
        idSequence += 1;
        return idSequence;
    }
}

# Builds a readable, collision free identifier for a nested resource.
#
# + prefix - Short token describing the resource kind, e.g. "WO" or "SCH".
# + return - An identifier such as `WO-1001`.
public isolated function generateId(string prefix) returns string {
    return string `${prefix}-${nextSequence()}`;
}

// ============================================================================
//  SECTION 3 - CALENDAR HELPERS
// ============================================================================

# Left pads a number below ten with a single zero, e.g. `7` becomes `"07"`.
#
# + value - The number to render.
# + return - A two character string.
isolated function pad2(int value) returns string {
    return value < 10 ? string `0${value}` : value.toString();
}

# Returns the number of days in the given month, honouring leap years.
#
# + year - Four digit calendar year.
# + month - Month number in the range 1..12.
# + return - The number of days in that month.
isolated function daysInMonth(int year, int month) returns int {
    match month {
        1|3|5|7|8|10|12 => {
            return 31;
        }
        4|6|9|11 => {
            return 30;
        }
    }
    // February: leap years are divisible by 4, except centuries that are not
    // divisible by 400.
    boolean isLeap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    return isLeap ? 29 : 28;
}

# Parses a strict ISO-8601 calendar date (`YYYY-MM-DD`) into a UTC instant
# fixed at midnight, so that two dates can be compared and subtracted.
#
# + value - The candidate date string.
# + fieldName - Name of the field being parsed, used in the error message.
# + return - The instant at midnight UTC, or a `ValidationError`.
public isolated function parseDate(string value, string fieldName = "date") returns time:Utc|ValidationError {
    string raw = value.trim();

    // Shape check first: exactly 10 characters laid out as ####-##-##.
    if raw.length() != 10 || raw.substring(4, 5) != "-" || raw.substring(7, 8) != "-" {
        return error ValidationError(
            string `Field '${fieldName}' must be an ISO-8601 date in the form YYYY-MM-DD, received '${value}'.`);
    }

    int|error year = int:fromString(raw.substring(0, 4));
    int|error month = int:fromString(raw.substring(5, 7));
    int|error day = int:fromString(raw.substring(8, 10));

    if year is error || month is error || day is error {
        return error ValidationError(
            string `Field '${fieldName}' contains non numeric characters: '${value}'.`);
    }

    // Range checks - these catch nonsense such as 2026-13-40.
    if year < 1900 || year > 2200 {
        return error ValidationError(
            string `Field '${fieldName}' has an out of range year: ${year}.`);
    }
    if month < 1 || month > 12 {
        return error ValidationError(
            string `Field '${fieldName}' has an invalid month: ${month}.`);
    }
    if day < 1 || day > daysInMonth(year, month) {
        return error ValidationError(
            string `Field '${fieldName}' has an invalid day for that month: ${day}.`);
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

    time:Utc|time:Error utc = time:utcFromCivil(civil);
    if utc is time:Error {
        return error ValidationError(
            string `Field '${fieldName}' could not be converted to an instant: ${utc.message()}`);
    }
    return utc;
}

# Renders a UTC instant back into an ISO-8601 calendar date.
#
# + instant - The instant to render.
# + return - A date string in the form `YYYY-MM-DD`.
public isolated function formatDate(time:Utc instant) returns string {
    time:Civil civil = time:utcToCivil(instant);
    return string `${civil.year}-${pad2(civil.month)}-${pad2(civil.day)}`;
}

# Today's date according to the server clock.
#
# + return - A date string in the form `YYYY-MM-DD`.
public isolated function today() returns string {
    return formatDate(time:utcNow());
}

# An RFC-3339 style timestamp used to stamp every error envelope.
#
# + return - A timestamp such as `2026-08-05T14:32:07Z`.
public isolated function currentTimestamp() returns string {
    time:Civil civil = time:utcToCivil(time:utcNow());
    decimal seconds = civil.second ?: 0d;
    int wholeSeconds = <int>seconds.floor();
    return string `${civil.year}-${pad2(civil.month)}-${pad2(civil.day)}` +
        string `T${pad2(civil.hour)}:${pad2(civil.minute)}:${pad2(wholeSeconds)}Z`;
}

# Adds a whole number of days to an ISO-8601 date.
#
# + isoDate - The starting date, in the form `YYYY-MM-DD`.
# + days - The number of days to add; may be negative.
# + return - The shifted date, or a `ValidationError` if `isoDate` is malformed.
public isolated function addDays(string isoDate, int days) returns string|ValidationError {
    time:Utc instant = check parseDate(isoDate);
    time:Utc shifted = time:utcAddSeconds(instant, <decimal>days * 86400d);
    return formatDate(shifted);
}

# Whole days between two ISO-8601 dates (`later - earlier`).
#
# + earlier - The earlier date.
# + later - The later date.
# + return - A positive number when `later` is after `earlier`, or a
#            `ValidationError` when either input is malformed.
public isolated function daysBetween(string earlier, string later) returns int|ValidationError {
    time:Utc a = check parseDate(earlier);
    time:Utc b = check parseDate(later);
    decimal diffSeconds = time:utcDiffSeconds(b, a);
    return <int>(diffSeconds / 86400d);
}

# Tests whether a due date lies strictly in the past relative to today.
#
# Because both operands are zero padded ISO-8601 dates, a plain lexicographic
# comparison is equivalent to a calendar comparison, which keeps this check
# cheap enough to run over every schedule of every asset.
#
# + dueDate - The date to test.
# + return - `true` when the date has already passed.
public isolated function isOverdue(string dueDate) returns boolean {
    return dueDate.trim() < today();
}

// ============================================================================
//  SECTION 4 - VALIDATION PRIMITIVES
// ============================================================================

# Rejects empty or whitespace-only strings.
#
# + value - The value under test.
# + fieldName - Name of the field, used to build a helpful message.
# + return - A `ValidationError` when blank, otherwise `()`.
public isolated function requireNonBlank(string value, string fieldName) returns ValidationError? {
    if value.trim().length() == 0 {
        return error ValidationError(string `Field '${fieldName}' is required and must not be blank.`);
    }
    return ();
}

# Rejects strings longer than the given limit, protecting the in-memory store
# from unbounded payloads.
#
# + value - The value under test.
# + fieldName - Name of the field, used to build a helpful message.
# + maxLength - The inclusive upper bound on length.
# + return - A `ValidationError` when too long, otherwise `()`.
public isolated function requireMaxLength(string value, string fieldName, int maxLength) returns ValidationError? {
    if value.length() > maxLength {
        return error ValidationError(
            string `Field '${fieldName}' must not exceed ${maxLength} characters.`);
    }
    return ();
}

# Runs the full validation suite over an asset that is about to be stored.
#
# + asset - The candidate asset.
# + return - The first `ValidationError` encountered, otherwise `()`.
public isolated function validateAsset(Asset asset) returns ValidationError? {
    check requireNonBlank(asset.assetTag, "assetTag");
    check requireMaxLength(asset.assetTag, "assetTag", 64);
    check requireNonBlank(asset.name, "name");
    check requireMaxLength(asset.name, "name", 200);
    check requireNonBlank(asset.institution, "institution");
    check requireNonBlank(asset.site, "site");

    // `dateAcquired` must be a real calendar date and cannot be in the future.
    _ = check parseDate(asset.dateAcquired, "dateAcquired");
    if asset.dateAcquired.trim() > today() {
        return error ValidationError(
            string `Field 'dateAcquired' cannot be in the future: '${asset.dateAcquired}'.`);
    }

    // Nested collections must not contain duplicate identifiers.
    check requireUniqueIds(from Component c in asset.components
        select c.compId, "components", "compId");
    check requireUniqueIds(from Schedule s in asset.schedules
        select s.scheduleId, "schedules", "scheduleId");
    check requireUniqueIds(from WorkOrder w in asset.workOrders
        select w.orderId, "workOrders", "orderId");

    // Every schedule date has to parse, otherwise the overdue report breaks.
    foreach Schedule s in asset.schedules {
        check requireNonBlank(s.scheduleId, "schedules[].scheduleId");
        _ = check parseDate(s.dueDate, string `schedules[${s.scheduleId}].dueDate`);
    }
    foreach Component c in asset.components {
        check requireNonBlank(c.compId, "components[].compId");
        check requireNonBlank(c.name, string `components[${c.compId}].name`);
    }
    foreach WorkOrder w in asset.workOrders {
        check requireNonBlank(w.orderId, "workOrders[].orderId");
        check requireNonBlank(w.description, string `workOrders[${w.orderId}].description`);
        check requireUniqueIds(from Task t in w.tasks
            select t.taskId, string `workOrders[${w.orderId}].tasks`, "taskId");
    }
    return ();
}

# Fails when the supplied list of identifiers contains a duplicate.
#
# + ids - The identifiers to inspect.
# + collectionName - Name of the collection, used in the error message.
# + idFieldName - Name of the identifier field, used in the error message.
# + return - A `ValidationError` on the first duplicate, otherwise `()`.
public isolated function requireUniqueIds(string[] ids, string collectionName, string idFieldName)
        returns ValidationError? {
    map<boolean> seen = {};
    foreach string id in ids {
        if seen.hasKey(id) {
            return error ValidationError(
                string `Duplicate ${idFieldName} '${id}' in '${collectionName}'.`);
        }
        seen[id] = true;
    }
    return ();
}

// ============================================================================
//  SECTION 5 - ERROR TRANSLATION
// ============================================================================

# Builds the uniform error envelope shared by every failing endpoint.
#
# + status - HTTP status code that will accompany the body.
# + code - Short machine friendly error code.
# + message - Human readable explanation.
# + path - Request path that produced the failure.
# + return - A populated `ErrorDetail`.
isolated function buildErrorDetail(int status, string code, string message, string path)
        returns ErrorDetail {
    return {
        timestamp: currentTimestamp(),
        status: status,
        'error: code,
        message: message,
        path: path
    };
}

# Maps a domain error onto the typed HTTP response that represents it.
#
# This single function is the reason the resource functions in `main.bal` stay
# almost free of error handling noise: they simply forward whatever the
# service layer failed with.
#
# + e - The error raised by the service layer.
# + path - The request path, echoed back in the envelope for traceability.
# + return - A `BadRequestResponse`, `NotFoundResponse`, `ConflictResponse` or
#            `InternalErrorResponse` depending on the error's type.
public isolated function toErrorResponse(error e, string path) returns ApiError {
    if e is ValidationError {
        BadRequestResponse response = {
            body: buildErrorDetail(400, "BAD_REQUEST", e.message(), path)
        };
        return response;
    }
    if e is NotFoundError {
        NotFoundResponse response = {
            body: buildErrorDetail(404, "NOT_FOUND", e.message(), path)
        };
        return response;
    }
    if e is ConflictError {
        ConflictResponse response = {
            body: buildErrorDetail(409, "CONFLICT", e.message(), path)
        };
        return response;
    }
    // Anything that is not part of the domain hierarchy is, by definition,
    // an unexpected server side failure.
    InternalErrorResponse response = {
        body: buildErrorDetail(500, "INTERNAL_SERVER_ERROR", e.message(), path)
    };
    return response;
}
