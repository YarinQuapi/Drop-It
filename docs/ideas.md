# Ideas backlog

Ideas for improving Drop It, to revisit. Roughly in priority order.

1. **Scanner feedback loop** (in progress, branch `scanner-feedback-loop`)
   A "report a bad scan" button that saves the photo and the recognized text.
   Real failures become parser tests (like the Pringles one) and a test set
   builds up over time. Liquid / per-100 ml labels still fail.

2. **Auto-fill foods from a barcode database**
   Look the barcode up in Open Food Facts (good Israeli coverage) before asking
   for a label photo. The label scanner becomes the fallback. Also seeds the
   catalog.

3. **Review step for scanned values**
   Show the photo beside the parsed fields and highlight low-confidence values
   (repaired decimals, Atwater mismatch) instead of a generic "please check".

4. **Faster logging**
   Recent and frequent foods at the top of add-meal, "copy yesterday's meals",
   saved meals / combos.

5. **Home screen widget and reminders**
   Widget with today's calories and the fasting timer; optional notification
   when a fast ends.

6. **Catalog trust signals**
   Prominent verified badges, a way for users to flag wrong values, per-barcode
   change history, and an admin queue of flagged entries.
