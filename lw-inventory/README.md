# Usage
## Compiling
```go build ```

# AWS

Log into the aws CLI before running the inventory app

Basic usage

 ```./lw-inventory aws```

 Using a profile (sso profile works as well)

 ```./lw-inventory aws --profile myprofile```

 Specifying a region

 ```./lw-inventory aws --region us-east-1```

 Show debug output (useful to see more details)

 ```./lw-inventory aws -d ```

# GCP

Log into the gcloud CLI before running the inventory app

Basic usage

```./lw-inventory gcp```

List of projects to ignore, comma separated

```./lw-inventory gcp --projects-to-ignore <projets to ignore>```

Use a credentials JSON file

```./lw-inventory gcp --credentials <path to JSON file>```

Show debug output (useful to see more details)

```./lw-inventory gcp -d ```

# Azure

Log into the az CLI before running the inventory app

Basic usage

```./lw-inventory azure```

List of subscriptions to ignore, comma separated

```./lw-inventory azure --ignore-subscriptions <your subscription ID or name>```

Show debug output (useful to see more details)

```./lw-inventory azure -d ```
