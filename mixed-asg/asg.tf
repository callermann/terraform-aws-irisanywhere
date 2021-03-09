data "null_data_source" "tags" {
  count = length(keys(local.merged_tags))

  inputs = {
    key                 = "${element(keys(local.merged_tags), count.index)}"
    value               = "${element(values(local.merged_tags), count.index)}"
    propagate_at_launch = true
  }
}

data "template_file" "cloud_init" {
  template = file("${path.module}/cloud_init.ps1")

  vars = {
    name                  = replace("${var.hostname_prefix}-${var.instance_type}", ".", "")
    metric_check_interval = var.asg_check_interval
    health_check_interval = var.lb_check_interval
    unhealthy_threshold   = var.lb_unhealthy_threshold
    cooldown              = var.asg_scalein_cooldown
    ia_adm_id             = var.ia_adm_id
    ia_adm_pw             = var.ia_adm_pw
    ia_lic_content        = var.ia_lic_content
    ia_cert_file          = var.ia_cert_file
    ia_cert_key_content   = var.ia_cert_key_content
    ia_max_sessions       = var.ia_max_sessions
    ia_s3_conn_id         = var.ia_s3_conn_id
    ia_s3_conn_code       = var.ia_s3_conn_code
    ia_customer_id        = var.ia_customer_id
    ia_admin_server       = var.ia_admin_server
    ia_service_acct       = var.ia_service_acct
    ia_bucket_name        = var.ia_bucket_name
    ia_access_key         = var.ia_access_key
    ia_secret_key         = var.ia_secret_key
  }
}

resource "aws_launch_template" "iris_mixed" {
  name_prefix            = replace("${var.hostname_prefix}-${var.instance_type}", ".", "")
  image_id               = coalesce(var.base_ami, data.aws_ami.GrayMeta-Iris-Anywhere.id)
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.iris.id]
  user_data              = base64encode(data.template_file.cloud_init.rendered)
  ebs_optimized          = true

  instance_initiated_shutdown_behavior = "terminate"

  iam_instance_profile {
    name = aws_iam_instance_profile.iris_mixed.name
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_type           = var.disk_os_type
      volume_size           = var.disk_os_size
      encrypted             = true
      delete_on_termination = "true"
    }
  }

  block_device_mappings {
    device_name = "/dev/sda2"

    ebs {
      volume_type           = var.disk_data_type
      volume_size           = var.disk_data_size
      iops                  = var.disk_data_iops
      encrypted             = true
      delete_on_termination = "true"
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.merged_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.merged_tags
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "iris_mixed" {
  name                  = replace("${var.hostname_prefix}-${var.instance_type}", ".", "")
  desired_capacity      = var.asg_size_desired
  max_size              = var.asg_size_max
  min_size              = var.asg_size_min
  protect_from_scale_in = true
  vpc_zone_identifier   = var.subnet_id
  target_group_arns     = ["${aws_lb_target_group.port443.id}"]

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceCapacity",
    "GroupPendingCapacity",
    "GroupMinSize",
    "GroupMaxSize",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupStandbyCapacity",
    "GroupTerminatingCapacity",
    "GroupTerminatingInstances",
    "GroupTotalCapacity",
    "GroupTotalInstances",
  ]

  # https://docs.aws.amazon.com/autoscaling/ec2/APIReference/API_InstancesDistribution.html
  mixed_instances_policy {
    instances_distribution {
      on_demand_allocation_strategy            = "prioritized"
      on_demand_base_capacity                  = var.asg_on_demand_base_capacity
      on_demand_percentage_above_base_capacity = var.asg_on_demand_percentage
      spot_allocation_strategy                 = "lowest-price"
      spot_instance_pools                      = var.asg_spot_pools
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.iris_mixed.id
        version            = "$$Latest"
      }

      override {
        instance_type     = "c4.large"
      }
    }
  }

  lifecycle {
    ignore_changes = [
      desired_capacity,
    ]
  }

  tags = flatten(["${data.null_data_source.tags.*.outputs}"])

}

resource "aws_autoscaling_policy" "out" {
  name                   = replace("${var.hostname_prefix}-${var.instance_type}-ScaleOut", ".", "")
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = var.asg_scaleout_cooldown
  autoscaling_group_name = aws_autoscaling_group.iris_mixed.name
}

resource "aws_cloudwatch_metric_alarm" "out" {
  alarm_name          = replace("${var.hostname_prefix}-${var.instance_type}-ScaleOut", ".", "")
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = var.asg_scaleout_evaluation
  metric_name         = "IrisAvailableSessions"
  namespace           = "AWS/EC2"
  period              = var.asg_check_interval
  statistic           = "Sum"
  threshold           = var.asg_scaleout_threshold

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.iris_mixed.name
  }

  alarm_description = "This metric monitors iris anywhere available sessions"
  alarm_actions     = [aws_autoscaling_policy.out.arn]
}

resource "aws_autoscaling_policy" "in" {
  name                   = replace("${var.hostname_prefix}-${var.instance_type}-ScaleIn", ".", "")
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = var.asg_scalein_cooldown
  autoscaling_group_name = aws_autoscaling_group.iris_mixed.name
}

resource "aws_cloudwatch_metric_alarm" "in" {
  alarm_name          = replace("${var.hostname_prefix}-${var.instance_type}-ScaleIn", ".", "")
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.asg_scalein_evaluation
  metric_name         = "IrisAvailableSessions"
  namespace           = "AWS/EC2"
  period              = var.asg_check_interval
  statistic           = "Sum"
  threshold           = var.asg_scalein_threshold

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.iris_mixed.name
  }

  alarm_description = "This metric monitors iris anywhere available sessions"
  alarm_actions     = [aws_autoscaling_policy.in.arn]
}
