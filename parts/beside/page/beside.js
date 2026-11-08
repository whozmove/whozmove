// Whozmove beside the panel, on the page: the place beside it at the panel's edge (core.places.besideEdge), which the
// notifications module fills, telling it how many sessions need you. It shows that by flicking an ear when there are
// more (SideCat.m).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

core.places.besideEdge = {
  // It's drawn beside the panel at its edge whenever the panel is there, which the app knows.
  inSight: () => true,
  show(count) { native({ type: 'besideEdge', needs: count }); },
};
