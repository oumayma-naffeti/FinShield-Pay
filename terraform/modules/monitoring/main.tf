data "aws_s3_bucket" "trail" {
  bucket = var.trail_bucket_name
}

# ---------- Journal d'audit : CloudTrail -> CloudWatch Logs ----------

resource "aws_cloudwatch_log_group" "trail" {
  name              = "/${var.project}/cloudtrail"
  retention_in_days = 7
}

resource "aws_cloudtrail" "main" {
  name                          = "${var.project}-trail"
  s3_bucket_name                = data.aws_s3_bucket.trail.id
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = var.cloudtrail_role_arn
  include_global_service_events = true
}

# ---------- Alerte : SNS + abonnement e-mail ----------

resource "aws_sns_topic" "security" {
  name = "${var.project}-security-alerts"
}

# L'e-mail n'est envoye qu'apres confirmation de l'abonnement par le destinataire
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.security.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------- Detection 1 : actions IAM sensibles (CloudTrail) ----------

resource "aws_cloudwatch_log_metric_filter" "iam_changes" {
  name           = "${var.project}-iam-sensitive-actions"
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = "{ ($.eventSource = \"iam.amazonaws.com\") && (($.eventName = \"CreateUser\") || ($.eventName = \"DeleteUser\") || ($.eventName = \"AttachRolePolicy\") || ($.eventName = \"PutRolePolicy\") || ($.eventName = \"CreateAccessKey\")) }"

  metric_transformation {
    name      = "IamSensitiveActions"
    namespace = "${var.project}/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "iam_changes" {
  alarm_name          = "${var.project}-iam-sensitive-actions"
  namespace           = "${var.project}/Security"
  metric_name         = "IamSensitiveActions"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security.arn]
}

# ---------- Detection 2 : requetes bloquees par le WAF ----------

resource "aws_cloudwatch_metric_alarm" "waf_blocked" {
  alarm_name          = "${var.project}-waf-blocked-requests"
  namespace           = "AWS/WAFV2"
  metric_name         = "BlockedRequests"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security.arn]

  dimensions = {
    WebACL = var.web_acl_name
    Rule   = "ALL"
    Region = var.region
  }
}
# ---------- Detection 3 : acces refuses ou erreurs sur l'API ----------
# Le champ "status" est ecrit entre guillemets dans les journaux : on compare des chaines.

resource "aws_cloudwatch_log_metric_filter" "api_denied" {
  name           = "${var.project}-api-denied"
  log_group_name = var.apigw_log_group_name
  pattern        = "{ ($.status = \"401\") || ($.status = \"403\") }"

  metric_transformation {
    name      = "ApiDeniedRequests"
    namespace = "${var.project}/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "api_denied" {
  alarm_name          = "${var.project}-api-denied-requests"
  namespace           = "${var.project}/Security"
  metric_name         = "ApiDeniedRequests"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security.arn]
}

resource "aws_cloudwatch_log_metric_filter" "api_errors" {
  name           = "${var.project}-api-5xx"
  log_group_name = var.apigw_log_group_name
  pattern        = "{ $.status = \"5*\" }"

  metric_transformation {
    name      = "ApiServerErrors"
    namespace = "${var.project}/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "api_errors" {
  alarm_name          = "${var.project}-api-5xx"
  namespace           = "${var.project}/Security"
  metric_name         = "ApiServerErrors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.security.arn]
}
