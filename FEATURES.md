# Feature Matrix

| Feature | Community Edition | Cloud Free | Cloud Pro |
|---|:---:|:---:|:---:|
| Core nutrition tracking | ✅ | ✅ | ✅ |
| Custom DB/Auth endpoint (self-hosted) | ✅ | ❌ | ❌ |
| Meal templates | ❌ | ✅ | ✅ |
| Activity quick-add | ❌ | ✅ | ✅ |
| Streaks | ❌ | ✅ | ✅ |
| Reports export (CSV) | ❌ | ✅ | ✅ |
| Share progress (mobile only) | ❌ | ✅ | ✅ |
| Micronutrient tracking | ❌ | ❌ | ✅ |
| Advanced analytics | ❌ | ❌ | ✅ |
| Nutrition label scan (mobile only) | ❌ | ❌ | ✅ |

## Notes

- **Cloud Pro** maps to JWT roles `'pro'` or `'basic'` — checked via `AppFeatures.isPaid`
- **Cloud Free** maps to JWT role `'free'`
- **Community Edition** maps to JWT role `'community'` (set on logout/reset)
- Feature gates live in `lib/app_features.dart`
