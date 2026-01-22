# TerraPerf Landing Page

Static "Coming Soon" landing page for https://terraperf.com

## Files

```
terraperf-landing/
├── index.html       # Main HTML page
├── styles.css       # Styles (matches TerraPerf design)
├── favicon.svg      # TerraPerf favicon
├── deploy.sh        # Deployment script
├── README.md        # This file
└── terraform/       # Infrastructure as Code
    ├── main.tf      # S3, CloudFront, ACM
    └── variables.tf # Configuration
```

## Deployment

### Prerequisites

1. AWS CLI configured with `terraperf-workloads-prod` profile
2. Terraform >= 1.0
3. Domain `terraperf.com` managed in Route53

### First-time Setup (Infrastructure)

```bash
# Login to AWS
aws sso login --profile terraperf-workloads-prod

# Initialize and apply Terraform
cd terraform
terraform init
terraform plan
terraform apply

# Note: ACM certificate requires DNS validation
# Add the CNAME records shown in terraform output to Route53
```

### Deploy Static Files

```bash
./deploy.sh
```

## DNS Configuration

After Terraform creates the ACM certificate, add DNS records to Route53:

1. **ACM Validation CNAME** - Required for SSL certificate
2. **A Record** - Point `terraperf.com` to CloudFront distribution
3. **A Record** - Point `www.terraperf.com` to CloudFront distribution

## Local Preview

```bash
# Simple HTTP server
python -m http.server 8080

# Open http://localhost:8080
```
