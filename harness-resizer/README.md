# Harness Resizer Bot
This script:
- Consumes recommendations from the Harness recommendation API
- Prompts the user to review these recommendations, and either accept them or propose their own.
- Generates PRs based on these recommendations, including links to the Harness dashboard.
- Deduplicates PRs through clever hashing of recommendation identifiers.

## Setup
To set this up, you will need two things:

1. A GitHub personal access token ([guide](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)), that has been authorized to access Lacework ([guide](https://docs.github.com/en/enterprise-cloud@latest/authentication/authenticating-with-saml-single-sign-on/authorizing-a-personal-access-token-for-use-with-saml-single-sign-on)).

2. A Harness API token ([guide](https://docs.harness.io/article/smloyragsm-api-keys)).

You can then run the CLI as follows:

```
GITHUB_TOKEN="XXXXXXXXXXXXXXXX" \
HARNESS_API_KEY="XXXXXXXXXXXXXXXX" \
./main.py generate_prs_interactive
```

## TODO 
- [ ] Add links to relevant Grafana/Honeycomb dashboards to the PR message.
- [ ] Add support for multiple container recommendations.
- [ ] Deploy to a GitHub action.
