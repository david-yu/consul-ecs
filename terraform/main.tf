provider "aws" {
  region = var.region
}

resource "aws_ecs_service" "mesh-app" {
  name            = "mesh-app-hcp-test"
  cluster         = var.ecs_cluster
  task_definition = module.mesh-app.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets          = var.subnets
    assign_public_ip = true
  }
  launch_type            = "FARGATE"
  propagate_tags         = "TASK_DEFINITION"
  enable_execute_command = true
}

module "mesh-app" {
  source                              = "./modules/mesh-task"
  family                              = "mesh-app-hcp-test"
  retry_join_url                      = [hcp_consul_cluster.this.consul_private_endpoint_url]
  datacenter                          = jsondecode(base64decode(hcp_consul_cluster.this.consul_config_file))["datacenter"]
  execution_role_arn                  = aws_iam_role.mesh-app-execution.arn
  task_role_arn                       = aws_iam_role.mesh_app_task.arn
  port                                = "9090"
  consul_image                        = var.consul_image
  consul_ecs_image                    = var.consul_ecs_image
  log_group_name                      = var.log_group_name
  region                              = var.region
  consul_ca_cert_secret_arn           = aws_secretsmanager_secret.consul-server.arn
  consul_ca_cert_secret_key           = "ca_cert"
  consul_gossip_encryption_secret_arn = aws_secretsmanager_secret.consul-server.arn
  consul_gossip_encryption_secret_key = "gossip_encryption_key"
  consul_agent_token_secret_arn       = aws_secretsmanager_secret.consul-agent-token.arn
  consul_agent_token_secret_key       = "agent_token"
  app_container = {
    name      = "mesh-app"
    image     = "ghcr.io/lkysow/fake-service:v0.21.0"
    essential = true
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = var.log_group_name
        awslogs-region        = var.region
        awslogs-stream-prefix = "app"
      }
    }
    environment = [
      {
        name  = "NAME"
        value = "mesh-app"
      }
    ]
    # todo: Ideally this should be added by the module.
    dependsOn = [
      {
        containerName = "mesh-init"
        condition     = "SUCCESS"
      },
      {
        containerName = "sidecar-proxy"
        condition     = "HEALTHY"
      }
    ]
  }
  envoy_image = var.envoy_image
}

module "mesh-client" {
  source                              = "./modules/mesh-task"
  family                              = "mesh-client-hcp-test"
  retry_join_url                      = [hcp_consul_cluster.this.consul_private_endpoint_url]
  datacenter                          = jsondecode(base64decode(hcp_consul_cluster.this.consul_config_file))["datacenter"]
  execution_role_arn                  = aws_iam_role.mesh-app-execution.arn
  task_role_arn                       = aws_iam_role.mesh_app_task.arn
  consul_image                        = var.consul_image
  consul_ecs_image                    = var.consul_ecs_image
  log_group_name                      = var.log_group_name
  region                              = var.region
  consul_ca_cert_secret_arn           = aws_secretsmanager_secret.consul-server.arn
  consul_ca_cert_secret_key           = "ca_cert"
  consul_gossip_encryption_secret_arn = aws_secretsmanager_secret.consul-server.arn
  consul_gossip_encryption_secret_key = "gossip_encryption_key"
  consul_agent_token_secret_arn       = aws_secretsmanager_secret.consul-agent-token.arn
  consul_agent_token_secret_key       = "agent_token"
  port                                = "9090"
  upstreams                           = "mesh-app-hcp-test:1234"
  app_container = {
    name      = "mesh-client"
    image     = "ghcr.io/lkysow/fake-service:v0.21.0"
    essential = true
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = var.log_group_name
        awslogs-region        = var.region
        awslogs-stream-prefix = "mesh-client"
      }
    }
    environment = [
      {
        name  = "NAME"
        value = "mesh-client"
      },
      {
        name  = "UPSTREAM_URIS"
        value = "http://localhost:1234"
      }
    ]
    portMappings = [
      {
        containerPort = 9090
      }
    ]
    dependsOn = [
      {
        containerName = "mesh-init"
        condition     = "SUCCESS"
      }
    ]
  }
  envoy_image = var.envoy_image
}

module "consul-controller" {
  source = "./modules/controller"

  consul_agent_token_secret_arn     = aws_secretsmanager_secret.consul-agent-token.arn
  consul_bootstrap_token_secret_arn = aws_secretsmanager_secret.bootstrap-token.arn
  consul_ecs_image                  = var.consul_ecs_image
  region                            = var.region
  cloudwatch_log_group_name         = var.log_group_name
  ecs_cluster_name                  = var.ecs_cluster
  subnets                           = var.subnets
  consul_server_api_hostname        = hcp_consul_cluster.this.consul_private_endpoint_url
  consul_server_api_port            = 443
  consul_server_api_scheme          = "https"
  assign_public_ip                  = true
}

resource "aws_ecs_service" "mesh-client" {
  name            = "mesh-client-hcp-test"
  cluster         = var.ecs_cluster
  task_definition = module.mesh-client.task_definition_arn
  desired_count   = 1
  network_configuration {
    subnets          = var.subnets
    assign_public_ip = true
  }
  launch_type    = "FARGATE"
  propagate_tags = "TASK_DEFINITION"
  load_balancer {
    target_group_arn = aws_lb_target_group.mesh-client.arn
    container_name   = "mesh-client"
    container_port   = 9090
  }
  enable_execute_command = true
}

resource "aws_iam_role" "mesh_app_task" {
  name = "mesh-app-hcp-test"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
  # for discover-servers
  # todo: scope this down so it's only list and describe tasks.
  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonECS_FullAccess"]

  inline_policy {
    name = "exec"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel"
          ]
          Resource = "*"
        }
      ]
    })
  }
}

resource "aws_lb" "mesh-client" {
  name               = var.mesh_client_app_lb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.mesh-client-alb.id]
  subnets            = var.lb_subnets
}

resource "aws_security_group" "mesh-client-alb" {
  name   = "mesh-client-alb-hcp-test"
  vpc_id = var.vpc_id

  ingress {
    description = var.lb_ingress_security_group_rule_description
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.lb_ingress_security_group_rule_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# allow ingress from LB into ECS cluster.
resource "aws_security_group_rule" "example" {
  type                     = "ingress"
  from_port                = 9090
  to_port                  = 9090
  protocol                 = "tcp"
  security_group_id        = data.aws_security_group.default.id
  source_security_group_id = aws_security_group.mesh-client-alb.id
}

data "aws_security_group" "default" {
  vpc_id = var.vpc_id
  name   = "default"
}

resource "aws_lb_target_group" "mesh-client" {
  name                 = "mesh-client-alb-hcp-test"
  port                 = 9090
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 10
  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 30
    interval            = 60
  }
}

resource "aws_lb_listener" "mesh-client" {
  load_balancer_arn = aws_lb.mesh-client.arn
  port              = "9090"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mesh-client.arn
  }
}

resource "aws_iam_policy" "mesh-app-execution" {
  name        = "mesh-app-hcp-test"
  path        = "/ecs/"
  description = "mesh-app execution"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "${aws_secretsmanager_secret.consul-server.arn}",
        "${aws_secretsmanager_secret.consul-agent-token.arn}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "mesh-app-execution" {
  name = "mesh-app-execution-hcp-test"
  path = "/ecs/"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "mesh-app-execution" {
  role       = aws_iam_role.mesh-app-execution.id
  policy_arn = aws_iam_policy.mesh-app-execution.arn
}
