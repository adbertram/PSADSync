[![Build status](https://ci.appveyor.com/api/projects/status/xccbsyl4ihl9gubf?svg=true)](https://ci.appveyor.com/project/adbertram/pspostman)

## The PowerShell Active Directory Sync Tool

The purpose of the PowerShell Active Directory Sync Tool is to consume _any_ CSV with user accounts (one per row) with _any_ fields and successfully match each row to an Active Directory user account. Once matched, the tool will sync any field in the CSV to the user account given all fields have been mapped correctly.

This module is still under development and testing so please be careful if running in production! Confirmations have been added to cut down on unexpected changes but this tool can make _major_ changes to your AD environment in no time flat!