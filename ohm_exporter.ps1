<#    
    .SYNOPSIS
    Collects stats from the tool "Open Hardware Monitore" and creates a prometheus ready metric file

    .DESCRIPTION
        Scripts starts OpenHardwareMonitor by itself, when the OpenHardwareMonitor-files are located in a folder named "OpenHardwareMonitor" next to the powershell script (if the ohm_exporter was not started as a service at least).
		When you run it the first time, check if all metrics are found - use parameter "-check" for that. If the numbers differ from each other, there is a problem in the script =(
		
		# Configure OpenHardwareMonitor
			Options -> Enable first 4 Options
		
		# Register as a service
			nssm install <service name> ohm_exporter.exe
		# Remove service
			nssm remove ohm_exporter
			
		# Build a new .exe
		    PS>Install-Module ps2exe
		    PS>Invoke-ps2exe .\ohm_exporter.ps1 .\ohm_exporter.exe
  
    .COMPONENT
        Needs OpenHardwareMonitoring Tool and windows_exporter (with textfile_inputs enabled)
		
	.INPUTS
		None
		
	.OUTPUTS
		Creates a ohm_exporter.prom file with metrics ready to collect by a prometheus

    .PARAMETER promfolder
        Define Prometheus exporter folder path, if not default path (C:\Program Files\windows_exporter\textfile_inputs)

    .PARAMETER check
        Counts the number of found OpenHardwareMonitor parameter and compares it with the created prometheus metrics. If they are not the same, the scripts needs adaptation.

    .EXAMPLE
        PS>./ohm_exporter.ps1

    .EXAMPLE
        PS>./ohm_exporter.ps1 -check

    .EXAMPLE
        PS>./ohm_exporter.ps1 -promfolder "C:\Program Files\windows_exporter\textfile_inputs"

    .NOTES
        Version:        1.0
        Author:         Ormiach
        Creation Date:  2021

    .LINK
		*) ohm_exporter: https://github.com/Ormiach/ohm_exporter
		*) windows_exporter: https://github.com/prometheus-community/windows_exporter
		*) Open Hardware Monitoring:  https://openhardwaremonitor.org/downloads/
		*) Nssm: https://nssm.cc/
		
		
#>
#####################################################################################################



########################
# Parameter
########################
param(
    [Parameter(Mandatory=$False)][string]$promfolder="C:\Program Files\windows_exporter\textfile_inputs",
    [Parameter(Mandatory=$False)][switch]$check
)

########################
# Do some checks
########################
# Is the script running with administrator privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (!$currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { 
	Write-Host "Needs administrator privileges to run  -> Exit"
	break
}

# Check if Prometheus-exporter folder exists
if (-Not (Test-Path $promfolder) ) { 
    throw "Folder does not exists: $promfolder -> Exit"
}

# Check if OpenHardwareMonitor ist running
if ( -Not (Get-Process OpenHardwareMonitor -ErrorAction SilentlyContinue)) {  
    Start-Process -FilePath "./OpenHardwareMonitor/OpenHardwareMonitor.exe" -WindowStyle Hidden
    Start-Sleep -s 2
    if ( -Not (Get-Process OpenHardwareMonitor -ErrorAction SilentlyContinue)) {
        throw "OpenHardwareMonitor not running -> EXIT"
    }
}

########################
# Define Filename
########################
$filename = "ohm_exporter.prom"
$file = $promfolder+"/"+$filename




