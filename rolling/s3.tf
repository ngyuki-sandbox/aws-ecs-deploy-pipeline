////////////////////////////////////////////////////////////////////////////////
/// S3

resource "aws_s3_bucket" "code" {
  bucket        = "${var.tag}-code"
  acl           = "private"
  force_destroy = true
}
