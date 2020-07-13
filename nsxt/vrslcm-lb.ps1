
$nsxurl = "https://$nsxmanager/policy/api/v1"
$nsxmanager = "nsxm.corp.local"

#------------------------------------

$T1GatewayName = "sfo-m01-lb01-t1-gw01" #Dedicated Tier-1 for Load Balancer
$LBName = "sfo-m01-lb01-t1-gw01"        #Load Balancer Name

$WSAPoolMemberIP1 = "192.169.11.61" #Workspace One Access pool member 1 IP Address
$WSAPoolMemberIP2 = "192.169.11.62" #Workspace One Access pool member 2 IP Address
$WSAPoolMemberIP3 = "192.169.11.63" #Workspace One Access pool member 3 IP Address
$WSAVIP ="192.168.11.60"    #Workspace One Access Virtual Server IP Address

$WSAPoolMemberName1 = "xreg-wsa01a"     #Workspace One Access pool member 1 Name
$WSAPoolMemberName2 = "xreg-wsa01b"     #Workspace One Access pool member 2 Name
$WSAPoolMemberName3 = "xreg-wsa01c"     #Workspace One Access pool member 3 Name


$VROPSPoolMemberIP1 = "192.168.11.31"   #VROps pool member 1 IP Address
$VROPSPoolMemberIP2 = "192.168.11.32"   #VROps pool member 2 IP Address
$VROPSPoolMemberIP3 = "192.168.11.33"   #VROps pool member 3 IP Address
$VROPSVIP = "192.168.11.30" #VROps Virtual Server IP address

$VROPSPoolMemberName1 = "xreg-vrops01a" #VROps pool member 1 Name
$VROPSPoolMemberName2 = "xreg-vrops01b" #VROps pool member 2 Name
$VROPSPoolMemberName3 = "xreg-vrops01c" #VROps pool member 3 Name

$VRAPoolMemberIP1 = "192.168.11.51" #VRA pool member 1 IP Address
$VRAPoolMemberIP2 = "192.168.11.52" #VRA pool member 2 IP Address
$VRAPoolMemberIP3 = "192.168.11.53" #VRA pool member 3 IP Address
$VRAVIP = "192.168.11.50"   #VRA Virtual Server IP Address

$VRAPoolMemberName1 = "xreg-vra01a" #VRA pool member 1 Name
$VRAPoolMemberName2 = "xreg-vra01b" #VRA pool member 2 Name
$VRAPoolMemberName3 = "xreg-vra01c" #VRA pool member 3 Name

$WSACertPath = "/infra/certificates/WSA-Certificate" #Path to imported WSA Certificate in NSX-T

#Set PS error preference to stop execution on error
$ErrorActionPreference = "Stop"

#Get credentials
$nsxuser = Read-Host "NSX Manager username"
$nsxpw = Read-Host -assecurestring "NSX Manager password"

#Manually create basic auth header to support older versions of PS
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($nsxpw)
$plaintext = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($nsxuser):$($plaintext)"))
$Headers = @{
    Authorization = "Basic $encodedCreds"
}

#Workaround for self-signed certificate. PS versions lower than 6 do not have -SKipCertificationCheck option in Invoke-WebRequest
#This will accept all certs for this session
    
$bCertWorkaround = $PSVersionTable.PSVersion.Major -lt 6