while($true)
{
	########################
	# Lets do it
	########################

	$ohm_query = get-wmiobject -namespace "root/OpenHardwareMonitor" -Class Sensor #| Select-Object #-Property Name,__CLASS,Parent,w,SensorType,Identifier,Index,Value
	$ohm_query = $ohm_query | Sort-Object -Property Name,Identifier -Unique
	$promhash  = @{}
	$promhash_counter = 0
	$checkitems = 0
	$checkmetrics = 0



	#####
	# Open promfile
	#####
	New-Item -Path "." -Name $filename -ItemType File -ErrorAction stop -Force | Out-Null
	 

	foreach($element in $ohm_query)
	{
		$need_calc = 1
		$metricname = ""
		$parentname = ""
		$addparent = ""
		$checkitems = $checkitems + 1
		
		# Get parent information
		$match = "Identifier='"+($element.Parent)+"'"
		$parent = get-wmiobject -namespace "root/OpenHardwareMonitor" -Class Hardware -filter "$match"
		if ($parent.Parent -And $parent.Parent -ne "") { 
			$parentname = $parent.Parent.replace("/","").ToLower().replace("\s","")
			$addparent = $parentname+"_" 
		}
		if ($element.Parent -And $element.Parent -Match "lpc") { $addparent = $addparent+"lpc_"	} 
		
		$metricname_addon = ""
		$metricname_end = ""
		
		# Metric stuff
		if ($element.Identifier.ToLower() -Match "gpu") { $metricname_addon = "gpu_" }
		elseif ($element.Identifier.ToLower() -Match "cpu") { $metricname_addon = "cpu_" }
		# Disk
		elseif ( $element.Identifier.ToLower() -Match "hdd" ) { 
			$addparent = "disk_"
			$metricname_end = "bytes"
			if ($element.Name -And $element.Name -eq "Total Bytes Written") { 
				$metricname_addon = $metricname_addon+"written_" 
				$metricname_end = "bytes"
                $need_calc = 1024*1024*1024
			}
			elseif ($element.Name -And $element.Name -eq "Write Amplification") { 
				$metricname_addon = $metricname_addon+"write_amplification_"
				$metricname_end = "total"
			}
			elseif ($element.Name -And $element.Name -eq "Remaining Life") { 
				$metricname_addon = $metricname_addon+"remaining_life_"
				$metricname_end = "percent"
			}
		}
		# Memory
		if ( $element.Identifier.ToLower() -Match "ram" -Or $element.Name.ToLower() -Match "memory" -Or $element.Identifier.ToLower() -Match "smalldata") { 
			$metricname_addon = $metricname_addon + "memory_"
			$metricname_end = "bytes"
			if ( $element.Name.ToLower() -Match "available" -Or $element.Name.ToLower() -Match "free") { $metricname_addon = $metricname_addon + "free_" } 
			if ( $element.Name.ToLower() -Match "used" ) { 
                $metricname_addon = $metricname_addon + "used_" 
                $need_calc = 1024*1024*1024
            } 
			if ( $element.Name.ToLower() -Match "total" ) { 
                $metricname_addon = $metricname_addon + "total_"
                $need_calc = 1024*1024*1024
            } 
		}
		
		# Metric units
		if ( $element.Identifier.ToLower() -Match "fan" ) { $metricname_end = "fan_rpm" }
		if ( $element.Identifier.ToLower() -Match "control" ) { 
			if ($element.Name.ToLower() -Match "fan") { $metricname_addon = $metricname_addon+"fan_" }
			$metricname_end = "percent" 
			# Rename nvidia fans....
			$element.Name = $element.Name.replace("Control ","")
		}
		if ( $element.Identifier.ToLower() -Match "throughput" ) {
			$metricname_addon = $metricname_addon+"throughput_" 
			$metricname_end = "bytes_per_seconds"
			$need_calc = 1024*1024
		}
		if ( $element.Identifier.ToLower() -Match "power" ) {$metricname_end = "power_watts" }
		if ( $element.SensorType.ToLower() -Match "voltage" ) { $metricname_end = "volts" }
		if ( $element.SensorType.ToLower() -Match "temperature" ) {$metricname_end = "temperature_celsius" }
		if ( $element.SensorType.ToLower() -Match "clock" ) {$metricname_end = "clock_mhz" }
		if ( $element.SensorType.ToLower() -Match "load" ) {$metricname_end = "load_percent" }
		
		
		# Calculate units to bytes
		if ($metricname_end -Match "bytes" -And $need_calc -Eq 1) { $need_calc = 1024 }
		$metricname = "ohm_"+$addparent+$metricname_addon+$metricname_end

		######
		# Write metric to prometheus-hash
		######
		if ($promhash.$metricname.Count -Eq 0 ) { 
			$promhash[$metricname] = @{} 
			$promhash[$metricname]["metric_help"] = $metricname+" "+ $metricname
			$promhash[$metricname]["metric_type"] = $metricname+" "+ "gauge"
		}
		$promhash[$metricname][$promhash_counter] = @{} 
		$promhash[$metricname][$promhash_counter]['parent_identifier'] = $element.Parent
		$promhash[$metricname][$promhash_counter]['parent_name'] = $parent.Name
		$promhash[$metricname][$promhash_counter]['parent_device'] = $parentname
		$promhash[$metricname][$promhash_counter]['identifier'] = $element.Identifier
		$promhash[$metricname][$promhash_counter]['device'] = $parent.HardwareType
		$promhash[$metricname][$promhash_counter]['name'] = $element.Name
		$promhash[$metricname][$promhash_counter]['index'] = $element.Index
		$promhash[$metricname][$promhash_counter]['value'] = ($need_calc * $element.Value)
		$promhash_counter = $promhash_counter +1
	}


	##########
	# Create prometheus file output
	##########
	$last_metricname = ""
	foreach($metricname in $promhash.keys) {
		if ($last_metricname -Ne $metricname) { 
			Add-Content $filename ("")
			Add-Content $filename ("# HELP "+$promhash[$metricname].metric_help)
			Add-Content $filename ("# TYPE "+$promhash[$metricname].metric_type)
		}
		foreach($metricnumber in $promhash[$metricname].keys) {
			$metric = $metricname+"{"
			if ($promhash[$metricname][$metricnumber]['name'] -Match "\w+") {
				$checkmetrics = $checkmetrics + 1
				foreach ($key in $promhash[$metricname][$metricnumber].keys) { 
					if ($key -Eq "value" -Or $promhash[$metricname][$metricnumber][$key] -Eq "") { continue }
					$metric = $metric+$key+'="'+$promhash[$metricname][$metricnumber][$key]+'",'
				}
				$metric = $metric.Substring(0,$metric.Length-1)
				Add-Content $filename ( $metric+"} "+$promhash[$metricname][$metricnumber]['value'] )
			}
		}
	}

	# Move file to prometheus folder
	Move-Item -Path $filename -Destination $file -force


	if ($check) { 
		Write-Host ("OpenHardwareMonitor-Items found: "+$checkitems)
		Write-Host ("Prometheus Metrics created:      "+$checkmetrics)	
	}
	
	
	Start-Sleep -s 25
}

