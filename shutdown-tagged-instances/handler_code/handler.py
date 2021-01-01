#! /usr/bin/env python3
import os
import json
from distutils.util import strtobool
import boto3
from botocore.config import Config

def lambda_handler(event, context):
    # just because it's always helpful, let's log the inbound event as that data
    # controls the exeuction of the code below to some degree
    print(json.dumps(event))
    key_name = os.environ.get('SHUTDOWN_KEY', 'Shutdown')
    key_value = os.environ.get('SHUTDOWN_VALUE', 'nightly') 
    # when triggered by a cloudwatch event, there will be a region property on the 
    # event specifying where the event came from ,this is likely the best choice to
    # trigger the function 'targeting' the region associated with the event. Which
    # means per region events will trigger the function for each region, however as
    # a convenience, it's possible to fix the region using the env var REGION
    shutdown_region = os.environ.get('REGION', event['region'])

    print(f"Looking for instances tagged ({key_name}:{key_value}) in {shutdown_region}")
    config = Config(region_name=shutdown_region)
    client = boto3.client('ec2', config=config)
    paginator = client.get_paginator('describe_instances').paginate(
        Filters=[
                {
                    'Name': f"tag:{key_name}",
                    'Values': [f"{key_value}"]
                },
                {'Name': 'instance-state-name', 'Values': ['running']}
        ],
        PaginationConfig=dict(
            # personally, if we're shutting down more than 100 instances
            # I sort of feel like someone should change the code deliberately
            MaxItems=100,
            PageSize=5
        )
    )
    instance_ids_tagged_for_shutdown = []
    for page in paginator:
        for reservation in page['Reservations']:
            for instance in reservation['Instances']:
                instance_ids_tagged_for_shutdown.append(instance['InstanceId'])

    # first we default to dry run, unless an environment variable (DRY_RUN) is
    #  is present in which case we assume it is 'boolable'
    is_dry_run = os.environ.get('DRY_RUN', 'True')
    # Then we check the event to see if dry_run is present, if that is the case
    # it will override anything previously set, again assuming the value is 'boolable'
    # we're forcing this to a str here so the provided value can fit many possible values 
    # including all the supported strtobool strings, and an explicit boolean in the event
    is_dry_run = str(event.get('dry_run', is_dry_run))
    is_dry_run = strtobool(is_dry_run)
    if instance_ids_tagged_for_shutdown:
        if is_dry_run:
            print(f"Without DRY_RUN would be shutting down instances: {instance_ids_tagged_for_shutdown}")
        else:
            print(f"Shutting down instances: {instance_ids_tagged_for_shutdown}")
            client.stop_instances(InstanceIds=instance_ids_tagged_for_shutdown)

    return {
        'statusCode': 200,
        'body': '{"message": "ok"}'
    }

if __name__ == "__main__":
    lambda_handler(event=dict(region="us-east-1"), context=None)