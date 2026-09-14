'use strict';

function resolveApiBase() {
    const queryBase = new URLSearchParams(window.location.search).get('apiBase');
    for (const candidate of [queryBase, localStorage.getItem('dsa.apiBase')]) {
        if (!candidate) continue;
        try {
            const url = new URL(candidate);
            if (['http:', 'https:'].includes(url.protocol) && !url.username && !url.password) {
                return url.origin + url.pathname.replace(/\/+$/, '');
            }
        } catch (_) {
            // Ignore an invalid override and use the next configured URL.
        }
    }
    return 'http://localhost:8080';
}

const API_BASE = resolveApiBase();

// Everything the UI needs to render, kept in one place.
const state = {
    assets: [],
    overdue: [],
    loans: [],
    institutions: [],
    sites: [],
    summary: {},
    filters: {q: '', institution: '', site: '', status: ''},
    sort: {key: 'assetTag', dir: 'asc'},
    online: null
};

// Human readable labels for the status enum.
const STATUS_LABEL = {
    AVAILABLE: 'Available',
    LOANED_OUT: 'Loaned out',
    OCCUPIED: 'Occupied',
    UNDER_MAINTENANCE: 'Maintenance',
    DISPOSED: 'Disposed'
};

const $ = (selector, scope = document) => scope.querySelector(selector);
const $$ = (selector, scope = document) => Array.from(scope.querySelectorAll(selector));

