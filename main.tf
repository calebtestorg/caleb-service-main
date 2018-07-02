variable project_name {}
variable port {}
variable ecs_terraform_state_bucket {}
variable ecs_terraform_state_key {}

data terraform_remote_state ecs_cluster {
  backend = "s3"
  workspace = "${terraform.workspace}"

  config {
    bucket = "${var.ecs_terraform_state_bucket}"
    key = "${var.ecs_terraform_state_key}"
    region = "ap-southeast-2"
  }
}

locals {
  name = "${terraform.workspace}-${var.project_name}"
}

provider aws {
  region = "ap-southeast-2"
}

terraform {
  backend s3 {
    region = "ap-southeast-2"
    key = "caleb-service-main/state.tfstate"
    bucket = "terraform-state-20180702084825854500000001"
  }
}

// AWS Elastic Container Repository

resource aws_ecr_repository ecr_repo {
  name = "${local.name}"
}

resource null_resource push_image {
  provisioner local-exec {
    command = "lein uberjar && docker build -t ${var.project_name} . && docker tag ${var.project_name} ${aws_ecr_repository.ecr_repo.repository_url} && eval $(aws ecr get-login --no-include-email) && docker push ${aws_ecr_repository.ecr_repo.repository_url}"
  }
}

// Logs

resource aws_cloudwatch_log_group ecs_logs {
  name = "/aws/ecs/${local.name}/container"
}

resource aws_cloudwatch_log_stream ecs_logs {
  log_group_name = "${aws_cloudwatch_log_group.ecs_logs.name}"
  name = "${local.name}"
}

// Elastic Container Service Service

resource aws_ecs_task_definition ecr_task_def {
  family = "${local.name}"
  container_definitions = <<EOF
[
    {
        "name": "${local.name}",
        "image": "${aws_ecr_repository.ecr_repo.repository_url}",
        "cpu": 10,
        "memory": 500,
        "portMappings": [
            {
                "containerPort": ${var.port}
            }
        ],
        "entryPoint": [
            "java",
            "-jar",
            "/${var.project_name}/app.jar"
        ],
        "essential": true,
        "logConfiguration": {
          "logDriver": "awslogs",
          "options": {
            "awslogs-group": "${aws_cloudwatch_log_group.ecs_logs.name}",
            "awslogs-region": "ap-southeast-2",
            "awslogs-stream-prefix": "${aws_cloudwatch_log_stream.ecs_logs.name}"
          }
        }
    }
]
EOF
}

data aws_iam_policy_document ecs_role {

  statement {
    actions = [
      "sts:AssumeRole"
    ]
    principals {
      identifiers = [
        "ecs.amazonaws.com"
      ]
      type = "Service"
    }
  }
}

resource aws_iam_role ecs_role {
  name = "${local.name}"
  assume_role_policy = "${data.aws_iam_policy_document.ecs_role.json}"
}

data aws_iam_policy_document ecs_role_policy {

  statement {
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:Describe*",
      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:Describe*",
      "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
      "elasticloadbalancing:RegisterTargets"
    ]
    resources = [
      "*"
    ]
  }
}

resource aws_iam_role_policy ecs_role_policy {
  name = "${local.name}-ecs"
  role = "${aws_iam_role.ecs_role.id}"
  policy = "${data.aws_iam_policy_document.ecs_role_policy.json}"
}

resource aws_ecs_service ecs_service {
  name = "${local.name}"
  task_definition = "${aws_ecs_task_definition.ecr_task_def.family}:${aws_ecs_task_definition.ecr_task_def.revision}"
  desired_count = 1
  cluster = "${data.terraform_remote_state.ecs_cluster.ecs_cluster_id}"

  depends_on = [
    "aws_iam_role.ecs_role",
    "aws_lb_listener.lbl"
  ]

  iam_role = "${aws_iam_role.ecs_role.arn}"

  load_balancer {
    target_group_arn = "${aws_lb_target_group.lb_tg.arn}"
    container_name = "${local.name}"
    container_port = "${var.port}"
  }

  lifecycle {
    ignore_changes = [
      "desired_count"
    ]
  }
}

// ========== ALB ==========

resource aws_security_group lb_sg {
  name = "${local.name}-lb"
  vpc_id = "${data.terraform_remote_state.ecs_cluster.vpc_id}"

  ingress {
    from_port = "${var.port}"
    to_port = "${var.port}"
    protocol = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [
      "0.0.0.0/0"]
  }

}

resource aws_lb lb {
  name = "${local.name}"
  internal = false
  security_groups = [
    "${aws_security_group.lb_sg.id}"
  ]
  subnets = [
    "${data.terraform_remote_state.ecs_cluster.sn_0_id}",
    "${data.terraform_remote_state.ecs_cluster.sn_1_id}"
  ]
}

resource aws_lb_listener lbl {
  default_action {
    target_group_arn = "${aws_lb_target_group.lb_tg.arn}"
    type = "forward"
  }
  load_balancer_arn = "${aws_lb.lb.arn}"
  protocol = "HTTP"
//  protocol = "HTTPS"
//  ssl_policy = "ELBSecurityPolicy-2016-08"
//  certificate_arn = "${aws_acm_certificate_validation.cert_validation.certificate_arn}"
  port = "${var.port}"
  depends_on = [
    "aws_lb.lb"
  ]
}

resource aws_lb_target_group lb_tg {
  name = "${local.name}-lb"
  port = "${var.port}"
  protocol = "HTTP"
  vpc_id = "${data.terraform_remote_state.ecs_cluster.vpc_id}"
  health_check {
    path = "/healthcheck"
    protocol = "HTTP"
    matcher = "200"
  }
}
