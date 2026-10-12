# Neon Getaway: online setup

The code for v0.11 is done, but Game Center and iCloud need some account setup before online play works on a phone or TestFlight.

1. **Capabilities.** A signed device build (`check_mode=device`) uses automatic signing with `-allowProvisioningUpdates`. That adds Game Center and iCloud (CloudKit) to the App ID `com.phoronomicstudios.neongetaway` and registers the container `iCloud.com.phoronomicstudios.neongetaway`. It needs Omari's OK, because it changes the developer account.
2. **App Store Connect → Neon Getaway → Game Center:** turn Game Center on and create three leaderboards:
   - `neon.weekly.earnings`: "This week's earnings". Recurring, starts on a Monday at 00:00, repeats every 1 week, high score wins.
   - `neon.alltime.score`: "All-time score". Classic, high score wins.
   - `neon.networth`: "Net worth". Classic, most recent score.
3. **CloudKit Console → container → Development schema.** The record types `Design`, `Purchase` and `Report` appear the first time each is saved. Then add these indexes:
   - `Design`: `recordName` Queryable, `createdTimestamp` Sortable.
   - `Purchase`: `creatorID` Queryable, `designID` Queryable.
   - `Report`: `designID` Queryable.

   Then **deploy the schema to Production** before any TestFlight build, because TestFlight uses Production.
4. **Support contact (App Review 1.2):** done: `Support.email` = hello@phoronomicstudios.com (Online screen → "Report a problem or a player").
5. **Privacy label:** add "User ID" (Game Center player ID, linked to the user, used for app functionality) and "Other user content" (published paint designs). It's not used for tracking.
6. **Live play testing:** use two phones signed in to different Game Center accounts (sandbox accounts are fine), both on the same build.
