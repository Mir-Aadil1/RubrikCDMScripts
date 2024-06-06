import time
import os
import json
import requests
import csv

output_data = []


API_URL = "https://rubrik-support.my.rubrik.com/api/graphql"
TOKEN_CACHE_PATH = 'token_cache.json'


CLIENT_ID = "client|xxxxxxx"
CLIENT_SECRET = "xxxxxxxxxxxxxxxxxxxxxxx"
ACCESS_TOKEN_URI = "https://rubrik-support.my.rubrik.com/api/client_token"


GRAPHQL_QUERY = """
query EventSeriesListQuery($filters: ActivitySeriesFilter, $first: Int) {
  activitySeriesConnection(filters: $filters, first: $first) {
    edges {
      node {
        activitySeriesId
        lastActivityStatus
        objectId
        objectName
        clusterName
        lastUpdated
        location
      }
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}
"""
EVENT_SERIES_DETAILS_QUERY = """
query EventSeriesDetailsQuery($activitySeriesId: UUID!, $clusterUuid: UUID) {
  activitySeries(input: {activitySeriesId: $activitySeriesId, clusterUuid: $clusterUuid}) {
    activityConnection {
      nodes {
        activityInfo
        message
        status
        time
        severity
      }
    }
    activitySeriesId
    objectName
    location
    lastUpdated
  }
}
"""


def generate_token():

    if os.path.exists(TOKEN_CACHE_PATH):
        with open(TOKEN_CACHE_PATH, 'r') as cache_file:
            data = json.load(cache_file)
            # Check if the token has expired
            if data['expiry'] > time.time():
                return data['token']

    try:
        token_headers = {
            "Content-Type": "application/json"
        }
        token_data = {
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET
        }

        token_response = requests.post(
            ACCESS_TOKEN_URI, headers=token_headers, json=token_data)
        if token_response.status_code == 200:
            token_info = token_response.json()
            api_token = token_info.get('access_token')

            # Cache the token
            # Defaulting to 1 hour if expires_in is not provided
            expiry = time.time() + token_info.get('expires_in', 3600)
            with open(TOKEN_CACHE_PATH, 'w') as cache_file:
                json.dump({'token': api_token, 'expiry': expiry}, cache_file)

            return api_token

        else:
            print(
                f"Request failed with status code {token_response.status_code}")
            return None
    except Exception as err:
        print(f"An error occurred: {err}")
        return None


def make_graphql_request(query, variables=None, api_token=None):
    if not api_token:
        api_token = generate_token()

    api_headers = {
        "Authorization": f"Bearer {api_token}",
        "Content-Type": "application/json",
        "Accept": "application/json"
    }

    try:
        request_data = {"query": query}

        if variables:
            request_data["variables"] = variables

        response = requests.post(
            API_URL, headers=api_headers, json=request_data)

        response_status = response.status_code
        response_data = response.json()

        return response_data or {}

    except Exception as err:
        print(f"An error occurred: {err}")
        return None


if __name__ == "__main__":
    variables = {
        "filters": {
            "objectType": ["DB2_DATABASE"],
            "lastActivityStatus": ["FAILURE"],
            "lastActivityType": ["BACKUP"],
            "clusterId": ["ca6a2191-ffde-4b92-8fa9-dd7e9836a611"],
            "lastUpdatedTimeGt": "2023-10-04T17:53:34.118Z",
            "lastUpdatedTimeLt": "2023-11-21T18:29:59.999Z",
        },
        "first": 999
    }

    response_data = make_graphql_request(GRAPHQL_QUERY, variables)

    result_list = response_data.get('data', {}).get(
        'activitySeriesConnection', {}).get('edges', [])

    failed_activity_series_ids = [item['node']
                                  ['activitySeriesId'] for item in result_list]
    print("Total Failed Activities:", len(result_list))

    for item in result_list:
        node_data = item.get('node', {})
        print(f"ID: {node_data.get('id')}, Status: {node_data.get('lastActivityStatus')}, Object: {node_data.get('objectName')}, Cluster: {node_data.get('clusterName')}, Last Updated: {node_data.get('lastUpdated')}")
    print(len(result_list))

    output_data = []

    for item in result_list:
        node_data = item.get('node', {})
        activity_series_id = node_data.get('activitySeriesId')

        variables_details_query = {"activitySeriesId": activity_series_id,
                                   "clusterUuid": "ca6a2191-ffde-4b92-8fa9-dd7e9836a611"}
        response_details_query = make_graphql_request(
            EVENT_SERIES_DETAILS_QUERY, variables_details_query)

        if response_details_query is not None:
            activity_series_details = response_details_query.get(
                'data', {}).get('activitySeries', {})
            activity_connection = activity_series_details.get(
                'activityConnection', {})
            nodes = activity_connection.get('nodes', [])

            if nodes:
                first_activity_info = nodes[0].get('activityInfo', '')
                first_activity_message = nodes[0].get('message', '')
                first_activity_status = nodes[0].get('status', '')
                first_activity_time = nodes[0].get('time', '')
                first_activity_severity = nodes[0].get('severity', '')

                row_data = {
                    "Activity Series ID": activity_series_id,
                    "Status": node_data.get('lastActivityStatus'),
                    "Object": node_data.get('objectName'),
                    "Cluster": node_data.get('clusterName'),
                    "Last Updated": node_data.get('lastUpdated'),
                    "Hostname": node_data.get('location'),
                    "First Activity Info": first_activity_info,
                    "First Activity Message": first_activity_message,
                    "First Activity Status": first_activity_status,
                    "First Activity Time": first_activity_time,
                    "First Activity Severity": first_activity_severity
                }

                output_data.append(row_data)

            else:
                print(
                    f"No activity nodes found for Activity Series ID: {activity_series_id}")

        else:
            print(
                f"Failed to fetch details for Activity Series ID: {activity_series_id}")

    csv_file_path = "output.csv"

    with open(csv_file_path, 'w', newline='') as csvfile:
        fieldnames = output_data[0].keys()
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)

        writer.writeheader()

        for row in output_data:
            writer.writerow(row)

    print(f"CSV file created successfully at {csv_file_path}")



