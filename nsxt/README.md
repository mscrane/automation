# NSX-T Load Balancer Config for vRealize Suite

This Powershell script will create the dedicated load balancer and all monitors, profiles, and virtual servers for the vRealize components per the VVD 6.x documentation: https://docs.vmware.com/en/VMware-Validated-Design/6.0/sddc-deployment-of-cloud-operations-and-automation-in-the-first-region/GUID-07AD9C42-CB80-4064-8B68-E47D08BD6967.html


## Prerequisites:

1) A dedicated Tier 1 Gateway created in NSX-T
2) A workspace One Access certificate imported into NSX-T manager

## Usage:

Open the script in a text editor and modify the variables section to match your environment(NSX Manager, IP Addresses, Virtual Server names, etc.). Run the script and enter the NSX Manager credentials. NSX objects are created using the policy API PATCH method. The script can be re-run any number of times to correct any errors.

## Notes:

This has been tested on PowerShell versions 5, 6, and 7. 

