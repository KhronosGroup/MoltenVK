#!/usr/bin/env python3
# Copyright (c) 2026 Jean-Philippe Meunier
# SPDX-License-Identifier: Apache-2.0
"""Reads a deqp-vk TestResults.qpa log and prints one "case,status,message" line per case that has a result.

The message is the text of the result, with commas and line breaks replaced. A case the process terminated (crash,
timeout) is reported with the reason CTS logged, prefixed "Terminated:".
Usage: parse-qpa.py <log.qpa>
"""
import re
import sys

begin = re.compile(r"^#beginTestCaseResult (\S+)")
status = re.compile(r'<Result StatusCode="([^"]+)">([^<]*)')
terminate = re.compile(r"^#terminateTestCaseResult (.*)")

case = None
with open(sys.argv[1], errors="replace") as log:
    for line in log:
        match = begin.match(line)
        if match:
            case = match.group(1)
            continue
        if case is None:
            continue
        match = status.search(line)
        if match:
            message = re.sub(r"[,\s]+", " ", match.group(2)).strip()
            print(f"{case},{match.group(1)},{message}")
            case = None
            continue
        match = terminate.match(line)
        if match:
            print(f"{case},Terminated:{match.group(1).strip()}")
            case = None
