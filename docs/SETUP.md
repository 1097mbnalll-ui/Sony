# إعداد TestFlight (مرة وحدة، من المتصفح على ويندوز)

## 1) سجّل معرّف التطبيق (Bundle ID)
1. ادخل developer.apple.com ← Certificates, IDs & Profiles ← Identifiers ← زر +
2. اختر App IDs ← App ← اكتب الوصف `Tarjuman` والـ Bundle ID مثل `com.اسمك.tarjuman` (حروف إنجليزية).
3. ما يحتاج تفعّل أي خدمات إضافية. احفظ.

## 2) أنشئ التطبيق في App Store Connect
1. appstoreconnect.apple.com ← Apps ← + ← New App
2. المنصة iOS، الاسم «ترجمان» (أو أي اسم متاح)، اللغة Arabic، اختر نفس الـ Bundle ID، و SKU أي نص.

## 3) أنشئ مفتاح API
1. App Store Connect ← Users and Access ← Integrations ← App Store Connect API ← Team Keys ← +
2. الاسم `github-ci`، الصلاحية **Admin** (لازم عشان التوقيع التلقائي في السحابة).
3. نزّل ملف `.p8` (يتنزل مرة وحدة بس). انسخ **Key ID** و **Issuer ID**.
4. Team ID تلقاه في developer.apple.com ← Membership details.

## 4) حط الأسرار في GitHub (أنت بنفسك، لا ترسلها لأحد)
في المستودع: Settings ← Secrets and variables ← Actions

**Secrets** (زر New repository secret):
| الاسم | القيمة |
|---|---|
| `APPLE_TEAM_ID` | الـ Team ID |
| `ASC_KEY_ID` | الـ Key ID |
| `ASC_ISSUER_ID` | الـ Issuer ID |
| `ASC_KEY_P8` | افتح ملف `.p8` بالمفكرة وانسخ كل محتواه والصقه |

**Variables** (تبويب Variables ← New repository variable):
| الاسم | القيمة |
|---|---|
| `APP_BUNDLE_ID` | نفس الـ Bundle ID من الخطوة 1 |

## 5) شغّل البناء
Actions ← Build & TestFlight ← Run workflow ← اختر الفرع ← Run.
بعد ما يخلص (تقريباً 15–25 دقيقة) تنتظر 5–15 دقيقة لين أبل تعالج النسخة.

## 6) ثبّت من TestFlight
1. App Store Connect ← التطبيق ← TestFlight. أول مرة بيسألك عن **Export Compliance** (التشفير)؛ جاوب حسب وضعك.
2. أضف نفسك في Internal Testing ← نزّل تطبيق TestFlight على الآيفون ← ثبّت ترجمان.

## مشاكل معروفة
- **فشل التوقيع**: تأكد إن صلاحية المفتاح Admin وإن الـ Bundle ID مطابق.
- **فشل الرفع "No suitable application records"**: التطبيق ما انشأ في App Store Connect (الخطوة 2).
