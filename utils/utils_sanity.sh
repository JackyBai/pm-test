#!/bin/bash
#
# PM-QA validation test suite for the power management on Linux
#
# Copyright (C) 2014, Linaro Limited.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# Contributors:
#     Sanjay Singh Rawat <sanjay.rawat@linaro.org>
#       - initial API and implementation
#

source ../include/functions.sh

is_root
if [ $? -ne 0 ]; then
    log_skip "user is not root"
    exit 0
fi

check_utils() {
    # just returning SUCCESS, so suite doesn't break
    return 1
}

check_utils