if ($bCertWorkaround) 
{
    Write-Host "Powershell version is " $PSVersionTable.PSVersion "using certificate trust workaround"

    Add-Type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@

[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
# Set Tls versions
$allProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $allProtocols

}
else{
    Write-Host "Powershell version is " $PSVersionTable.PSVersion "using -SkipCertificateCheck option for Invoke-WebRequest"
}





function RESTNSXCall{
    param(
        $uri,
        $method,
        $credentials,
        $body
    )
   
     try{
        if ($bCertWorkaround)
        {
            $response = Invoke-WebRequest -Uri $uri -Headers $Headers -Method $method -Body $body -ContentType "application/json" -ErrorAction Stop
            
        
        }
        else {
            $response = Invoke-WebRequest -Uri $uri -Headers $Headers -Method $method -Body $body -ContentType "application/json" -SkipCertificateCheck  -ErrorAction Stop
        }
        Write-Host "Status: " -NoNewline
        if(($response.StatusCode -eq 200) -or ($response.StatusCode -eq 201))
        {
            Write-Host $response.StatusCode -ForegroundColor green
        }
        else {
            Write-Host $response.StatusCode -ForegroundColor red
        }
    }
    catch [System.Net.WebException]{
        $res = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($res)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
    
        $responseBody = $reader.ReadToEnd()

        Write-Error "Server response: $responseBody"
}
}


#Create Load Balancer
$Body = @"
{
    "resource_type": "LBService",
    "enabled": true,
    "size":"SMALL",
    "connectivity_path": "/infra/tier-1s/$T1GatewayName"

}
"@

Write-Host "Creating Load Balancer......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-services/$LBName -Method Patch -Body $Body -credentials $nsxcreds

function ConfigWSA{

#Create WSA Monitor
$Body = @"
{
    "request_url": "/SAAS/API/1.0/REST/system/health/heartbeat",
    "request_method": "GET",
    "request_version": "HTTP_VERSION_1_1",
    "response_status_codes": [
      200
    ],
    "response_body": "ok",
    "resource_type": "LBHttpsMonitorProfile",
    "display_name": "wsa-https-monitor",
    "description": "Cross-Region Workspace ONE Access HTTPS Monitor",
    "monitor_port": 443,
    "interval": 3,
    "timeout": 10,
    "rise_count": 3,
    "fall_count": 3
}
"@


Write-Host "Creating WSA Monitor......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-monitor-profiles/wsa-https-monitor -Method Patch -Body $Body -credentials $nsxcreds

#Create WS LB Pool
$Body = @"
{
	"active_monitor_paths":[
		"/infra/lb-monitor-profiles/wsa-https-monitor"],
    "algorithm": "LEAST_CONNECTION",
    "snat_translation": {
		"type": "LBSnatAutoMap"
	},
	"members": [
        {
            "display_name": "$WSAPoolMemberName1",
            "ip_address": "$WSAPoolMemberIP1",
            "port": "443",
            "weight": "1"
        },
        {
            "display_name": "$WSAPoolMemberName2",
            "ip_address": "$WSAPoolMemberIP2",
            "port": "443",
            "weight": "1"
        },
        {
            "display_name": "$WSAPoolMemberName3",
            "ip_address": "$WSAPoolMemberIP3",
            "port": "443",
            "weight": "1"
        }
    ]
}
"@

Write-Host "Creating WSA Pool......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-pools/wsa-server-pool -Method Patch -Body $Body -credentials $nsxcreds


#Create Application Profile for WSA
$Body = @"
{
    "resource_type": "LBHttpProfile",
    "description": "Cross-Region Workspace ONE Access HTTP Application Profile",
    "request_header_size": "1024",
    "response_header_size": "4096",
    "response_timeout": "60",
    "http_redirect_to_https": "False"
}
"@

Write-Host "Creating WSA HTTP Profile......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-app-profiles/wsa-http-app-profile -Method Patch -Body $Body -credentials $nsxcreds

#Create Application Profile for WSA
$Body = @"
{
    "resource_type": "LBHttpProfile",
    "description": "Cross-Region Workspace ONE Access HTTP to HTTPS Redirect Application Profile",
    "request_header_size": "1024",
    "response_header_size": "4096",
    "response_timeout": "60",
    "http_redirect_to_https": "True"
}
"@

Write-Host "Creating WSA HTTPS Redirect Profile......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-app-profiles/wsa-http-app-profile-redirect -Method Patch -Body $Body -credentials $nsxcreds

$Body = @"
{
    "resource_type": "LBCookiePersistenceProfile",
    "description": "Cookie persistence profile",
    "cookie_name": "JSESSIONID",
    "cookie_mode": "REWRITE",
    "cookie_fallback": true,
    "cookie_garble": true,
    "persistence_shared": false
}
"@

Write-Host "Creating WSA Persistence Profile......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-persistence-profiles/wsa-persistence-profile -Method Patch -Body $Body -credentials $nsxcreds

#Create WSA Virtual Servers
$Body = @"
{
    "resource_type": "LBVirtualServer",
	"ip_address":"$WSAVIP",
	"ports": ["443"],
    "application_profile_path": "/infra/lb-app-profiles/wsa-http-app-profile",
    "lb_persistence_profile_path": "/infra/lb-persistence-profiles/wsa-persistence-profile",
    "lb_service_path": "/infra/lb-services/$LBName",
    "pool_path": "/infra/lb-pools/wsa-server-pool",
    "client_ssl_profile_binding": {
        "ssl_profile_path": "/infra/lb-client-ssl-profiles/default-balanced-client-ssl-profile",
        "default_certificate_path": "$WSACertPath",
        "client_auth": "IGNORE",
        "certificate_chain_depth": 3
      },
    "rules": [
    {
      "match_strategy": "ALL",
      "phase": "HTTP_REQUEST_REWRITE",
      "actions": [
        {
          "header_name": "Remote Port",
          "header_value": "`$_remote_port",
          "type": "LBHttpRequestHeaderRewriteAction"
        }
      ]
    }
    ]
}

"@

Write-Host "Creating WSA HTTPS Virtual Server......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-virtual-servers/wsa-https -Method Patch -Body $Body -credentials $nsxcreds

#Create WSA Virtual Servers
$Body = @"
{
    "resource_type": "LBVirtualServer",
    "description": "Cross-Region Workspace ONE Access Cluster HTTP to HTTPS Redirect",
	"ip_address":"$WSAVIP",
	"ports": ["80"],
    "application_profile_path": "/infra/lb-app-profiles/wsa-http-app-profile-redirect",
    "lb_service_path": "/infra/lb-services/$LBName"
}

"@

Write-Host "Creating WSA HTTP REdirect Virtual Server......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-virtual-servers/wsa-http-redirect -Method Patch -Body $Body -credentials $nsxcreds

}

function ConfigVROPS{


#Create vrOps Monitor
$Body = @"
{
    "request_url": "/suite-api/api/deployment/node/status?service=api&service=admin&service=ui",
    "request_method": "GET",
    "request_version": "HTTP_VERSION_1_1",
    "response_status_codes": [
      200,
      204,
      301
    ],
    "response_body": "ONLINE",
    "resource_type": "LBHttpsMonitorProfile",
    "display_name": "vrops-https-monitor",
    "description": "vRealize Operations Manager analytics cluster HTTPS monitor",
    "monitor_port": 443,
    "interval": 5,
    "timeout": 16,
    "rise_count": 3,
    "fall_count": 3
}
"@

Write-Host "Creating VROps Monitor......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-monitor-profiles/vrops-https-profile -Method Patch -Body $Body -credentials $nsxcreds

#Create VROps LB Pool
$Body = @"
{
    "description": "vRealize Operations Manager analytics cluster server pool",
	"active_monitor_paths":[
		"/infra/lb-monitor-profiles/vrops-https-profile"],
    "algorithm": "LEAST_CONNECTION",
	"members": [
        {
            "display_name": "$VROPSPoolMemberName1",
            "ip_address": "$VROPSPoolMemberIP1",
            "port": "443",
            "weight": "1"
        },
        {
            "display_name": "$VROPSPoolMemberName2",
            "ip_address": "$VROPSPoolMemberIP2",
            "port": "443",
            "weight": "1"
        },
        {
            "display_name": "$VROPSPoolMemberName3",
            "ip_address": "$VROPSPoolMemberIP3",
            "port": "443",
            "weight": "1"
        }
    ]
}
"@

Write-Host "Creating VROps Pool......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-pools/vrops-server-pool  -Method Patch -Body $Body -credentials $nsxcreds

#Create Application Profile for VROps
$Body = @"
{
    "resource_type": "LBFastTcpProfile",
    "description": "vRealize Operations Manager analytics cluster TCP application profile",
    "idle_timeout": "1800"
}
"@

Write-Host "Creating VROps TCP Application Profile......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-app-profiles/vrops-tcp-app-profile -Method Patch -Body $Body -credentials $nsxcreds

#Create Application Profile for VROps
$Body = @"
{
    "resource_type": "LBHttpProfile",
    "description": "vRealize Operations Manager analytics cluster HTTP to HTTPS Redirect application profile",
    "request_header_size": "1024",
    "response_header_size": "4096",
    "response_timeout": "60",
    "http_redirect_to_https": "True",
    "idle_timeout": "1800"
}
"@

Write-Host "Creating VROps HTTP Redirect Profile......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-app-profiles/vrops-http-app-profile-redirect -Method Patch -Body $Body -credentials $nsxcreds

$Body = @"
{
    "resource_type": "LBSourceIpPersistenceProfile",
    "description": "vRealize Operations Manager analytics cluster source IP persistence profile",
    "timeout":"1800"
}
"@

Write-Host "Creating VROps Persistence Profile......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-persistence-profiles/vrops-source-ip-persistence-profile -Method Patch -Body $Body -credentials $nsxcreds


#Create VROps Virtual Servers
$Body = @"
{
    "resource_type": "LBVirtualServer",
    "description": "vRealize Operations Manager analytics cluster UI",
	"ip_address":"$VROPSVIP",
	"ports": ["443"],
    "application_profile_path": "/infra/lb-app-profiles/vrops-tcp-app-profile",
    "lb_service_path": "/infra/lb-services/$LBName",
    "lb_persistence_profile_path":  "/infra/lb-persistence-profiles/vrops-source-ip-persistence-profile",
    "pool_path": "/infra/lb-pools/vrops-server-pool"
}

"@

Write-Host "Creating VROps HTTPS Virtual Server......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-virtual-servers/vrops-https -Method Patch -Body $Body -credentials $nsxcreds

#Create VROps Virtual Servers
$Body = @"
{
    "resource_type": "LBVirtualServer",
    "description": "vRealize Operations Manager analytics cluster HTTP to HTTPS Redirect",
	"ip_address":"$VROPSVIP",
	"ports": ["80"],
    "application_profile_path": "/infra/lb-app-profiles/vrops-http-app-profile-redirect",
    "lb_service_path": "/infra/lb-services/$LBName"
}

"@

Write-Host "Creating VROps HTTP Redirect Virtual Server......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-virtual-servers/vrops-http-redirect -Method Patch -Body $Body -credentials $nsxcreds

}

function ConfigVRA{
    
#Create vRA Monitor
$Body = @"
{
    "request_url": "/health",
    "request_method": "GET",
    "request_version": "HTTP_VERSION_1_1",
    "response_status_codes": [
      200
    ],
    "resource_type": "LBHttpMonitorProfile",
    "display_name": "vra-http-monitor",
    "description": "vRealize Automation HTTP Monitor",
    "monitor_port": 8008,
    "interval": 3,
    "timeout": 10,
    "rise_count": 3,
    "fall_count": 3
}
"@

Write-Host "Creating VRA Monitor......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-monitor-profiles/vra-http-monitor -Method Patch -Body $Body -credentials $nsxcreds


#Create vRA LB Pool
$Body = @"
{
	"active_monitor_paths":[
		"/infra/lb-monitor-profiles/vra-http-monitor"],
    "algorithm": "LEAST_CONNECTION",
    "snat_translation": {
		"type": "LBSnatAutoMap"
	},
	"members": [
        {
            "display_name": "$VRAPoolMemberName1",
            "ip_address": "$VRAPoolMemberIP1",
            "port": "443",
            "weight": "1"
        },
        {
            "display_name": "$VRAPoolMemberName2",
            "ip_address": "$VRAPoolMemberIP2",
            "port": "443",
            "weight": "1"
        },
        {
            "display_name": "$VRAPoolMemberName3",
            "ip_address": "$VRAPoolMemberIP3",
            "port": "443",
            "weight": "1"
        }
    ]
}
"@


Write-Host "Creating VRA Pool......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-pools/vra-server-pool  -Method Patch -Body $Body -credentials $nsxcreds

#Create Application Profile for vRA
$Body = @"
{
    "resource_type": "LBFastTcpProfile",
    "description": "vRealize Automation TCP Application Profile",
    "idle_timeout": "1800"
}
"@

Write-Host "Creating VRA TCP Profile......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-app-profiles/vra-tcp-app-profile -Method Patch -Body $Body -credentials $nsxcreds

#Create Application Profile for vRA redirect
$Body = @"
{
    "resource_type": "LBHttpProfile",
    "description": "vRealize Automation HTTP to HTTPS Redirect Application Profile",
    "request_header_size": "1024",
    "response_header_size": "4096",
    "response_timeout": "60",
    "http_redirect_to_https": "True",
    "idle_timeout": "1800",
    "x_forwarded_for":"INSERT"
}
"@

Write-Host "Creating VRA HTTP Redirect Profile......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-app-profiles/vra-http-app-profile-redirect -Method Patch -Body $Body -credentials $nsxcreds

#Create vRA Virtual Servers
$Body = @"
{
    "resource_type": "LBVirtualServer",
    "description": "vRealize Automation Cluster UI",
	"ip_address":"$VRAVIP",
	"ports": ["443"],
    "application_profile_path": "/infra/lb-app-profiles/vra-tcp-app-profile",
    "lb_service_path": "/infra/lb-services/$LBName",
    "pool_path": "/infra/lb-pools/vra-server-pool"
}
"@

Write-Host "Creating VRA Virtual Server......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-virtual-servers/vra-https -Method Patch -Body $Body -credentials $nsxcreds

#Create vRA Virtual Servers
$Body = @"
{
    "resource_type": "LBVirtualServer",
    "description": "vRealize Automation HTTP to HTTPS Redirect",
	"ip_address":"$VRAVIP",
	"ports": ["80"],
    "application_profile_path": "/infra/lb-app-profiles/vra-http-app-profile-redirect",
    "lb_service_path": "/infra/lb-services/$LBName"
}
"@

Write-Host "Creating VRA HTTP Redirect Virtual Server......." -NoNewLine
RESTNSXCall -uri $nsxurl/infra/lb-virtual-servers/vra-http-redirect -Method Patch -Body $Body -credentials $nsxcreds

}


ConfigWSA
ConfigVROPS
ConfigVRA