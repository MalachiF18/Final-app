# Publishing at no personal cost

Research checked November 4, 2026. This is a school project, so start with the school’s department or IT team. Apple normally charges **US$99 per membership year** (local pricing varies), even when the app is free to download. Flutter itself does not remove that fee. [Apple enrollment](https://developer.apple.com/help/account/membership/program-enrollment)

## Routes to an actual App Store listing

| Route | Who pays? | Fit for this project |
| --- | --- | --- |
| Accredited school requests an Apple Developer Program fee waiver | Apple waives the membership fee if approved | Best first choice. The school publishes and administers the app as its project. |
| School already has an active Developer Program membership | No additional individual membership is needed for invited team members | Ask a faculty sponsor or IT administrator to add the project to the existing organization team. Its membership must stay active. |
| Eligible nonprofit or government organization adopts and publishes the project | Membership can be waived if the organization qualifies | Only appropriate for a real partnership with an eligible entity. Creating a free app or a student club does not by itself make an individual eligible. |
| School, sponsor, grant, or hackathon award funds a membership | Someone else covers the fee | Zero out-of-pocket for you, but not a fee-free Apple program. Confirm ongoing funding, ownership, and the actual account holder. |
| Swift Student Challenge award | Some past awards included one year of membership | Competitive and time-limited, not a dependable publishing plan. Confirm the next award’s benefits and redemption conditions before relying on it. A Flutter repository is not the required Swift app playground submission. |

Apple’s waiver requires an eligible **legal entity**, excludes individuals/sole proprietors/single-person businesses, and restricts paid apps, in-app purchases, and other sales of digital goods/services. The organization requests the waiver while enrolling, or its existing Account Holder requests it before expiration. Approval is Apple’s decision. [Fee-waiver requirements](https://developer.apple.com/help/account/membership/fee-waivers)

Invitations give individual Apple Accounts team access; do not share the school’s account password. [Invite team members](https://developer.apple.com/help/account/access/invite-team-members)

The challenge’s current rules require an individual’s original `.swiftpm` playground and student eligibility. The 2026 deadline has passed. Apple documented a one-year membership award in prior years; do not assume an unannounced future cycle guarantees the same benefit. [Current challenge](https://developer.apple.com/swift-student-challenge/), [2026 rules](https://developer.apple.com/swift-student-challenge/policy/), [Apple’s prior membership-award example](https://apps.apple.com/us/iphone/story/id1517413279)

## Free alternatives that are not App Store publication

- **Web app:** Build Flutter web and host on a free static service. GitHub Pages supports public repositories on GitHub Free, including this public repo. On iPhone, Safari’s Add to Home Screen / Open as Web App gives an app-like launcher. This does not create an App Store listing, native iOS package, or guaranteed offline support. Each browser/device retains its own demo data. [GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages), [Apple Home Screen instructions](https://support.apple.com/guide/iphone/open-as-web-app-iphea86e5236/ios)
- **Personal device with Xcode:** A free Apple Account can provision an app for your own testing. Personal Team provisioning is temporary and must be refreshed; it is not public distribution. Requires a Mac with Xcode and an iOS project. [Apple account overview](https://developer.apple.com/help/account/basics/about-your-developer-account)
- **School TestFlight:** Testers do not need a paid developer membership, but the publishing school still needs an active Developer Program membership (possibly waived). TestFlight is beta testing, not a permanent listing or a way around membership. [Apple Developer Program](https://developer.apple.com/programs/)
- **Android APK / classroom browser demo:** Useful for assessment without the Apple store. Neither gives an iPhone App Store listing.

Enterprise distribution, ad hoc signing, unlisted apps, alternative marketplaces, and web-distributed native iOS apps are not universal free App Store loopholes. They have separate membership, eligibility, or distribution restrictions. A free builder or cloud build allowance also does not waive Apple’s publisher fee. [Apple program comparison](https://developer.apple.com/help/account/membership/programs-overview/)

## Suggested school plan

1. Ask the faculty sponsor whether the institution already has an Apple Developer organization team and allows student project publication.
2. If not, ask an authorized school representative to review fee-waiver eligibility and enroll the institution. Agree who maintains the app after the course ends.
3. Get invited with your own Apple Account and the appropriate development/App Store Connect role.
4. Complete production readiness below, test on physical iPhones, and have the school’s publisher submit the signed archive for review.
5. While waiting, demonstrate the local web build. A GitHub Pages build can use `flutter build web --release --base-href /Final-app/`; upload `build/web` through a Pages workflow after enabling Pages. Publishing has not been performed by this change.

## This repository’s iOS readiness

This commit is a locally saved school demo, not an App Store submission. The repository currently targets Android and web and has no checked-in iOS runner. On a Mac with Xcode, generate the iOS platform files with `flutter create --platforms=ios --org io.github.malachif18 .`, review the generated changes, choose the institution-approved bundle ID/signing team, then follow Flutter’s iOS release guide. Do not claim a signed or device-tested iOS build until it exists. [Flutter iOS release guide](https://docs.flutter.dev/deployment/ios)

Before submitting: replace the planned Groceries screen or remove that tab from the release; decide whether the product is a local organizer or implement authenticated household synchronization; supply app icons, screenshots, support and privacy URLs, accurate privacy disclosures, age rating, and review notes. Current local demo data includes roommate names and chore history on the device. Confirm the behavior of every dependency before selecting App Store privacy answers. No push notifications or background scheduler are implemented. Rotation happens after a saved completion.

App Review approval is separate from fee-waiver approval. A class submission destination and a school publishing account were not provided, so no class portal or App Store submission was made.
