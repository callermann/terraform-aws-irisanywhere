data "template_file" "iris_mixed_role" {
  template = file("${path.module}/iris_mixed_role.json")
}

data "template_file" "iris_mixed_policy" {
  template = file("${path.module}/iris_mixed_policy.json")

  vars = {
    cluster = replace("${var.hostname_prefix}-${var.instance_type}", ".", "")
  }
}

resource "aws_iam_role" "iris_mixed" {
  name               = replace("${var.hostname_prefix}-${var.instance_type}-Role", ".", "")
  assume_role_policy = data.template_file.iris_mixed_role.rendered
}

resource "aws_iam_instance_profile" "iris_mixed" {
  name = replace("${var.hostname_prefix}-${var.instance_type}-Profile", ".", "")
  role = aws_iam_role.iris_mixed.name
}

resource "aws_iam_policy" "iris_mixed" {
  name   = replace("${var.hostname_prefix}-${var.instance_type}-Policy", ".", "")
  policy = data.template_file.iris_mixed_policy.rendered
}

resource "aws_iam_role_policy_attachment" "iris_mixed" {
  policy_arn = aws_iam_policy.iris_mixed.arn
  role       = aws_iam_role.iris_mixed.name
}
