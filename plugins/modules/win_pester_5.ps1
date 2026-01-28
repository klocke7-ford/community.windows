#!powershell

# Copyright: (c) 2026, Ford Motor Company (@klocke7-ford) <klocke7-ford@ford.com>
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic

# Variables for Pester 5 module
# All Variables available:  https://pester.dev/docs/usage/Configuration

# Variables pulled from Pester for use in this module:
# Run.path str Default: @('.') The path(s) to the folder(s) or file(s) containing the tests to run.
# Run.ExcludePath str Default: @() The path(s) to the folder(s) or file(s) to exclude from the test run.
# Run.TestParameters dict Default: @{} A hashtable of parameters to pass to the tests.
#
# Filter.Tag str Default: @() The tag(s) to include in the test run.
# Filter.ExcludeTag	str Default: @() The tag(s) to exclude from the test run.
#
# TestResult.Enabled bool Default: $false.  If $true, enables saving test results to a file.
# TestResult.OutputFormat str Default: 'NUnitXML' The format of the test result output. Valid values are 'NUnitXML', 'JUnitXML', 'NUnit2.5', 'NUnit3'.
# TestResult.OutputPath str Default: 'testResults.xml' The file path to save the test result output.
# TestResult.OutputEncoding str Default: 'utf8' The encoding of the test result output file.
#
# Output.Verbosity str Default: 'Normal' The verbosity level of the output. Valid values are 'None', 'Normal', 'Detailed', 'Diagnostic'.

# Unique Variables for this module:
# required_version str The specific version of Pester required to run the tests.
#   The version must be in the format '5.#.#'.  Example: 5.6.1
# minimum_version str Default: '5.0.0' The minimum version of Pester required to run the tests.
#   The version must be in the format '5.#.#'.  Example: 5.6.1
# passThruDepth int Default: 2 The depth to which the test results object is returned. Valid values are 2, 3, 4, 5, 6.
#   Higher values provide more detail but can result in very large outputs.  Level 7 and above are not supported due to possible circular references causing looping error.

$spec = @{
  options            = @{
    path                 = @{type = 'str'; required = $true}
    path_exclude         = @{type = 'str'}
    tags_include         = @{type = "list"; elements = "str"}
    tags_exclude         = @{type = "list"; elements = "str"}
    test_parameters      = @{type = "dict"}
    test_results_enabled = @{type = "bool"; default = $false}
    output_file          = @{type = "str"; default = "testResults.xml"}
    output_format        = @{type = "str"; default = "NUnitXML"}
    output_encoding      = @{type = "str"; default = "utf8"; }
    required_version     = @{type = "str"; }
    minimum_version      = @{type = "str"; default = "5.0.0"}
    pass_thru_depth      = @{type = "int"; default = 2; choices = 2, 3, 4, 5, 6}
  }
  mutually_exclusive = @(
    , @("required_version", "minimum_version")
  )
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$path = $module.Params.path
$path_exclude = $module.Params.path_exclude
$tags_include = $module.Params.tags_include
$tags_exclude = $module.Params.tags_exclude
$test_parameters = $module.Params.test_parameters
$test_results_enabled = $module.Params.test_results_enabled
$output_file = $module.Params.output_file
$output_format = $module.Params.output_format
$output_encoding = $module.Params.output_encoding
$required_version = $module.Params.required_version
$minimum_version = $module.Params.minimum_version
$pass_thru_depth = $module.Params.pass_thru_depth

# Validate version format
try {
  if ($required_version) {
    $required_version = [version]$required_version
  } else {
    $minimum_version = [version]$minimum_version
  }
} catch {
  if ($required_version) {
    $version = $required_version
  } else {
    $version = $minimum_version
  }
  $module.FailJson("Value '$version' for parameter 'required_version/minimum_version' is not a valid version format.  Version must be in the format '5.#.#'.  Example: 5.6.1")
}

# Make sure the path to the test(s) are real
if (-not (Test-Path $path)) {
  $module.FailJson("Cannot find file or directory: '$path' as it does not exist")
}

# Find and import the required version or the minimum version Pester module; if available
if (-not (Get-Module -Name 'Pester' -ErrorAction SilentlyContinue)) {
  if (Get-Module -Name 'Pester' -ListAvailable -ErrorAction SilentlyContinue) {
    $moduleVersionAvailable = Get-Module 'Pester' -ListAvailable
    $moduleVersionAvailableString = "No Pester modules found"
    if ($moduleVersionAvailable.Count -gt 0) {
      $moduleVersionAvailableString = ""
      Get-Module 'Pester' -ListAvailable | Select-Object Name, Version | ForEach-Object {
        $moduleVersionAvailableString += $_.Version.ToString() + "; "
      }
    }

    if ($required_version) {
      try {
        Import-Module 'Pester' -RequiredVersion $required_version -ErrorAction Stop
      } catch {
        $module.FailJson("Cannot find/import the Pester module with the specific version: $required_version.  Available versions: $moduleVersionAvailableString")
      }
    } else {
      try {
        Import-Module 'Pester' -MinimumVersion $minimum_version -MaximumVersion '5.999.999' -ErrorAction Stop
      } catch {
        $module.FailJson("Cannot find/import a Pester module with a minimum version of $minimum_version.  Available versions: $moduleVersionAvailableString")
      }
    }
  } else {
    $module.FailJson("Cannot find module: Pester. Check if pester is installed. You can install the latest version from the PowerShell Gallery using 'Find-Module Pester | Install-Module -Scope AllUsers'." )
  }
}

# Get the actual pester's module version in the ansible's result variable
$module.Result.pester_version_used = (Get-Module -Name 'Pester').Version.ToString()

# Create Pester configuration
$pesterConfig = New-PesterConfiguration

if ($test_parameters) {
  # Create a Pester container to hold test parameters
  $pesterContainer = New-PesterContainer -Path $path -Data $test_parameters
  $pesterConfig.Containers.Add($pesterContainer)
} else {
  $pesterConfig.Run.Path = @($path)
}

if ($path_exclude) {
  $pesterConfig.Run.ExcludePath = @($path_exclude)
}

if ($tags_include) {
  $pesterConfig.Filter.Tag = $tags_include
}

if ($tags_exclude) {
  $pesterConfig.Filter.ExcludeTag = $tags_exclude
}

if ($test_results_enabled) {
  $pesterConfig.TestResult.Enabled = $test_results_enabled
  $pesterConfig.TestResult.OutputPath = $output_file
  $pesterConfig.TestResult.OutputFormat = $output_format
  $pesterConfig.TestResult.OutputEncoding = $output_encoding
}

# Always return the test results object
$pesterConfig.Run.PassThru = $true

# Run Pester and collect results
$results = Invoke-Pester -Configuration $pesterConfig
$resultsAtDepth = $results | ConvertTo-Json -Depth $pass_thru_depth
$module.Result.output = $resultsAtDepth | ConvertFrom-Json

# If the module created an output file, then the module made changes
if ($test_results_enabled) {
  $module.Result.changed = $true
} else {
  $module.Result.changed = $false
}

$module.ExitJson()
