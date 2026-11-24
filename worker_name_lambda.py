
import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

autoscaling = boto3.client("autoscaling")
ec2 = boto3.client("ec2")

ASG_NAME = os.environ["ASG_NAME"]


def lambda_handler(event, context):
    logger.info("Received event: %s", json.dumps(event))

    # Ignore events belonging to another Auto Scaling Group.
    detail = event.get("detail", {})
    event_group = detail.get("AutoScalingGroupName")

    if event_group and event_group != ASG_NAME:
        logger.info("Ignoring unrelated group: %s", event_group)
        return {
            "statusCode": 200,
            "message": "Ignored unrelated group"
        }

    # Retrieve the EKS worker Auto Scaling Group.
    response = autoscaling.describe_auto_scaling_groups(
        AutoScalingGroupNames=[ASG_NAME]
    )

    groups = response.get("AutoScalingGroups", [])

    if not groups:
        raise RuntimeError(
            f"Auto Scaling Group not found: {ASG_NAME}"
        )

    # Find all workers currently in service.
    instance_ids = [
        instance["InstanceId"]
        for instance in groups[0].get("Instances", [])
        if instance["LifecycleState"] == "InService"
    ]

    if not instance_ids:
        logger.info("No InService workers found")
        return {
            "statusCode": 200,
            "tagged": 0
        }

    tagged_count = 0

    # Assign each instance its own unique EC2 Name tag.
    for instance_id in instance_ids:
        worker_name = f"eks-worker-{instance_id}"

        ec2.create_tags(
            Resources=[instance_id],
            Tags=[
                {
                    "Key": "Name",
                    "Value": worker_name
                }
            ]
        )

        tagged_count += 1

        logger.info(
            "Tagged instance %s as %s",
            instance_id,
            worker_name
        )

    return {
        "statusCode": 200,
        "tagged": tagged_count,
        "instances": instance_ids
    }
