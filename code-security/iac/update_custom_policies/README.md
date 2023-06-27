# Update rego package names for Opal custom policies

## Overview

As part of improvements to Lacework's Opal engine for Infrastructure-As-Code policies; Lacework has renamed some package in the library of rego code provide in Opal.  
Where previously functions were available in the `lacework` package and were available via `import data.lacework`, they are now in a `iac` package which is available via `import data.lacework.iac`  

Some example changes:
`import data.lacework` → `import data.lacework.iac`
`import data.k8s` → `import data.lacework.iac.k8s`
`lacework.resources("aws_instance")` → `iac.resources("aws_instance")`
`k8s.resources_with_pod_templates[_]` → (unchanged)

If you currently maintain your own custom policies for IaC you may now see errors where your policy code refers to the previous package schema.  
The provided script updates your policy code to use the current package names.

## update_policies_directory.sh

### Pre-requisites
* You should be at a workstation where you can make changes to your custom policy code

### Usage
`./update_policies_directory.sh [policy_directory]`  
e.g. `./update_policies_directory.sh policies/opal`

### Step-by-step
* In git (or your version control) ensure that your working copy of your IaC policies has no outstanding changes.
* Run `./update_policies_directory.sh [policy_directory]`
* Use `git diff` (or the diff function of your version control) to review the changes to your code.
  * Some simpler Opal policies will not reference the affected packages and will not receive any changes.
* Ensure your Lacework CLI has the latest version of Opal by running `lacework iac download install --name lacework-opal-releases --reinstall`
* Run `lacework iac policy test -d [policy_directory]` to test the changes to your policy code.
* If you are happy with the code changes and the policy tests; commit the changes to version control.
* If you manually upload your custom policies, run `lacework iac policy upload [policy_directory]` to upload your new code.
  * If you have a pipeline to upload policies when the code changes, ensure your pipeline runs.