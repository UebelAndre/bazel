@echo off
REM Copyright 2026 The Bazel Authors. All rights reserved.
REM
REM Licensed under the Apache License, Version 2.0 (the "License");
REM you may not use this file except in compliance with the License.
REM You may obtain a copy of the License at
REM
REM    http://www.apache.org/licenses/LICENSE-2.0
REM
REM Unless required by applicable law or agreed to in writing, software
REM distributed under the License is distributed on an "AS IS" BASIS,
REM WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
REM See the License for the specific language governing permissions and
REM limitations under the License.

REM Windows-native counterpart of collect_coverage.sh, so that coverage runs do
REM not require an MSYS2 bash. Keep the two in sync.
REM See https://github.com/bazelbuild/bazel/issues/5508
REM
REM Expected environment:
REM   COVERAGE_MANIFEST - mandatory, location of the instrumented file manifest
REM   LCOV_MERGER - mandatory, location of the LcovMerger
REM   CC_CODE_COVERAGE_SCRIPT - optional, exec path of the C++ coverage
REM     collector. Rules may override this with an executable of their own; any
REM     extension cmd can dispatch (.exe, .bat, .cmd) works.
REM   COVERAGE_DIR - optional, location of the coverage temp directory
REM   COVERAGE_OUTPUT_FILE - optional, location of the final lcov file
REM   VERBOSE_COVERAGE - optional, print debug info from the coverage scripts
REM   BAZEL_LLVM_PROFILE_FILE - optional, custom LLVM profile filename pattern
REM     (defaults to "%%h-%%p-%%m.profraw" if not set)
REM
REM Script expects that it will be started in the execution root directory and
REM not in the test's runfiles directory.

setlocal EnableExtensions DisableDelayedExpansion

if defined VERBOSE_COVERAGE echo on

REM tw.exe prefixes the runfiles env variables so that this script can find its
REM own runfiles, which are not part of the test's runfiles.
for %%N in (RUNFILES_DIR RUNFILES_MANIFEST_FILE JAVA_RUNFILES PYTHON_RUNFILES) do call :unprefix %%N

if not defined COVERAGE_MANIFEST (
  echo --
  echo Coverage runner: %%COVERAGE_MANIFEST%% is not set
  echo Current environment:
  set
  exit /b 1
)

REM When collect_coverage.bat is used, the test runner must be instructed not to
REM cd to the test's runfiles directory.
set "ROOT=%CD%"

REM Canonicalize the path to the coverage manifest so that tests can find it.
call :absolutize COVERAGE_MANIFEST

REM Write coverage data outside of the runfiles tree.
if not defined COVERAGE_DIR set "COVERAGE_DIR=%ROOT%\coverage"
call :absolutize COVERAGE_DIR

if not exist "%COVERAGE_DIR%" mkdir "%COVERAGE_DIR%"

if not defined COVERAGE_OUTPUT_FILE set "COVERAGE_OUTPUT_FILE=%COVERAGE_DIR%\_coverage.dat"
call :absolutize COVERAGE_OUTPUT_FILE

REM Java
REM --------------------------------------
set "JAVA_COVERAGE_FILE=%COVERAGE_DIR%\jvcov.dat"
REM Let tests know that it is a coverage run.
set "COVERAGE=1"
set "BULK_COVERAGE_RUN=1"

REM Setting up the environment for executing the C++ tests.
if not defined GCOV_PREFIX_STRIP set "GCOV_PREFIX_STRIP=3"
set "GCOV_PREFIX=%COVERAGE_DIR%"
if defined BAZEL_LLVM_PROFILE_FILE (
  set "LLVM_PROFILE_FILE=%COVERAGE_DIR%\%BAZEL_LLVM_PROFILE_FILE%"
) else (
  set "LLVM_PROFILE_FILE=%COVERAGE_DIR%\%%h-%%p-%%m.profraw"
)
REM %%c enables continuous mode but expands out to nothing, so the position
REM within LLVM_PROFILE_FILE does not matter.
if defined LLVM_PROFILE_CONTINUOUS_MODE set "LLVM_PROFILE_FILE=%LLVM_PROFILE_FILE%%%c"

REM In coverage mode for Java, merge the runtime classpath listed in
REM JAVA_RUNTIME_CLASSPATH_FOR_COVERAGE with SingleJar and hand the result to
REM JacocoCoverageRunner via JACOCO_METADATA_JAR. See collect_coverage.sh for
REM why the merge happens here rather than in the coverage runner.
if not defined JAVA_RUNTIME_CLASSPATH_FOR_COVERAGE goto :after_single_jar

set "JAVA_RUNTIME_CLASSPATH_FOR_COVERAGE=%ROOT%\%JAVA_RUNTIME_CLASSPATH_FOR_COVERAGE%"
set "SINGLE_JAR_TOOL=%ROOT%\%SINGLE_JAR_TOOL%"
call :absolutize SINGLE_JAR_TOOL

set "_single_jar_params_file=%COVERAGE_DIR%\runtime_classpath.paramsfile"
set "JACOCO_METADATA_JAR=%COVERAGE_DIR%\coverage-runtime_merged_instr.jar"

REM The classpath entries are relative, so prefix each with the runfiles root to
REM give SingleJar absolute paths. One redirection for the whole file: a runtime
REM classpath can run to hundreds of jars.
set "_runfiles_prefix=%TEST_SRCDIR%\%TEST_WORKSPACE%\"
> "%_single_jar_params_file%" (
  echo --output %JACOCO_METADATA_JAR%
  echo --sources
  for /f "usebackq delims=" %%L in ("%JAVA_RUNTIME_CLASSPATH_FOR_COVERAGE%") do echo %_runfiles_prefix%%%L
)

