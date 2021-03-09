output "worker_asg_name" {
  value = "${aws_autoscaling_group.iris_mixed.name}"
}
