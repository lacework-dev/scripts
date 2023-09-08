import oci
import csv
counter = dict()
QUERY_STRING = "QUERY all resources where lifeCycleState != 'TERMINATED' && lifeCycleState != 'FAILED'"
search_client = oci.resource_search.ResourceSearchClient(oci.config.from_file())
structured_search = oci.resource_search.models.StructuredSearchDetails(query=QUERY_STRING)
next_page = None
while True:
    instances = search_client.search_resources(structured_search, page=next_page)
    for instance in instances.data.items:
        resource_type = instance.resource_type.lower()
        if resource_type not in counter:
            counter[resource_type] = 0
        counter[resource_type] += 1
    if not instances.next_page:
        break
    next_page = instances.next_page

with open('OCIUsageMetrics.csv', 'w') as csvfile:
    writer = csv.writer(csvfile)
    writer.writerow(['Resource', 'Count'])
    for row in counter.items():
        writer.writerow(row)