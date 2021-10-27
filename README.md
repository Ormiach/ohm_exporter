# Table of contents
* [General Info](#general-info)
* [Setup](#setup)
* [Usage](#usage)
* [Improve Script](#imrpove-script)

# General info
"ohm_exporter" collects stats via "Open Hardware Monitor" and creates a prometheus readable metric file.

# Setup


### Download ohm_exporter.exe
Download ohm_exporter.exe from here: 
* https://github.com/Ormiach/ohm_exporter

### Download & Configure OpenHardwareMonitor
For ohm_exporter to work, it needs the tool "Open Hardware Monitor", which you can download from here: 
* https://openhardwaremonitor.org/

Put all the files into a folder called "Open Hardware Monitor" next to the ohm_exporter.exe.
Change the following options in "Open Hardware Monitor": 
* Options -> Enable first 4 Options

### Download windows_exporter.exe
Prometheus collect the data create via windows_exporter. Download the windows_exporter here: 
* https://github.com/prometheus-community/windows_exporter
You need to start windows_exporter with "textfile collector" enabled.

### Download nssm.exe
If you like to install the ohm_exporter as a service you can do this with "nssm". You get the exe here: 
* https://nssm.cc/

### Register ohm_exporter as a service
```
nssm install ohm_exporter ohm_exporter.exe
```

### Remove ohm_exporter service
```
nssm remove ohm_exporter
```

# Improve Script

### Build a new .exe
```
PS>Install-Module ps2exe
PS>Invoke-ps2exe .\ohm_exporter.ps1 .\ohm_exporter.exe
```