# TerraPerf Landing Page

Static "Coming Soon" landing page for https://terraperf.com

## Files

```
terraperf-landing/
├── index.html       # Main HTML page with waitlist form
├── privacy.html     # Privacy policy (GDPR compliant)
├── styles.css       # Styles (matches TerraPerf design)
├── favicon.svg      # TerraPerf favicon
├── deploy.sh        # Deployment script
├── README.md        # This file
├── api/             # Waitlist API
│   ├── waitlist_api.py    # FastAPI backend
│   └── requirements.txt   # Python dependencies
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
# Terminal 1: Start the waitlist API
cd api
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python waitlist_api.py  # Runs on http://localhost:8001

# Terminal 2: Start the static site
python -m http.server 8083

# Open http://localhost:8083
```

## Waitlist Feature

The landing page includes an email signup form for the waiting list:

- **Form validation**: Email format and consent checkbox required
- **GDPR compliance**: Privacy policy link and explicit consent
- **Local storage**: Emails saved to `api/data/waitlist.json` during development
- **Production**: Will use DynamoDB for storage

### Privacy Policy

The privacy policy (`privacy.html`) complies with GDPR and includes:
- Data controller information (Sofrasorb)
- Types of data collected
- Legal basis for processing
- User rights (access, rectification, erasure, etc.)
- CNIL contact information
