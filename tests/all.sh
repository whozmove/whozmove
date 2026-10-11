#!/bin/bash
# Runs every test: both hooks, the rows the app builds, and the panel page's logic. Exits 1 if any output changed.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
cd "$(dirname "$0")/.." || exit 1
status=0
tests/hooks.sh || status=1
tests/rows.sh || status=1
tests/panel.sh || status=1
exit $status
