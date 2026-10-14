# Commander's user interface

This was one 2275-line `commander_shell.dart` holding thirty-four widgets. Nothing was wrong with
any of them; the file was simply the place where every screen, dialog and shared control had ended
up, so a change to the Jobs list and a change to the pairing flow touched the same file, and
nothing about the arrangement said which widgets a page was allowed to reach for.

The split is a pure move — the same statements, in more files — and it was verified as one rather
than trusted: the only differences between before and after are the three `super.key` parameters the
lint requires of a widget that became public.

## Where things live

```
ui/
  commander_shell.dart   navigation, keyboard shortcuts, and the chrome around a page:
                         the desktop header, the loading view, the failure view
  pages/                 one file per navigation destination, and the private widgets
                         only that destination uses
  dialogs/               the modal flows: pairing and Brain profile, managed network,
                         enrollment scanning, and the rows the profile dialog lists
  widgets/               the small controls more than one page needs
```

## The rule for adding something

A widget lives in the narrowest place that can hold it.

- Used by one page, put it in that page's file and keep it private. Most widgets are this.
- Used by two or more, move it to `widgets/` and make it public. Making it public is the point
  rather than an inconvenience: two pages showing the same job state must not drift into calling it
  different things, which is why `jobStateLabel` sits beside `StateIcon` instead of being written
  out twice.
- Needed by the shell *and* a page, it is shared, so `widgets/`. `ModeBadge` is the current example.

The privacy is doing real work here. A private widget in `pages/jobs_page.dart` cannot be reached
from `pages/fleet_page.dart` without somebody first deciding to make it public and move it, and that
decision is exactly the one that used to happen by accident.

## What the shell still owns

Which destinations exist, which one is selected, the digit-key shortcuts, and the two states that
are not a page: still loading, and failed to reach the Brain. It builds pages, it does not know what
is on them.

## Dialogs

`brain_profile_dialog.dart` is the largest file here and stays that way deliberately. Pairing,
re-pairing, revocation and the recovery paths for a Brain that cannot be reached are one interlocked
piece of state, described at length in the top-level README, and splitting them across files would
scatter a flow whose whole difficulty is that its steps constrain each other. What did come out of it
is `paired_brain_rows.dart`: the list rows are presentation over data the dialog hands them, and they
hold none of that state.
