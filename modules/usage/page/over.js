// Over the gear, at the end of the title line of each session working beyond your gear, in any grouping and whatever the
// team file says: grey and outlined, the kit's chip, as nothing is stopped for it. It comes and goes as the row's other
// title-end parts do.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

core.slots.titleEnd.push((row) => (core.gear?.facts()?.over?.includes(row.s.sessionId)
  ? `<span class="tag chip outline u-over">${esc(GEAR_WORDS.overMark)}</span>` : ''));
