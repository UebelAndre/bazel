#!/usr/bin/env bash
#
# Copyright 2026 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Stands in for collect_cc_coverage.sh when
# --@bazel_tools//tools/test:incompatible_disable_builtin_cc_coverage is
# enabled. Its Windows counterpart is collect_cc_coverage_noop.bat.
#
# Coverage for the other languages is still collected; LcovMerger simply finds
# no C++ reports to merge.
# See https://github.com/bazelbuild/bazel/issues/5508

echo "Warning: Bazel's built-in C++ code coverage collection is disabled by" \
     "--@bazel_tools//tools/test:incompatible_disable_builtin_cc_coverage." >&2
