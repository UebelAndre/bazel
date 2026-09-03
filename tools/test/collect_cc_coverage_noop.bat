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

REM Stands in for collect_cc_coverage.sh when
REM --@bazel_tools//tools/test:incompatible_disable_builtin_cc_coverage is
REM enabled. Its non-Windows counterpart is collect_cc_coverage_noop.sh.
REM
REM Coverage for the other languages is still collected; LcovMerger simply finds
REM no C++ reports to merge.
REM See https://github.com/bazelbuild/bazel/issues/5508

echo Warning: Bazel's built-in C++ code coverage collection is disabled by 1>&2
echo --@bazel_tools//tools/test:incompatible_disable_builtin_cc_coverage. 1>&2
exit /b 0
