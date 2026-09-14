"""Exercise Question 1 over HTTP using a temporary institution and asset."""

import argparse
import json
import uuid
from datetime import date, timedelta
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://localhost:8081')
    args = parser.parse_args()
    base = args.url.rstrip('/')
    checks = 0

    def request(method, path, body=None, expected=None, raw=None):
        nonlocal checks
        if expected is None:
            expected = 201 if method == 'POST' else 200
        payload = raw if raw is not None else (
            json.dumps(body).encode() if body is not None else None)
        req = Request(base + path, data=payload, method=method,
                      headers={'Content-Type': 'application/json'})
        try:
            response = urlopen(req, timeout=15)
        except HTTPError as error:
            response = error
        with response:
            data = response.read().decode()
            assert response.status == expected, (
                f'{method} {path}: expected {expected}, got {response.status}: {data}')
            checks += 1
            try:
                return json.loads(data)
            except json.JSONDecodeError:
                return data

    suffix = uuid.uuid4().hex[:8]
    institution = f'HTTP Test Institute {suffix}'
    tag = f'TEST-{suffix}'
    asset_path = '/assets/' + tag
    institution_path = '/institutions/' + quote(institution)
    today = date.today()
    future = (today + timedelta(days=14)).isoformat()
    past = (today - timedelta(days=2)).isoformat()
    registered = False
    try:
        assert request('GET', '/health')['status'] == 'UP'
        assert isinstance(request('GET', '/assets'), list)
        request('POST', '/institutions', {'name': institution}, 201)
        registered = True
        assert institution in request('GET', '/institutions')
        request('POST', '/institutions', {'name': institution.lower()}, 409)
        asset = {'assetTag': tag, 'name': 'Test laptop', 'description': 'HTTP verification',
                 'institution': institution, 'site': 'Test Campus',
                 'dateAcquired': '2024-03-10', 'status': 'AVAILABLE'}
        assert request('POST', '/assets', asset, 201)['assetTag'] == tag
        request('POST', '/assets', asset, 409)
        assert request('GET', asset_path)['name'] == asset['name']
        assert request('PUT', asset_path, {'name': 'Updated laptop'})['name'] == 'Updated laptop'
        assert [a['assetTag'] for a in request('GET', '/assets/institution/' + quote(institution))] == [tag]
        assert any(a['assetTag'] == tag for a in request('GET', '/assets/site/Test%20Campus'))
        assert request('GET', '/assets?institution=' + quote(institution) + '&site=Test%20Campus')[0]['assetTag'] == tag
        assert 'Test Campus' in request('GET', '/sites?institution=' + quote(institution))
        assert request('GET', '/summary')['totalAssets'] >= 1

        result = request('POST', asset_path + '/components', {'compId': 'C-TEST', 'name': 'Battery'})
        assert result['components'][0]['compId'] == 'C-TEST'
        request('POST', asset_path + '/components', {'compId': 'C-TEST', 'name': 'Battery'}, 409)
        assert request('DELETE', asset_path + '/components/C-TEST')['components'] == []

        result = request('POST', asset_path + '/schedules', {
            'scheduleId': 'SCH-TEST', 'type': 'MAINTENANCE', 'dueDate': past,
            'description': 'Test servicing'})
        assert result['schedules'][0]['dueDate'] == past
        overdue = request('GET', '/maintenance/overdue?institution=' + quote(institution))
        assert overdue[0]['assetTag'] == tag and overdue[0]['daysOverdue'] == 2
        result = request('PUT', asset_path + '/schedules/SCH-TEST', {'dueDate': future})
        assert result['schedules'][0]['dueDate'] == future
        assert request('GET', '/maintenance/overdue?institution=' + quote(institution)) == []
        request('PUT', asset_path + '/schedules/SCH-TEST', {'dueDate': '2026-02-30'}, 400)
        request('DELETE', asset_path + '/schedules/SCH-TEST')
        request('POST', asset_path + '/schedules', {'type': 'BOOKING', 'dueDate': future, 'scheduleId': 'BOOK-1'})
        request('POST', asset_path + '/schedules', {'type': 'BOOKING', 'dueDate': future, 'scheduleId': 'BOOK-2'}, 409)
        request('DELETE', asset_path + '/schedules/BOOK-1')

        assert request('POST', asset_path + '/loan', {'borrower': 'Test Student', 'dueDate': future})['status'] == 'LOANED_OUT'
        request('POST', asset_path + '/loan', {'borrower': 'Second Student'}, 409)
        request('DELETE', asset_path, expected=409)
        request('DELETE', institution_path, expected=409)
        request('PUT', asset_path, {'status': 'AVAILABLE'}, 409)
        assert request('POST', asset_path + '/return', {})['status'] == 'AVAILABLE'
        assert request('GET', '/loans?assetTag=' + tag)[0]['active'] is False
        assert request('POST', asset_path + '/loan', {'borrower': 'Room User', 'spaceBooking': True})['status'] == 'OCCUPIED'
        assert request('POST', asset_path + '/return', {})['status'] == 'AVAILABLE'

        result = request('POST', asset_path + '/workorders', {
            'orderId': 'WO-TEST', 'description': 'Faulty screen',
            'tasks': [{'taskId': 'T1', 'description': 'Replace screen'}]})
        assert result['status'] == 'UNDER_MAINTENANCE'
        assert result['workOrders'][0]['tasks'][0]['taskId'] == 'T1'
        result = request('PUT', asset_path + '/workorders/WO-TEST', {
            'status': 'IN_PROGRESS', 'tasks': [{'taskId': 'T1', 'description': 'Replace screen', 'completed': True}]})
        assert result['workOrders'][0]['tasks'][0]['completed'] is True
        result = request('PUT', asset_path + '/workorders/WO-TEST', {'status': 'CLOSED'})
        assert result['status'] == 'AVAILABLE'
        assert request('DELETE', asset_path + '/workorders/WO-TEST')['workOrders'] == []

        request('GET', '/assets/UNKNOWN-' + suffix, expected=404)
        request('GET', '/assets?status=WRONG', expected=400)
        request('POST', '/assets', {'name': 'Missing required fields'}, 400)
        request('POST', asset_path + '/schedules', {'type': 'WRONG', 'dueDate': future}, 400)
        request('POST', '/assets', expected=400, raw=b'{broken')
        request('GET', '/unknown-route-' + suffix, expected=404)
        request('PATCH', asset_path, {}, 405)
        request('DELETE', asset_path)
        request('GET', asset_path, expected=404)
        request('DELETE', institution_path)
        registered = False
        assert institution not in request('GET', '/institutions')
        print(f'PASS: {checks} HTTP checks against {base}')
    finally:
        if registered:
            try:
                request('POST', asset_path + '/return', {})
            except Exception:
                pass
            try:
                request('DELETE', institution_path)
            except Exception as error:
                print(f'Cleanup needed for {institution}: {error}')


if __name__ == '__main__':
    main()