// Escape values before inserting them into HTML templates.
function esc(value) {
    if (value === null || value === undefined) {
        return '';
    }
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

// Builds a coloured status pill.
function pill(value, label) {
    const key = String(value || '').toLowerCase();
    const text = label || STATUS_LABEL[value] || value || '-';
    return `<span class="pill pill--${esc(key)}">${esc(text)}</span>`;
}

// Debounces a function so typing in the search box does not spam the DOM.
function debounce(fn, wait) {
    let timer = null;
    return (...args) => {
        clearTimeout(timer);
        timer = setTimeout(() => fn(...args), wait);
    };
}

// Today's date as YYYY-MM-DD, for date input defaults and minimums.
function todayIso() {
    const now = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

// Adds whole days to an ISO date string.
function addDaysIso(iso, days) {
    const date = new Date(`${iso}T00:00:00Z`);
    date.setUTCDate(date.getUTCDate() + days);
    return date.toISOString().slice(0, 10);
}

// Shows a transient notification in the bottom right corner.
function toast(title, text = '', kind = 'info') {
    const host = $('#toasts');
    const el = document.createElement('div');
    el.className = `toast toast--${kind}`;
    el.innerHTML = `
        <div class="toast__body">
            <div class="toast__title">${esc(title)}</div>
            ${text ? `<div class="toast__text">${esc(text)}</div>` : ''}
        </div>`;
    host.appendChild(el);

    const life = kind === 'error' ? 7000 : 3800;
    setTimeout(() => {
        el.classList.add('is-leaving');
        setTimeout(() => el.remove(), 220);
    }, life);
}

// Applies a theme and remembers the choice.
function applyTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('dsa.theme', theme);
}

// Restores the saved theme, falling back to the operating system setting.
function initTheme() {
    const saved = localStorage.getItem('dsa.theme');
    if (saved === 'dark' || saved === 'light') {
        applyTheme(saved);
        return;
    }
    const prefersDark = window.matchMedia &&
        window.matchMedia('(prefers-color-scheme: dark)').matches;
    applyTheme(prefersDark ? 'dark' : 'light');
}

// Performs one API call and normalises failures.
async function api(path, options = {}) {
    const config = {
        method: options.method || 'GET',
        headers: {'Accept': 'application/json'}
    };

    if (options.body !== undefined) {
        config.headers['Content-Type'] = 'application/json';
        config.body = JSON.stringify(options.body);
    }

    let response;
    try {
        response = await fetch(API_BASE + path, config);
    } catch (networkError) {
        setConnection(false);
        throw new Error(
            `Cannot reach the API at ${API_BASE}. Is the Ballerina service running?`);
    }

    setConnection(true);

    const text = await response.text();
    let payload = null;
    if (text) {
        try {
            payload = JSON.parse(text);
        } catch (parseError) {
            payload = null;
        }
    }

    if (!response.ok) {
        const message = payload && payload.message
            ? payload.message
            : `The server returned HTTP ${response.status}.`;
        const error = new Error(message);
        error.status = response.status;
        throw error;
    }
    return payload;
}

// Percent-encodes a value for use inside a URI path segment.
const seg = (value) => encodeURIComponent(String(value));

// Updates the connection pill in the app bar.
function setConnection(online) {
    if (state.online === online) {
        return;
    }
    state.online = online;
    const box = $('#connStatus');
    box.classList.toggle('is-online', online);
    box.classList.toggle('is-offline', !online);
    $('#connText').textContent = online ? 'API online' : 'API offline';
}

// Loads every data set the dashboard needs and repaints the whole page.
async function loadAll() {
    try {
        const [assets, overdue, loans, institutions, sites, summary] = await Promise.all([
            api('/assets'),
            api('/maintenance/overdue'),
            api('/loans'),
            api('/institutions'),
            api('/sites'),
            api('/summary')
        ]);

        state.assets = assets || [];
        state.overdue = overdue || [];
        state.loans = loans || [];
        state.institutions = institutions || [];
        state.sites = sites || [];
        state.summary = summary || {};

        renderFilters();
        renderTiles();
        renderAssets();
        renderOverdue();
        renderWorkOrders();
        renderLoans();
        return true;
    } catch (error) {
        toast('Could not load data', error.message, 'error');
        return false;
    }
}

// Repaints the five summary tiles.
function renderTiles() {
    const byStatus = state.summary.byStatus || {};
    const out = (byStatus.LOANED_OUT || 0) + (byStatus.OCCUPIED || 0);

    $('#statTotal').textContent = state.summary.totalAssets ?? state.assets.length;
    $('#statAvailable').textContent = byStatus.AVAILABLE || 0;
    $('#statOut').textContent = out;
    $('#statMaintenance').textContent = byStatus.UNDER_MAINTENANCE || 0;
    $('#statOverdue').textContent = state.overdue.length;

    $('#statInstitutions').textContent =
        `across ${state.institutions.length} institution${state.institutions.length === 1 ? '' : 's'}`;
    $('#statLoans').textContent =
        `${state.summary.activeLoans || 0} active loan${state.summary.activeLoans === 1 ? '' : 's'}`;

    const badge = $('#overdueBadge');
    badge.textContent = String(state.overdue.length);
    badge.dataset.zero = state.overdue.length === 0 ? 'true' : 'false';
}

// Rebuilds the institution and site dropdowns, preserving the selection.
function renderFilters() {
    const fillSelect = (select, values, placeholder) => {
        const current = select.value;
        select.innerHTML = `<option value="">${esc(placeholder)}</option>` +
            values.map((v) => `<option value="${esc(v)}">${esc(v)}</option>`).join('');
        if (values.includes(current)) {
            select.value = current;
        }
    };
    fillSelect($('#filterInstitution'), state.institutions, 'All institutions');
    fillSelect($('#filterSite'), state.sites, 'All campuses / sites');
    state.filters.institution = $('#filterInstitution').value;
    state.filters.site = $('#filterSite').value;
}

// Applies the current filters and sort order to the asset list.
function visibleAssets() {
    const {q, institution, site, status} = state.filters;
    const needle = q.trim().toLowerCase();

    let rows = state.assets.filter((a) => {
        if (institution && a.institution !== institution) return false;
        if (site && a.site !== site) return false;
        if (status && a.status !== status) return false;
        if (!needle) return true;
        const haystack = [a.assetTag, a.name, a.description, a.institution, a.site]
            .join(' ').toLowerCase();
        return haystack.includes(needle);
    });

    const {key, dir} = state.sort;
    rows = rows.slice().sort((x, y) => {
        const left = String(x[key] ?? '').toLowerCase();
        const right = String(y[key] ?? '').toLowerCase();
        if (left < right) return dir === 'asc' ? -1 : 1;
        if (left > right) return dir === 'asc' ? 1 : -1;
        return 0;
    });
    return rows;
}

// Repaints the main asset table.
function renderAssets() {
    const rows = visibleAssets();
    const body = $('#assetTableBody');

    body.innerHTML = rows.map((a) => {
        const canLoan = a.status === 'AVAILABLE';
        const canReturn = a.status === 'LOANED_OUT' || a.status === 'OCCUPIED';
        return `
        <tr>
            <td><span class="cell-tag" data-detail="${esc(a.assetTag)}">${esc(a.assetTag)}</span></td>
            <td class="cell-strong">${esc(a.name)}</td>
            <td class="cell-muted">${esc(a.institution)}</td>
            <td class="cell-muted">${esc(a.site)}</td>
            <td>${pill(a.status)}</td>
            <td class="col-num">${(a.schedules || []).length}</td>
            <td class="col-num">${(a.workOrders || []).length}</td>
            <td class="col-actions">
                <span class="row-actions">
                    <button class="btn btn--sm btn--ghost" data-detail="${esc(a.assetTag)}">View</button>
                    <button class="btn btn--sm" data-loan="${esc(a.assetTag)}" ${canLoan ? '' : 'disabled'}>Loan</button>
                    <button class="btn btn--sm" data-return="${esc(a.assetTag)}" ${canReturn ? '' : 'disabled'}>Return</button>
                    <button class="btn btn--sm" data-schedule="${esc(a.assetTag)}">Schedule</button>
                    <button class="btn btn--sm" data-workorder="${esc(a.assetTag)}">W/O</button>
                    <button class="btn btn--sm btn--ghost" data-delete="${esc(a.assetTag)}">Delete</button>
                </span>
            </td>
        </tr>`;
    }).join('');

    $('#assetEmpty').hidden = rows.length > 0;
    $('#assetCount').textContent =
        `${rows.length} of ${state.assets.length} asset${state.assets.length === 1 ? '' : 's'}`;
    $$('#assetTable th.sortable').forEach((th) => {
        th.classList.remove('sort-asc', 'sort-desc');
        if (th.dataset.sort === state.sort.key) {
            th.classList.add(state.sort.dir === 'asc' ? 'sort-asc' : 'sort-desc');
        }
    });
}

// Repaints the overdue maintenance table.
function renderOverdue() {
    const body = $('#overdueTableBody');
    body.innerHTML = state.overdue.map((row) => `
        <tr>
            <td><span class="cell-tag" data-detail="${esc(row.assetTag)}">${esc(row.assetTag)}</span></td>
            <td class="cell-strong">${esc(row.assetName)}</td>
            <td class="cell-muted">${esc(row.scheduleId)}</td>
            <td>${pill(row.scheduleType, row.scheduleType)}</td>
            <td class="cell-muted">${esc(row.dueDate)}</td>
            <td class="col-num"><span class="days-late">${esc(row.daysOverdue)}</span></td>
            <td class="cell-muted">${esc(row.institution)}</td>
            <td class="col-actions">
                <span class="row-actions">
                    <button class="btn btn--sm" data-workorder="${esc(row.assetTag)}">Raise W/O</button>
                    <button class="btn btn--sm" data-edit-schedule="${esc(row.assetTag)}"
                            data-schedule-id="${esc(row.scheduleId)}">Edit</button>
                    <button class="btn btn--sm btn--ghost"
                            data-del-schedule="${esc(row.assetTag)}"
                            data-schedule-id="${esc(row.scheduleId)}">Clear</button>
                </span>
            </td>
        </tr>`).join('');

    $('#overdueEmpty').hidden = state.overdue.length > 0;
}

// Flattens every work order of every asset into one table.
function renderWorkOrders() {
    const rows = [];
    state.assets.forEach((a) => {
        (a.workOrders || []).forEach((w) => rows.push({asset: a, order: w}));
    });

    const body = $('#workOrderTableBody');
    body.innerHTML = rows.map(({asset, order}) => {
        const done = (order.tasks || []).filter((t) => t.completed).length;
        const total = (order.tasks || []).length;
        const closed = order.status === 'CLOSED' || order.status === 'CANCELLED';
        return `
        <tr>
            <td class="cell-tag">${esc(order.orderId)}</td>
            <td><span class="cell-tag" data-detail="${esc(asset.assetTag)}">${esc(asset.assetTag)}</span></td>
            <td class="cell-strong">${esc(asset.name)}</td>
            <td>${pill(order.status, order.status)}</td>
            <td class="cell-muted"><span class="cell-clip">${esc(order.description)}</span></td>
            <td class="col-num">${done} / ${total}</td>
            <td class="col-actions">
                <span class="row-actions">
                    <button class="btn btn--sm" data-close-wo="${esc(asset.assetTag)}"
                            data-order-id="${esc(order.orderId)}" ${closed ? 'disabled' : ''}>Close</button>
                    <button class="btn btn--sm btn--ghost" data-del-wo="${esc(asset.assetTag)}"
                            data-order-id="${esc(order.orderId)}">Delete</button>
                </span>
            </td>
        </tr>`;
    }).join('');

    $('#workOrderEmpty').hidden = rows.length > 0;
}

// Repaints the loan history table.
function renderLoans() {
    const body = $('#loanTableBody');
    body.innerHTML = state.loans.map((l) => `
        <tr>
            <td class="cell-tag">${esc(l.loanId)}</td>
            <td><span class="cell-tag" data-detail="${esc(l.assetTag)}">${esc(l.assetTag)}</span></td>
            <td class="cell-strong">${esc(l.borrower)}</td>
            <td class="cell-muted">${esc(l.loanedOn)}</td>
            <td class="cell-muted">${esc(l.dueDate)}</td>
            <td class="cell-muted">${esc(l.returnedOn || '-')}</td>
            <td>${l.active ? pill('ACTIVE', 'On loan') : pill('RETURNED', 'Returned')}</td>
        </tr>`).join('');

    $('#loanEmpty').hidden = state.loans.length > 0;
}

// Opens the read-only detail view for one asset.
function openDetail(assetTag) {
    const asset = state.assets.find((a) => a.assetTag === assetTag);
    if (!asset) {
        toast('Asset not found', `No asset carries the tag ${assetTag}.`, 'error');
        return;
    }

    $('#detailTitle').textContent = asset.name;

    const components = asset.components || [];
    const schedules = asset.schedules || [];
    const orders = asset.workOrders || [];

    $('#detailBody').innerHTML = `
        <dl class="detail-grid">
            <div class="detail-item"><dt>Asset tag</dt><dd>${esc(asset.assetTag)}</dd></div>
            <div class="detail-item"><dt>Status</dt><dd>${pill(asset.status)}</dd></div>
            <div class="detail-item"><dt>Institution</dt><dd>${esc(asset.institution)}</dd></div>
            <div class="detail-item"><dt>Campus / site</dt><dd>${esc(asset.site)}</dd></div>
            <div class="detail-item"><dt>Date acquired</dt><dd>${esc(asset.dateAcquired)}</dd></div>
            <div class="detail-item"><dt>Description</dt><dd>${esc(asset.description || '-')}</dd></div>
        </dl>

        <section class="detail-section">
            <h3>Components (${components.length})</h3>
            <div class="detail-list">
                ${components.length === 0
                    ? '<div class="detail-empty">This asset has no registered components.</div>'
                    : components.map((c) => `
                        <div class="detail-entry">
                            <div class="detail-entry__main">
                                <div class="detail-entry__title">${esc(c.name)}</div>
                                <div class="detail-entry__meta">${esc(c.compId)} &mdash; ${esc(c.description || 'No description')}</div>
                            </div>
                            <div class="detail-entry__actions">
                                <button class="btn btn--sm btn--ghost"
                                        data-del-component="${esc(asset.assetTag)}"
                                        data-component-id="${esc(c.compId)}">Remove</button>
                            </div>
                        </div>`).join('')}
            </div>
        </section>

        <section class="detail-section">
            <h3>Schedules (${schedules.length})</h3>
            <div class="detail-list">
                ${schedules.length === 0
                    ? '<div class="detail-empty">No maintenance or booking schedule has been set.</div>'
                    : schedules.map((s) => `
                        <div class="detail-entry">
                            <div class="detail-entry__main">
                                <div class="detail-entry__title">
                                    ${pill(s.type, s.type)} ${esc(s.dueDate)}
                                </div>
                                <div class="detail-entry__meta">${esc(s.scheduleId)} &mdash; ${esc(s.description || 'No description')}</div>
                            </div>
                            <div class="detail-entry__actions">
                                <button class="btn btn--sm"
                                        data-edit-schedule="${esc(asset.assetTag)}"
                                        data-schedule-id="${esc(s.scheduleId)}">Edit</button>
                                <button class="btn btn--sm btn--ghost"
                                        data-del-schedule="${esc(asset.assetTag)}"
                                        data-schedule-id="${esc(s.scheduleId)}">Remove</button>
                            </div>
                        </div>`).join('')}
            </div>
        </section>

        <section class="detail-section">
            <h3>Work orders (${orders.length})</h3>
            <div class="detail-list">
                ${orders.length === 0
                    ? '<div class="detail-empty">No work order has been raised against this asset.</div>'
                    : orders.map((w) => `
                        <div class="detail-entry">
                            <div class="detail-entry__main">
                                <div class="detail-entry__title">
                                    ${pill(w.status, w.status)} ${esc(w.orderId)}
                                </div>
                                <div class="detail-entry__meta">${esc(w.description)}</div>
                                ${(w.tasks || []).length === 0 ? '' : `
                                    <ul class="task-list">
                                        ${w.tasks.map((t) => `
                                            <li class="${t.completed ? 'is-done' : ''}">${esc(t.description)}</li>
                                        `).join('')}
                                    </ul>`}
                            </div>
                            <div class="detail-entry__actions">
                                <button class="btn btn--sm btn--ghost"
                                        data-del-wo="${esc(asset.assetTag)}"
                                        data-order-id="${esc(w.orderId)}">Delete</button>
                            </div>
                        </div>`).join('')}
            </div>
        </section>`;

    openModal('#modalDetail');
}

// Currently registered submit handler for the generic form modal.
let formHandler = null;

// Shows a modal.
function openModal(selector) {
    $(selector).hidden = false;
    document.body.style.overflow = 'hidden';
}

// Hides a modal.
function closeModal(selector) {
    $(selector).hidden = true;
    if ($$('.modal:not([hidden])').length === 0) {
        document.body.style.overflow = '';
    }
}

// Opens the shared form modal.
function openForm(title, bodyHtml, submitLabel, onSubmit) {
    $('#formTitle').textContent = title;
    $('#formBody').innerHTML = bodyHtml;
    $('#formSubmit').textContent = submitLabel;
    formHandler = onSubmit;
    openModal('#modalForm');

    const firstField = $('#formBody input, #formBody select, #formBody textarea');
    if (firstField) {
        firstField.focus();
    }
}

// Collects every named control inside the form modal into a plain object.
function readForm() {
    const data = {};
    $$('#formBody [name]').forEach((field) => {
        if (field.type === 'checkbox') {
            data[field.name] = field.checked;
        } else {
            data[field.name] = field.value.trim();
        }
    });
    return data;
}

let confirmHandler = null;

// Asks the user to confirm a destructive action.
function confirmAction(title, message, onYes) {
    $('#confirmTitle').textContent = title;
    $('#confirmMessage').textContent = message;
    confirmHandler = onYes;
    openModal('#modalConfirm');
}

// Opens the loan form for one asset.
function actionLoan(assetTag) {
    const asset = state.assets.find((a) => a.assetTag === assetTag);
    const defaultDue = addDaysIso(todayIso(), 14);

    openForm(`Loan ${assetTag}`, `
        <p class="hint" style="margin-bottom:16px">
            ${esc(asset ? asset.name : assetTag)} &mdash; currently ${esc(asset ? asset.status : 'unknown')}.
        </p>
        <div class="form-row">
            <label for="f-borrower">Borrower *</label>
            <input type="text" id="f-borrower" name="borrower" required
                   placeholder="Staff number, student number or full name">
        </div>
        <div class="form-row">
            <label for="f-dueDate">Return date</label>
            <input type="date" id="f-dueDate" name="dueDate" value="${defaultDue}" min="${todayIso()}">
            <span class="hint">Defaults to 14 days from today if left blank.</span>
        </div>
        <div class="form-row">
            <label class="check">
                <input type="checkbox" name="spaceBooking">
                <span>This is a room or lab booking (status becomes OCCUPIED)</span>
            </label>
        </div>`, 'Issue asset', async (data) => {
        if (!data.borrower) {
            throw new Error('A borrower is required.');
        }
        const body = {borrower: data.borrower, spaceBooking: data.spaceBooking};
        if (data.dueDate) {
            body.dueDate = data.dueDate;
        }
        await api(`/assets/${seg(assetTag)}/loan`, {method: 'POST', body});
        toast('Asset issued', `${assetTag} is now out with ${data.borrower}.`, 'success');
    });
}

// Opens the return form for one asset.
function actionReturn(assetTag) {
    openForm(`Return ${assetTag}`, `
        <div class="form-row">
            <label class="check">
                <input type="checkbox" name="sendForMaintenance">
                <span>The asset came back damaged &mdash; send it for maintenance</span>
            </label>
            <span class="hint">A work order is raised automatically when this is ticked.</span>
        </div>
        <div class="form-row">
            <label for="f-notes">Condition notes</label>
            <textarea id="f-notes" name="notes"
                      placeholder="Optional notes recorded against the return"></textarea>
        </div>`, 'Accept return', async (data) => {
        await api(`/assets/${seg(assetTag)}/return`, {
            method: 'POST',
            body: {notes: data.notes || '', sendForMaintenance: data.sendForMaintenance}
        });
        toast('Asset returned', `${assetTag} has been checked back in.`, 'success');
    });
}

// Opens the "add schedule" form for one asset.
function actionSchedule(assetTag, scheduleId = null) {
    const asset = state.assets.find((item) => item.assetTag === assetTag);
    const schedule = scheduleId && (asset?.schedules || []).find((item) => item.scheduleId === scheduleId);
    if (scheduleId && !schedule) {
        toast('Schedule not found', 'Refresh the dashboard and try again.', 'error');
        return;
    }
    closeModal('#modalDetail');
    openForm(`${schedule ? 'Edit' : 'Add'} a schedule ${schedule ? 'on' : 'to'} ${assetTag}`, `
        <div class="form-grid">
            <div class="form-row">
                <label for="f-type">Type *</label>
                <select id="f-type" name="type">
                    ${['MAINTENANCE', 'SERVICING', 'INSPECTION', 'BOOKING'].map((type) =>
                        `<option value="${type}" ${type === (schedule?.type || 'MAINTENANCE') ? 'selected' : ''}>${type}</option>`).join('')}
                </select>
            </div>
            <div class="form-row">
                <label for="f-due">Due date *</label>
                <input type="date" id="f-due" name="dueDate" value="${esc(schedule?.dueDate || addDaysIso(todayIso(), 30))}" required>
            </div>
        </div>
        <div class="form-row">
            <label for="f-sdesc">Description</label>
            <textarea id="f-sdesc" name="description"
                      placeholder="e.g. Quarterly calibration and nozzle cleaning">${esc(schedule?.description || '')}</textarea>
        </div>
        <div class="form-row">
            <label for="f-sid">Schedule id</label>
            <input type="text" id="f-sid" name="scheduleId" placeholder="Leave blank to auto-generate"
                   value="${esc(scheduleId || '')}" ${schedule ? 'readonly' : ''}>
        </div>`, schedule ? 'Save changes' : 'Add schedule', async (data) => {
        if (!data.dueDate) {
            throw new Error('A due date is required.');
        }
        const body = {type: data.type, dueDate: data.dueDate, description: data.description || ''};
        if (!schedule && data.scheduleId) {
            body.scheduleId = data.scheduleId;
        }
        const path = `/assets/${seg(assetTag)}/schedules` + (schedule ? `/${seg(scheduleId)}` : '');
        await api(path, {method: schedule ? 'PUT' : 'POST', body});
        toast(schedule ? 'Schedule updated' : 'Schedule added', `${data.type} scheduled for ${data.dueDate}.`, 'success');
    });
}

// Opens the "create work order" form for one asset.
function actionWorkOrder(assetTag) {
    openForm(`Open a work order on ${assetTag}`, `
        <div class="form-row">
            <label for="f-wodesc">Fault description *</label>
            <textarea id="f-wodesc" name="description" required
                      placeholder="e.g. Nozzle heat-bed failure"></textarea>
        </div>
        <div class="form-row">
            <label for="f-wostatus">Status</label>
            <select id="f-wostatus" name="status">
                <option value="OPEN">Open</option>
                <option value="IN_PROGRESS">In progress</option>
            </select>
        </div>
        <div class="form-row">
            <label>Tasks</label>
            <div id="taskRows">
                <div class="task-row">
                    <input type="text" class="task-input" placeholder="e.g. Check thermal sensor connectivity">
                </div>
            </div>
            <button class="btn btn--sm" type="button" id="btnAddTask">+ Add another task</button>
            <span class="hint">Raising an open work order moves an available asset to UNDER_MAINTENANCE.</span>
        </div>`, 'Open work order', async (data) => {
        if (!data.description) {
            throw new Error('A fault description is required.');
        }
        const tasks = $$('#taskRows .task-input')
            .map((input) => input.value.trim())
            .filter((value) => value.length > 0)
            .map((value) => ({description: value, completed: false}));

        await api(`/assets/${seg(assetTag)}/workorders`, {
            method: 'POST',
            body: {status: data.status, description: data.description, tasks}
        });
        toast('Work order opened', `A ${data.status} job was logged against ${assetTag}.`, 'success');
    });
    $('#btnAddTask').addEventListener('click', () => {
        const row = document.createElement('div');
        row.className = 'task-row';
        row.innerHTML = `
            <input type="text" class="task-input" placeholder="Describe the next step">
            <button class="btn btn--sm btn--ghost" type="button" data-drop-task>Remove</button>`;
        $('#taskRows').appendChild(row);
        row.querySelector('input').focus();
        row.querySelector('[data-drop-task]').addEventListener('click', () => row.remove());
    });
}

// Opens the "create asset" form.
function actionNewAsset() {
    openForm('Register a new asset', `
        <div class="form-grid">
            <div class="form-row">
                <label for="f-tag">Asset tag *</label>
                <input type="text" id="f-tag" name="assetTag" required placeholder="NUST-LIB-3DP-002">
            </div>
            <div class="form-row">
                <label for="f-acq">Date acquired *</label>
                <input type="date" id="f-acq" name="dateAcquired" value="${todayIso()}" max="${todayIso()}" required>
            </div>
        </div>
        <div class="form-row">
            <label for="f-name">Name *</label>
            <input type="text" id="f-name" name="name" required placeholder="Pro-Series 3D Printer">
        </div>
        <div class="form-grid">
            <div class="form-row">
                <label for="f-inst">Institution *</label>
                <input type="text" id="f-inst" name="institution" required list="instList"
                       placeholder="Namibia University of Science and Technology">
                <datalist id="instList">
                    ${state.institutions.map((i) => `<option value="${esc(i)}"></option>`).join('')}
                </datalist>
            </div>
            <div class="form-row">
                <label for="f-site">Campus / site *</label>
                <input type="text" id="f-site" name="site" required list="siteList"
                       placeholder="Main Campus - Innovation Lab">
                <datalist id="siteList">
                    ${state.sites.map((s) => `<option value="${esc(s)}"></option>`).join('')}
                </datalist>
            </div>
        </div>
        <div class="form-row">
            <label for="f-status">Status</label>
            <select id="f-status" name="status">
                <option value="AVAILABLE">Available</option>
                <option value="UNDER_MAINTENANCE">Under maintenance</option>
                <option value="DISPOSED">Disposed</option>
            </select>
        </div>
        <div class="form-row">
            <label for="f-desc">Description</label>
            <textarea id="f-desc" name="description" placeholder="What is this resource used for?"></textarea>
        </div>`, 'Create asset', async (data) => {
        for (const field of ['assetTag', 'name', 'institution', 'site', 'dateAcquired']) {
            if (!data[field]) {
                throw new Error(`'${field}' is required.`);
            }
        }
        await api('/assets', {
            method: 'POST',
            body: {
                assetTag: data.assetTag,
                name: data.name,
                description: data.description || '',
                institution: data.institution,
                site: data.site,
                status: data.status,
                dateAcquired: data.dateAcquired,
                components: [],
                schedules: [],
                workOrders: []
            }
        });
        toast('Asset registered', `${data.assetTag} was added to the catalogue.`, 'success');
    });
}

// Switches the visible tab panel.
function switchView(view) {
    $$('.tab').forEach((tab) => tab.classList.toggle('is-active', tab.dataset.view === view));
    $$('.view').forEach((panel) => panel.classList.toggle('is-active', panel.id === `view-${view}`));
}

// Wires every event listener exactly once.
function wireEvents() {
    $('#btnTheme').addEventListener('click', () => {
        const next = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
        applyTheme(next);
    });

    $('#btnRefresh').addEventListener('click', async () => {
        if (await loadAll()) {
            toast('Refreshed', 'The dashboard is showing the latest data.', 'success');
        }
    });

    $('#btnNewAsset').addEventListener('click', actionNewAsset);
    $$('.tab').forEach((tab) => {
        tab.addEventListener('click', () => switchView(tab.dataset.view));
    });
    $('#searchInput').addEventListener('input', debounce((event) => {
        state.filters.q = event.target.value;
        renderAssets();
    }, 180));

    $('#filterInstitution').addEventListener('change', (event) => {
        state.filters.institution = event.target.value;
        renderAssets();
    });

    $('#filterSite').addEventListener('change', (event) => {
        state.filters.site = event.target.value;
        renderAssets();
    });

    $('#filterStatus').addEventListener('change', (event) => {
        state.filters.status = event.target.value;
        renderAssets();
    });

    $('#btnClearFilters').addEventListener('click', () => {
        state.filters = {q: '', institution: '', site: '', status: ''};
        $('#searchInput').value = '';
        $('#filterInstitution').value = '';
        $('#filterSite').value = '';
        $('#filterStatus').value = '';
        renderAssets();
    });
    $$('#assetTable th.sortable').forEach((th) => {
        th.addEventListener('click', () => {
            const key = th.dataset.sort;
            state.sort = (state.sort.key === key)
                ? {key, dir: state.sort.dir === 'asc' ? 'desc' : 'asc'}
                : {key, dir: 'asc'};
            renderAssets();
        });
    });
    $$('[data-close]').forEach((el) => {
        el.addEventListener('click', () => {
            const modal = el.closest('.modal');
            if (modal) {
                closeModal(`#${modal.id}`);
            }
        });
    });

    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') {
            $$('.modal:not([hidden])').forEach((modal) => closeModal(`#${modal.id}`));
        }
    });

    $('#genericForm').addEventListener('submit', async (event) => {
        event.preventDefault();
        if (!formHandler) {
            return;
        }
        const button = $('#formSubmit');
        const label = button.textContent;
        button.disabled = true;
        button.textContent = 'Working...';
        try {
            await formHandler(readForm());
            closeModal('#modalForm');
            await loadAll();
        } catch (error) {
            toast('Request rejected', error.message, 'error');
        } finally {
            button.disabled = false;
            button.textContent = label;
        }
    });

    $('#confirmYes').addEventListener('click', async () => {
        closeModal('#modalConfirm');
        if (confirmHandler) {
            try {
                await confirmHandler();
                await loadAll();
            } catch (error) {
                toast('Request rejected', error.message, 'error');
            }
        }
    });
    document.addEventListener('click', (event) => {
        const target = event.target.closest('[data-detail], [data-loan], [data-return],' +
            '[data-schedule], [data-edit-schedule], [data-workorder], [data-delete], [data-del-schedule],' +
            '[data-del-component], [data-del-wo], [data-close-wo]');
        if (!target) {
            return;
        }
        const d = target.dataset;

        if (d.detail !== undefined) {
            openDetail(d.detail);
        } else if (d.loan !== undefined) {
            actionLoan(d.loan);
        } else if (d.return !== undefined) {
            actionReturn(d.return);
        } else if (d.schedule !== undefined) {
            actionSchedule(d.schedule);
        } else if (d.editSchedule !== undefined) {
            actionSchedule(d.editSchedule, d.scheduleId);
        } else if (d.workorder !== undefined) {
            actionWorkOrder(d.workorder);
        } else if (d.delete !== undefined) {
            confirmAction('Delete asset',
                `Permanently remove ${d.delete} from the catalogue? This cannot be undone.`,
                async () => {
                    await api(`/assets/${seg(d.delete)}`, {method: 'DELETE'});
                    toast('Asset deleted', `${d.delete} was removed.`, 'success');
                });
        } else if (d.delSchedule !== undefined) {
            confirmAction('Remove schedule',
                `Remove schedule ${d.scheduleId} from ${d.delSchedule}?`,
                async () => {
                    await api(`/assets/${seg(d.delSchedule)}/schedules/${seg(d.scheduleId)}`,
                        {method: 'DELETE'});
                    closeModal('#modalDetail');
                    toast('Schedule removed', `${d.scheduleId} was deleted.`, 'success');
                });
        } else if (d.delComponent !== undefined) {
            confirmAction('Remove component',
                `Detach component ${d.componentId} from ${d.delComponent}?`,
                async () => {
                    await api(`/assets/${seg(d.delComponent)}/components/${seg(d.componentId)}`,
                        {method: 'DELETE'});
                    closeModal('#modalDetail');
                    toast('Component removed', `${d.componentId} was detached.`, 'success');
                });
        } else if (d.delWo !== undefined) {
            confirmAction('Delete work order',
                `Delete work order ${d.orderId} from ${d.delWo}?`,
                async () => {
                    await api(`/assets/${seg(d.delWo)}/workorders/${seg(d.orderId)}`,
                        {method: 'DELETE'});
                    closeModal('#modalDetail');
                    toast('Work order deleted', `${d.orderId} was removed.`, 'success');
                });
        } else if (d.closeWo !== undefined) {
            confirmAction('Close work order',
                `Mark work order ${d.orderId} on ${d.closeWo} as CLOSED?`,
                async () => {
                    await api(`/assets/${seg(d.closeWo)}/workorders/${seg(d.orderId)}`,
                        {method: 'PUT', body: {status: 'CLOSED'}});
                    toast('Work order closed', `${d.orderId} is now CLOSED.`, 'success');
                });
        }
    });
}

// Application entry point.
async function start() {
    initTheme();
    $('#apiBadge').innerHTML = `API: <code>${esc(API_BASE)}</code>`;
    wireEvents();

    try {
        await api('/health');
        setConnection(true);
    } catch (error) {
        setConnection(false);
        toast('API unreachable', error.message, 'error');
    }

    await loadAll();
    setInterval(loadAll, 30000);
}

document.addEventListener('DOMContentLoaded', start);
