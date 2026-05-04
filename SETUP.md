# yAllsale — Tam Altyapı Kurulum Rehberi
# Bu dosyayı GitHub'a yükle, referans olarak kullan

## ═══════════════════════════════════════
## 1. SUPABASE KURULUMU
## ═══════════════════════════════════════

### 1a. Veritabanı tablolarını kur
1. supabase.com → yAllsale projene gir
2. Sol menü → "SQL Editor"
3. backend/schema.sql dosyasının içeriğini kopyala
4. SQL Editor'a yapıştır → "Run" bas
5. Tüm tablolar otomatik oluşur

### 1b. Storage bucket oluştur (ürün fotoğrafları için)
1. Sol menü → "Storage"
2. "New bucket" → isim: "product-photos"
3. Public: ON
4. "Create bucket" bas

### 1c. Auth ayarları
1. Sol menü → "Authentication" → "Providers"
2. Email: ON (zaten aktif)
3. Phone: "Twilio" seç → Twilio credentials gir (aşağıda)
4. Google: Client ID ve Secret gir (Google Cloud Console'dan)

## ═══════════════════════════════════════
## 2. STRIPE KURULUMU
## ═══════════════════════════════════════

### 2a. Stripe hesabı
1. stripe.com → "Start now" → kayıt ol
2. Dashboard → "Activate your account" → banka bilgilerini gir
3. Sol menü → "Developers" → "API keys"
4. Publishable key ve Secret key'i kaydet

### 2b. Stripe Identity aktif et
1. Dashboard → "Products" → "Identity"
2. "Activate" bas → kabul et
3. Artık Gov. ID doğrulama hazır

### 2c. Ürünler ve fiyatlar oluştur
Dashboard → "Products" → "Add product":

Ürün 1: "Verified Member"
- Price: $2.99, One time
- Price ID'yi kaydet: price_xxxxxxxx

Ürün 2: "Pro Seller"  
- Price: $9.99, Monthly recurring
- Price ID'yi kaydet: price_xxxxxxxx

### 2d. Webhook kur
1. Dashboard → "Developers" → "Webhooks"
2. "Add endpoint" → URL: https://mgakdlawqrhbqfeizgpf.supabase.co/functions/v1/stripe-webhook
3. Events seç:
   - checkout.session.completed
   - identity.verification_session.verified
   - identity.verification_session.requires_input
   - customer.subscription.deleted
4. "Signing secret"i kaydet

## ═══════════════════════════════════════
## 3. TWILIO KURULUMU (SMS doğrulama)
## ═══════════════════════════════════════

1. twilio.com → kayıt ol (ücretsiz $15 kredi ile başlar)
2. Console → "Account SID" ve "Auth Token"u kaydet
3. "Phone Numbers" → bir numara al (ücretsiz trial ile)
4. Supabase → Authentication → Phone → Twilio credentials gir

## ═══════════════════════════════════════
## 4. SUPABASE EDGE FUNCTIONS DEPLOY
## ═══════════════════════════════════════

### Gereksinimler
- Node.js (https://nodejs.org)
- Supabase CLI: npm install -g supabase

### Kurulum
```bash
# Terminal aç
supabase login
supabase link --project-ref mgakdlawqrhbqfeizgpf

# Functions klasörünü oluştur
mkdir -p supabase/functions/create-checkout
mkdir -p supabase/functions/stripe-webhook
mkdir -p supabase/functions/stripe-identity
mkdir -p supabase/functions/nearby-sales
mkdir -p supabase/functions/send-notifications

# backend/functions.js dosyasındaki kodları ilgili klasörlere kopyala
# Her klasöre index.ts olarak kaydet

# Deploy
supabase functions deploy create-checkout
supabase functions deploy stripe-webhook
supabase functions deploy stripe-identity
supabase functions deploy nearby-sales
supabase functions deploy send-notifications
```

### Environment Variables
```bash
supabase secrets set STRIPE_SECRET_KEY=sk_live_xxxxxxxx
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_xxxxxxxx
supabase secrets set STRIPE_PRO_PRICE_ID=price_xxxxxxxx
supabase secrets set SUPABASE_URL=https://mgakdlawqrhbqfeizgpf.supabase.co
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=sb_secret_8aYoP...
```

## ═══════════════════════════════════════
## 5. VERCEL ENVIRONMENT VARIABLES
## ═══════════════════════════════════════

Vercel Dashboard → yallsale projesi → Settings → Environment Variables:

```
NEXT_PUBLIC_SUPABASE_URL=https://mgakdlawqrhbqfeizgpf.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=sb_publishable_J_F7Wk0SB3eCLnKqmd5o6g_o3IgkZfE
NEXT_PUBLIC_MAPBOX_TOKEN=pk.eyJ1IjoiY2Vua2VyMzUi...
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_live_xxxxxxxx
STRIPE_SECRET_KEY=sk_live_xxxxxxxx
STRIPE_WEBHOOK_SECRET=whsec_xxxxxxxx
```

## ═══════════════════════════════════════
## 6. GOOGLE SIGN IN KURULUMU
## ═══════════════════════════════════════

1. console.cloud.google.com → Yeni proje: "yAllsale"
2. APIs & Services → Credentials → "Create Credentials" → OAuth 2.0
3. Authorized redirect URIs ekle:
   - https://mgakdlawqrhbqfeizgpf.supabase.co/auth/v1/callback
   - https://yallsale.com/auth/callback
4. Client ID ve Secret'ı kaydet
5. Supabase → Authentication → Google → credentials gir

## ═══════════════════════════════════════
## 7. APPLE SIGN IN KURULUMU
## ═══════════════════════════════════════

1. developer.apple.com → Certificates, IDs & Profiles
2. Identifiers → App IDs → yAllsale'i seç → "Sign In with Apple" aktif et
3. Keys → "+" → "Sign In with Apple" seç
4. Key ID ve .p8 dosyasını indir
5. Supabase → Authentication → Apple → credentials gir

## ═══════════════════════════════════════
## 8. SCHEDULED FUNCTIONS (cron)
## ═══════════════════════════════════════

Supabase'de cron jobs kur:

```sql
-- Her 15 dakikada item tracking bildirimleri gönder
SELECT cron.schedule(
  'send-item-tracking-notifications',
  '*/15 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://mgakdlawqrhbqfeizgpf.supabase.co/functions/v1/send-notifications',
    headers := '{"Authorization": "Bearer SERVICE_ROLE_KEY"}'::jsonb
  );
  $$
);

-- Her gece saat 00:00'da süresi dolan öne çıkanları kaldır
SELECT cron.schedule(
  'expire-featured-listings',
  '0 0 * * *',
  $$
  UPDATE public.sales 
  SET is_featured = false, status = 'active' 
  WHERE is_featured = true AND featured_until < NOW();
  $$
);

-- Her gece süresi dolan rezervasyonları iptal et
SELECT cron.schedule(
  'expire-reservations',
  '0 * * * *',
  $$
  UPDATE public.reservations SET status = 'expired' 
  WHERE status = 'active' AND expires_at < NOW();
  UPDATE public.products SET status = 'available', reserved_by = NULL 
  WHERE status = 'reserved' AND reservation_expires_at < NOW();
  $$
);
```

## ═══════════════════════════════════════
## 9. TAHMINI MALİYET TABLOSU
## ═══════════════════════════════════════

Servis               | Ücretsiz Limit      | Sonrası
---------------------|---------------------|------------------
Supabase             | 50K kullanıcı       | $25/ay
Vercel               | 100GB bant genişliği| $20/ay
Mapbox               | 50K yükleme/ay      | $0.50/1K
Stripe ID Verify     | -                   | $1.50/doğrulama
Twilio SMS           | $15 kredi           | $0.0075/SMS
Google Sign In       | Sınırsız            | Ücretsiz
Apple Sign In        | Developer hesabında | Ücretsiz

İlk 500 kullanıcı için tahmini toplam: ~$50-100/ay

## ═══════════════════════════════════════
## 10. DOSYA YAPISI
## ═══════════════════════════════════════

yallsale/
├── index.html          # Ana uygulama (harita + tüm ekranlar)
├── landing.html        # Tanıtım sayfası (yallsale.com)
├── auth.html           # Kayıt / giriş akışı
├── membership.html     # Üyelik planları + Stripe ödeme
├── backend/
│   ├── schema.sql      # Supabase veritabanı şeması
│   └── functions.js    # Edge functions kodu
└── SETUP.md            # Bu dosya
