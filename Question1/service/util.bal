import ballerina/time;

public type ValidationError distinct error;

public type NotFoundError distinct error;

public type ConflictError distinct error;

public type InternalError distinct error;

public type AppError ValidationError|NotFoundError|ConflictError|InternalError;

isolated int idSequence = 1000;

isolated function nextSequence() returns int {
    lock {
        idSequence += 1;
        return idSequence;
    }
}

public isolated function generateId(string prefix) returns string {
    return string `${prefix}-${nextSequence()}`;
}

isolated function pad2(int value) returns string {
    return value < 10 ? string `0${value}` : value.toString();
}

isolated function daysInMonth(int year, int month) returns int {
    match month {
        1|3|5|7|8|10|12 => {
            return 31;
        }
        4|6|9|11 => {
            return 30;
        }
    }
    boolean isLeap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    return isLeap ? 29 : 28;
}

public isolated function parseDate(string value, string fieldName = "date") returns time:Utc|ValidationError {
    string raw = value.trim();
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

public isolated function formatDate(time:Utc instant) returns string {
    time:Civil civil = time:utcToCivil(instant);
    return string `${civil.year}-${pad2(civil.month)}-${pad2(civil.day)}`;
}

public isolated function today() returns string {
    return formatDate(time:utcNow());
}

public isolated function currentTimestamp() returns string {
    time:Civil civil = time:utcToCivil(time:utcNow());
    decimal seconds = civil.second ?: 0d;
    int wholeSeconds = <int>seconds.floor();
    return string `${civil.year}-${pad2(civil.month)}-${pad2(civil.day)}` +
        string `T${pad2(civil.hour)}:${pad2(civil.minute)}:${pad2(wholeSeconds)}Z`;
}

public isolated function addDays(string isoDate, int days) returns string|ValidationError {
    time:Utc instant = check parseDate(isoDate);
    time:Utc shifted = time:utcAddSeconds(instant, <decimal>days * 86400d);
    return formatDate(shifted);
}

public isolated function daysBetween(string earlier, string later) returns int|ValidationError {
    time:Utc a = check parseDate(earlier);
    time:Utc b = check parseDate(later);
    decimal diffSeconds = time:utcDiffSeconds(b, a);
    return <int>(diffSeconds / 86400d);
}

public isolated function isOverdue(string dueDate) returns boolean {
    return dueDate.trim() < today();
}

public isolated function requireNonBlank(string value, string fieldName) returns ValidationError? {
    if value.trim().length() == 0 {
        return error ValidationError(string `Field '${fieldName}' is required and must not be blank.`);
    }
    return ();
}

public isolated function requireMaxLength(string value, string fieldName, int maxLength) returns ValidationError? {
    if value.length() > maxLength {
        return error ValidationError(
            string `Field '${fieldName}' must not exceed ${maxLength} characters.`);
    }
    return ();
}

public isolated function validateAsset(Asset asset) returns ValidationError? {
    check requireNonBlank(asset.assetTag, "assetTag");
    check requireMaxLength(asset.assetTag, "assetTag", 64);
    check requireNonBlank(asset.name, "name");
    check requireMaxLength(asset.name, "name", 200);
    check requireNonBlank(asset.institution, "institution");
    check requireNonBlank(asset.site, "site");
    _ = check parseDate(asset.dateAcquired, "dateAcquired");
    if asset.dateAcquired.trim() > today() {
        return error ValidationError(
            string `Field 'dateAcquired' cannot be in the future: '${asset.dateAcquired}'.`);
    }
    check requireUniqueIds(from Component c in asset.components
        select c.compId, "components", "compId");
    check requireUniqueIds(from Schedule s in asset.schedules
        select s.scheduleId, "schedules", "scheduleId");
    check requireUniqueIds(from WorkOrder w in asset.workOrders
        select w.orderId, "workOrders", "orderId");
    map<boolean> bookingDates = {};
    foreach Schedule s in asset.schedules {
        check requireNonBlank(s.scheduleId, "schedules[].scheduleId");
        _ = check parseDate(s.dueDate, string `schedules[${s.scheduleId}].dueDate`);
        check requireMaxLength(s.description, "schedules[].description", 500);
        if s.'type == BOOKING {
            string date = s.dueDate.trim();
            if bookingDates.hasKey(date) {
                return error ValidationError(string `Asset '${asset.assetTag}' has duplicate bookings on ${date}.`);
            }
            bookingDates[date] = true;
        }
    }
    foreach Component c in asset.components {
        check requireNonBlank(c.compId, "components[].compId");
        check requireNonBlank(c.name, string `components[${c.compId}].name`);
        check requireMaxLength(c.name, "components[].name", 200);
        check requireMaxLength(c.description, "components[].description", 500);
    }
    foreach WorkOrder w in asset.workOrders {
        check requireNonBlank(w.orderId, "workOrders[].orderId");
        check requireNonBlank(w.description, string `workOrders[${w.orderId}].description`);
        check requireMaxLength(w.description, "workOrders[].description", 500);
        check requireUniqueIds(from Task t in w.tasks
            select t.taskId, string `workOrders[${w.orderId}].tasks`, "taskId");
        foreach Task task in w.tasks {
            check requireNonBlank(task.description, "tasks[].description");
            check requireMaxLength(task.description, "tasks[].description", 500);
        }
    }
    return ();
}

public isolated function requireUniqueIds(string[] ids, string collectionName, string idFieldName)
        returns ValidationError? {
    map<boolean> seen = {};
    foreach string id in ids {
        check requireNonBlank(id, idFieldName);
        if id != id.trim() {
            return error ValidationError(string `Field '${idFieldName}' must not contain surrounding whitespace.`);
        }
        if seen.hasKey(id) {
            return error ValidationError(
                string `Duplicate ${idFieldName} '${id}' in '${collectionName}'.`);
        }
        seen[id] = true;
    }
    return ();
}

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
    InternalErrorResponse response = {
        body: buildErrorDetail(500, "INTERNAL_SERVER_ERROR", e.message(), path)
    };
    return response;
}
