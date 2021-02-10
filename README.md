# caffeine
Powershell based setup engine used in course environment deployments @ Cornerstone Group AB.

The engine accepts files of the extended .ini file format developed @ Cornerstone Group.
Please see the parser (https://github.com/Adicitus/common/blob/master/source/Parse-ConfigFile.ps1) for format details.

The module contains 2 Cmdlets:
- Start-Caffeine: Starts a single run through of the caffeine engine. If no config file (.ini) is provided, Caffeine will attempt to select one.
- Install-Caffeine: Creates a scheduled task to start caffeine each time the computer boots.

The first time that the engine is run it will attempt to create registry key (HKLM\SOFTWARE\CAFSetup) to track it's internal state across reboots.

## Task Sequences 
Task sequences are a set of steps that the engine should process sequentially.

These are defined in native Powershell script files as an collection (array) of hashtables.

Each hashtable defines a step and must contain the following fields:
- Name: A short name that describes the step.
- Caption: A longer description of what the step does.
- Block: A scriptblock to be executed (this defines the logic of the step).

A default Task Sequence is available in the .assets folder: in the folder default.ts, look at default.ts.ps1.

This is built on the old "Collect, Analyze, Fix" setup (CAFSetup) for "Microsoft Official Courseware" environments, and the step there reflect this.

## Compatibility
Caffeine was originally built to target PowerShell V2 and above, however it is best to assume that at least PowerShell V3 is required.

## How to build this module
This module is set up to be compiled using the PSBuildModule:
https://github.com/Adicitus/ps-build-module
