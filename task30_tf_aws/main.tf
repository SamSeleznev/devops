provider "aws" {
  region = "ap-northeast-2"
}

resource "aws_lb_target_group" "api_tg" {
  name        = "api-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "vpc-07b77778eb1d58bd1"

  health_check {
    path                = "/health"
    port                = 80
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 10
    matcher             = 404
  }
}

resource "aws_lb_target_group" "web_tg" {
  name        = "web-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "vpc-07b77778eb1d58bd1"
}

resource "aws_lb_target_group" "main_tg" {
  name        = "main-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = "vpc-07b77778eb1d58bd1"
}

resource "aws_lb" "alb" {
  name               = "alb-ecs"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["sg-07f211fbc16ce4156"]
  subnets = [
    "subnet-09896dd61f9fb170a",
    "subnet-02f8428e5efa460af",
  ]
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main_tg.arn
  }
}
resource "aws_lb_listener_rule" "api_rule" {
  listener_arn = aws_lb_listener.alb_listener.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_tg.arn
  }

  condition {
    host_header {
      values = ["api.semen.bootcamp.vok-works.com"]
    }
  }
}

resource "aws_lb_listener_rule" "web_rule" {
  listener_arn = aws_lb_listener.alb_listener.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }

  condition {
    host_header {
      values = ["web.semen.bootcamp.vok-works.com"]
    }
  }
}
# Зона Route53
data "aws_route53_zone" "main" {
  zone_id = "Z03831093LWJMAWR6JEHU"
}

# Запись для API
resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api"
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

# Запись для WEB  
resource "aws_route53_record" "web" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "web"
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}
resource "aws_ecs_service" "api_svc" {
  name            = "api_svc"
  cluster         = "ECS-EC2"
  task_definition = "api:20"
  desired_count   = 1
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.api_tg.arn
    container_name   = "api"
    container_port   = 80
  }

  network_configuration {
    assign_public_ip = true
    security_groups  = ["sg-03aba3eabcb91cd5a"]

    subnets = [
      "subnet-02f8428e5efa460af",
      "subnet-09896dd61f9fb170a",
    ]
  }
}
resource "aws_appautoscaling_target" "api_svc_target" {
  max_capacity       = 2
  min_capacity       = 1
  resource_id        = "service/ECS-EC2/${aws_ecs_service.api_svc.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "api_svc_scale_out" {
  name               = "scale-out-cpu"
  resource_id        = "service/ECS-EC2/${aws_ecs_service.api_svc.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }

  depends_on = [aws_appautoscaling_target.api_svc_target]
}

resource "aws_appautoscaling_policy" "api_svc_scale_in" {
  name               = "scale-in-cpu"
  resource_id        = "service/ECS-EC2/${aws_ecs_service.api_svc.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }

  depends_on = [aws_appautoscaling_target.api_svc_target]
}

resource "aws_cloudwatch_metric_alarm" "api_svc_scale_up" {
  alarm_name          = "api-cpu-utilization-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "70"

  dimensions = {
    ClusterName = "ECS-EC2"
    ServiceName = aws_ecs_service.api_svc.name
  }

  alarm_actions = [aws_appautoscaling_policy.api_svc_scale_out.arn]
}

resource "aws_cloudwatch_metric_alarm" "api_svc_scale_down" {
  alarm_name          = "api-cpu-utilization-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "30"

  dimensions = {
    ClusterName = "ECS-EC2"
    ServiceName = aws_ecs_service.api_svc.name
  }

  alarm_actions = [aws_appautoscaling_policy.api_svc_scale_in.arn]
}
resource "aws_ecs_service" "web_svc" {
  name            = "web_svc"
  cluster         = "ECS-EC2"
  task_definition = "web:5"
  desired_count   = 1
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.web_tg.arn
    container_name   = "web"
    container_port   = 80
  }

  network_configuration {
    assign_public_ip = true
    security_groups  = ["sg-03aba3eabcb91cd5a"]

    subnets = [
      "subnet-02f8428e5efa460af",
      "subnet-09896dd61f9fb170a",
    ]
  }
}
resource "aws_appautoscaling_target" "web_svc_target" {
  max_capacity       = 2
  min_capacity       = 1
  resource_id        = "service/ECS-EC2/${aws_ecs_service.web_svc.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "web_svc_scale_out" {
  name               = "scale-out-cpu"
  resource_id        = "service/ECS-EC2/${aws_ecs_service.web_svc.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }

  depends_on = [aws_appautoscaling_target.web_svc_target]
}

resource "aws_appautoscaling_policy" "web_svc_scale_in" {
  name               = "scale-in-cpu"
  resource_id        = "service/ECS-EC2/${aws_ecs_service.web_svc.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }

  depends_on = [aws_appautoscaling_target.web_svc_target]
}

resource "aws_cloudwatch_metric_alarm" "web_svc_scale_up" {
  alarm_name          = "web-cpu-utilization-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "70"

  dimensions = {
    ClusterName = "ECS-EC2"
    ServiceName = aws_ecs_service.web_svc.name
  }

  alarm_actions = [aws_appautoscaling_policy.web_svc_scale_out.arn]
}

resource "aws_cloudwatch_metric_alarm" "web_svc_scale_down" {
  alarm_name          = "web-cpu-utilization-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "30"

  dimensions = {
    ClusterName = "ECS-EC2"
    ServiceName = aws_ecs_service.web_svc.name
  }

  alarm_actions = [aws_appautoscaling_policy.web_svc_scale_in.arn]
}
