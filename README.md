# Final-app
Daily Improvement Household

Imagine living with three other people, and somehow you're always the one taking out the trash, cleaning the kitchen, or buying household supplies. Nobody knows whose turn it is, and everybody thinks they're doing more than the next person.
That's the problem our app Daily improvement Household, is designed to solve.
Daily improvement household  is a roommate management app that helps people organize their shared living space. Users can create a household, invite their roommates, assign chores, create shared grocery lists, and keep track of responsibilities.
One of our biggest features is automatic chore rotation, which makes sure the same person isn't stuck doing the same task every week. (Unless agreed upon)
We're also introducing a fairness system that tracks completed responsibilities so everyone can see how they're contributing.
Because at the end of the day, if everybody lives there, everybody should contribute.

---

## Tech

Flutter (Android and web) with Supabase as the backend.

[![CI](https://github.com/MalachiF18/Final-app/actions/workflows/ci.yml/badge.svg)](https://github.com/MalachiF18/Final-app/actions/workflows/ci.yml)

## Folder layout

```
lib/
  main.dart                          app entry point, starts the app
  core/
    app.dart                         MaterialApp and bottom-nav shell (4 tabs)
    theme.dart                       light and dark Material 3 theme from one seed
    dates.dart                       relativeDue(): "Due tomorrow", "Overdue by 2 days"
  features/
    chores/chores_screen.dart        Chores tab (card 2.1)
    groceries/groceries_screen.dart  Groceries tab (card 3.1)
    fairness/fairness_screen.dart    Fairness tab (card 3.8)
    household/household_screen.dart  Household tab (cards 1.5, 1.7)
test/
  core/                              tests mirror lib/core
```

## Run it

```
flutter pub get
flutter test
flutter run
```

## How we work

- One branch per Trello card, named like `2.3-repeat-schedules`.
- Open a pull request into `main`.
- CI must pass before merging.
- Move the card to Done when it is merged.
