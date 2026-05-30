#!/usr/bin/env bash
# Allow browsers to load product images from S3 (products/* prefix only).
# Run once on EC2 (or any machine with AWS CLI + credentials for the account).
set -euo pipefail

BUCKET="${AWS_S3_BUCKET:-gotokart-product-images-035379289330-us-east-1-an}"

echo "→ Updating public access block on s3://${BUCKET} ..."
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false

echo "→ Applying bucket policy (anonymous GetObject on products/*) ..."
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadProductImages",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::${BUCKET}/products/*"
  }]
}
EOF
)"

echo "✅ S3 product images are now publicly readable at:"
echo "   https://${BUCKET}.s3.us-east-1.amazonaws.com/products/<slug>.jpg"
