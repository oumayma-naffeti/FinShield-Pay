# Cle de partition = marchand, cle de tri = reference de commande.
# Isolation multi-marchands (EF-06) et idempotence par ecriture
# conditionnelle sur (merchant_id, order_ref) (section 5.1).
resource "aws_dynamodb_table" "transactions" {
  name         = "${var.project}-transactions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "merchant_id"
  range_key    = "order_ref"

  attribute {
    name = "merchant_id"
    type = "S"
  }

  attribute {
    name = "order_ref"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "${var.project}-transactions" }
}