REM Invoke SingleJar. This will create JACOCO_METADATA_JAR.
call "%SINGLE_JAR_TOOL%" "@%_single_jar_params_file%"

:after_single_jar

if not "%IS_COVERAGE_SPAWN%"=="0" goto :after_test

REM TODO(bazel-team): cd should be avoided.
cd /d "%TEST_SRCDIR%\%TEST_WORKSPACE%"

REM Always create the coverage report.
if "%SPLIT_COVERAGE_POST_PROCESSING%"=="0" (
  if not exist "%COVERAGE_OUTPUT_FILE%" type nul > "%COVERAGE_OUTPUT_FILE%"
)

REM Execute the test.
call %*
set "TEST_STATUS=%ERRORLEVEL%"

if "%TEST_STATUS%"=="0" goto :after_test
echo --
echo Coverage runner: Not collecting coverage for failed test.
echo The following commands failed with status %TEST_STATUS%
echo %*
exit /b %TEST_STATUS%

:after_test

REM ------------------EXPERIMENTAL---------------------
REM After this point we can run the code necessary for the coverage spawn.

REM Make sure no binaries run later produce coverage data.
set "LLVM_PROFILE_FILE="

if "%SPLIT_COVERAGE_POST_PROCESSING%"=="1" (
  if "%IS_COVERAGE_SPAWN%"=="0" exit /b 0
  if "%IS_COVERAGE_SPAWN%"=="1" if not exist "%COVERAGE_OUTPUT_FILE%" type nul > "%COVERAGE_OUTPUT_FILE%"
)

REM TODO(bazel-team): cd should be avoided.
cd /d "%ROOT%"

REM Call the C++ code coverage collection script. A rule may point
REM CC_CODE_COVERAGE_SCRIPT at an arbitrary executable of its own instead of the
REM built-in collector, so resolve the exec path to a fully qualified Windows
REM path and dispatch it with `call`, which runs a .exe as a child process and a
REM .bat or .cmd in this interpreter, waiting for it and returning control here
REM either way. Invoking a batch file without `call` would never come back.
if not defined GENERATE_LLVM_LCOV goto :after_cc_coverage
if not defined CC_CODE_COVERAGE_SCRIPT goto :after_cc_coverage
call :absolutize CC_CODE_COVERAGE_SCRIPT
call "%CC_CODE_COVERAGE_SCRIPT%"
REM Compare against 0 rather than using `if errorlevel 1`, which does not match
REM the negative exit codes a crashing native binary produces.
if "%ERRORLEVEL%"=="0" goto :after_cc_coverage
if defined IGNORE_COVERAGE_COLLECTION_FAILURES goto :after_cc_coverage
echo error: coverage collection script failed 1>&2
exit /b 1
:after_cc_coverage

REM This can happen if a rule returns an InstrumentedFilesInfo (which all do
REM following 5b216b2) but does not define an _lcov_merger attribute.
REM Unfortunately, we cannot simply stop this script being called in this case
REM due to conflicts with how things work within Google.
REM The file creation is required because TestActionBuilder has already declared
REM it.
if not defined LCOV_MERGER exit /b 0

REM The LCOV merger is overridable through the _lcov_merger attribute, so it is
REM subject to the same dispatch rules as CC_CODE_COVERAGE_SCRIPT above.
call :absolutize LCOV_MERGER

if not exist "%LCOV_MERGER%" (
  echo --
  echo Coverage runner: cannot locate file %LCOV_MERGER%
  exit /b 1
)

REM Build the command line that invokes LcovMerger. See collect_coverage.sh for
REM what the individual flags mean.
set "_lcov_merger_args=--coverage_dir=%COVERAGE_DIR% --output_file=%COVERAGE_OUTPUT_FILE% --filter_sources=/usr/bin/.+ --filter_sources=/usr/lib/.+ --filter_sources=/usr/include.+ --filter_sources=/Applications/.+ --source_file_manifest=%COVERAGE_MANIFEST%"

if defined COVERAGE_REPORTED_TO_ACTUAL_SOURCES_FILE set "_lcov_merger_args=%_lcov_merger_args% --sources_to_replace_file=%ROOT%\%COVERAGE_REPORTED_TO_ACTUAL_SOURCES_FILE%"

if defined DISPLAY_LCOV_CMD (
  echo Running lcov_merger
  echo "%LCOV_MERGER%" %_lcov_merger_args%
  echo -----------------
)

REM Runfiles variables are set to the runfiles of the test, which does not
REM contain the runfiles of the LCOV merger. Clear them so that it can find its
REM own runfiles tree.
set "JAVA_RUNFILES="
set "RUNFILES_DIR="
set "RUNFILES_MANIFEST_FILE="
call "%LCOV_MERGER%" %_lcov_merger_args%
exit /b %ERRORLEVEL%

REM Moves BAZEL_COVERAGE_INTERNAL_<name> into <name>, if the former is set.
:unprefix
set "_wrapped_name=BAZEL_COVERAGE_INTERNAL_%~1"
call set "_wrapped_value=%%%_wrapped_name%%%"
if defined _wrapped_value (
  set "%~1=%_wrapped_value%"
  set "%_wrapped_name%="
)
set "_wrapped_name="
set "_wrapped_value="
goto :eof

REM Rewrites the variable named by %1 to a fully qualified path. Relative paths
REM are resolved against the current directory, which is the execution root.
:absolutize
call set "_abs_value=%%%~1%%"
if defined _abs_value for %%I in ("%_abs_value%") do set "%~1=%%~fI"
set "_abs_value="
goto :eof
