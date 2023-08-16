# Удаляем метрики и политики автомасштабирования
resource "aws_cloudwatch_metric_alarm" "api_svc_scale_up" {
  count = 0 
}

resource "aws_cloudwatch_metric_alarm" "api_svc_scale_down" {
  count = 0
}

resource "aws_cloudwatch_metric_alarm" "web_svc_scale_up" {
  count = 0
}

resource "aws_cloudwatch_metric_alarm" "web_svc_scale_down" {
  count = 0  
}

resource "aws_appautoscaling_policy" "api_svc_scale_out" {
  count = 0
}

resource "aws_appautoscaling_policy" "api_svc_scale_in" {
  count = 0  
}

resource "aws_appautoscaling_policy" "web_svc_scale_out" {
  count = 0
}

resource "aws_appautoscaling_policy" "web_svc_scale_in" {
  count = 0
}

# Удаляем цели автомасштабирования
resource "aws_appautoscaling_target" "api_svc_target" {
  count = 0
}

resource "aws_appautoscaling_target" "web_svc_target" {
  count = 0
}

# Удаляем сервисы ECS
resource "aws_ecs_service" "api_svc" {
  count = 0
}

resource "aws_ecs_service" "web_svc" {
  count = 0  
}

# Удаляем записи в Route53
resource "aws_route53_record" "api" {
  count = 0
}

resource "aws_route53_record" "web" {
  count = 0 
}

# Удаляем листенер и правила ALB
resource "aws_lb_listener" "alb_listener" {
  count = 0
}

resource "aws_lb_listener_rule" "api_rule" {
  count = 0
}

resource "aws_lb_listener_rule" "web_rule" {
  count = 0
}

# Удаляем ALB
resource "aws_lb" "alb" {
  count = 0
}

# Удаляем target group
resource "aws_lb_target_group" "api_tg" {
  count = 0
}

resource "aws_lb_target_group" "web_tg" {
  count = 0
}

resource "aws_lb_target_group" "main_tg" {
  count = 0
}

# Удаляем provider 
provider "aws" {
  region = "ap-northeast-2"
}