echo "build: Build started"

Push-Location $PSScriptRoot

if(Test-Path .\artifacts) {
	echo "build: Cleaning .\artifacts"
	Remove-Item .\artifacts -Force -Recurse
}

& dotnet restore --no-cache

$branch = @{ $true = $env:APPVEYOR_REPO_BRANCH; $false = $(git symbolic-ref --short -q HEAD) }[$env:APPVEYOR_REPO_BRANCH -ne $NULL];
$revision = @{ $true = "{0:00000}" -f [convert]::ToInt32("0" + $env:APPVEYOR_BUILD_NUMBER, 10); $false = "local" }[$env:APPVEYOR_BUILD_NUMBER -ne $NULL];
$suffix = @{ $true = ""; $false = "$($branch.Substring(0, [math]::Min(10,$branch.Length)))-$revision"}[$branch -eq "master" -and $revision -ne "local"]
$commitHash = $(git rev-parse --short HEAD)
$buildSuffix = @{ $true = "$($suffix)-$($commitHash)"; $false = "$($branch)-$($commitHash)" }[$suffix -ne ""]

echo "build: Package version suffix is $suffix"
echo "build: Build version suffix is $buildSuffix" 

foreach ($src in ls src/*) {
    Push-Location $src

	echo "build: Packaging project in $src"

    & dotnet build -c Release --version-suffix=$buildSuffix -p:EnableSourceLink=true
    if ($suffix) {
        & dotnet pack -c Release -o ..\..\artifacts --version-suffix=$suffix --no-build
    } else {
        & dotnet pack -c Release -o ..\..\artifacts --no-build
    }
    if($LASTEXITCODE -ne 0) { exit 1 }    

    Pop-Location
}
# download nuget.exe and put in in the bld/nuget folder
$bldDir = Join-Path $PSScriptRoot "bld"
if (-Not (Test-Path $bldDir)) {
    New-Item -ItemType Directory -Path $bldDir | Out-Null
}

$nuget = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
$nugetDir = Join-Path $bldDir "nuget"
if (-Not (Test-Path $nugetDir)) {
    echo "build: Creating nuget directory $nugetDir"
    New-Item -ItemType Directory -Path $nugetDir | Out-Null
}

$nugetPath = Join-Path $nugetDir "nuget.exe"
if(!(Test-Path $nugetPath)) {
    echo "build: Downloading nuget.exe to $nugetPath"
    Invoke-WebRequest -Uri $nuget -OutFile $nugetPath
}


echo "build: Installing xunit.runner.console NuGet package"

& $nugetPath install xunit.runner.console -Version 2.9.3 -OutputDirectory $bldDir
if ($LASTEXITCODE -ne 0) { exit 2 }
$xcrPath = Join-Path $bldDir "xunit.runner.console.2.9.3/tools/net6.0/xunit.console.exe"
if (-Not (Test-Path $xcrPath)) {
    echo "build: xunit.runner.console not found at $xcrPath"
    exit 2
}
$xcrNet60Path = "$bldDir/xunit.runner.console.2.9.3/tools/net6.0"
echo "build: xunit.runner.console found at $bldDir"
echo "build: xunit.runner.console net6.0 found at $xcrNet60Path"

if ($LASTEXITCODE -ne 0) { exit 2 }
foreach ($test in ls test/*.Tests) {
    Push-Location $test

	echo "build: Testing project in $test"

    & dotnet test -c Release -f  net8.0
    & dotnet test -c Release -f  net472
    & dotnet build -c Release -f  netstandard2.0 
    & $xcrPath ./bin/Release/netstandard2.0/Serilog.Sinks.PersistentFile.Tests.dll
    if($LASTEXITCODE -ne 0) { exit 3 }
    Pop-Location
}

Pop-Location
