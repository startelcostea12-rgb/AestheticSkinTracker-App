# AestheticSkinTracker Beta Launch Checklist

## Store Metadata

- App name finalized and consistent across iOS, Android, and web.
- Subtitle / short description focused on skin progress tracking, recovery guidance, and AI-assisted insights.
- Full description written in plain language with clear mention that the app does not provide medical diagnosis.
- Keywords prepared for App Store and Play Store search relevance.
- Support email and support URL ready.
- Marketing website or landing page ready.
- Privacy Policy URL published and reachable.
- Terms of Use / subscription terms URL published and reachable.

## Screenshots And Visuals

- iPhone screenshots for 6.7-inch and 6.1-inch sizes.
- Android phone screenshots for Play Store listing.
- Tablet screenshots if tablet layouts are supported.
- Screenshots include onboarding, scan flow, peptide/reconstitution library, analysis results, and paywall.
- App icon verified on Android, iOS, web, Windows, and macOS.
- Splash screen verified on light backgrounds and slow launch conditions.

## Privacy And Compliance

- Privacy Policy explicitly describes camera/photo usage, analytics, subscriptions, and AI-assisted processing.
- App Store privacy nutrition labels prepared.
- Google Play Data safety form prepared.
- If backend image analysis is enabled, retention and deletion policy documented clearly.
- Medical disclaimer reviewed on onboarding, analysis, and subscription surfaces.

## Subscription Readiness

- RevenueCat offerings verified in sandbox.
- Product IDs and entitlement names match production configuration.
- Purchase flow tested on iOS sandbox and Android internal testing.
- Restore purchases tested on real store accounts.
- Paywall copy clearly explains Premium vs Free.
- One-time report offering and subscription messaging are consistent.

## Functional QA

- Onboarding completes cleanly on phone and web.
- Camera capture, crop, and Deep Analysis gating work on supported devices.
- Backend unavailable state shows a clear retry/error message.
- Reconstitution sheet and peptide library have no layout overflow on narrow screens.
- Web build has no missing logo asset or optional-model 404 noise.
- Key routes tested: home, onboarding, camera, peptide tracker, paywall, report flow.

## Release Builds

- flutter analyze reviewed with no blocking errors.
- flutter test passes.
- flutter build appbundle succeeds.
- iOS archive / TestFlight upload succeeds.
- flutter build web succeeds if web beta is planned.

## Submission Prep

- Beta tester notes prepared.
- In-app purchase review notes prepared for Apple.
- Demo account or review steps documented if needed.
- Changelog / What’s New text drafted for first beta.