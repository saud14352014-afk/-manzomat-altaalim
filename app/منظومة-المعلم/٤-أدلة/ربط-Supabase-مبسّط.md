# ربط منظومة المعلم بـ Supabase — نسخة مبسّطة (معلّم واحد)

بلا حسابات، بلا GitHub، بلا رمز مزامنة. فقط: أنشئ مشروع، الصق رابطين، اضغط ربط.

---

## الخطوة ١ — أنشئ المشروع (مرة واحدة)
1. ادخل **supabase.com** ← Start your project ← سجّل **ببريدك الإلكتروني** (Email) — لا تحتاج GitHub.
2. **New project** ← اكتب اسمًا + كلمة مرور لقاعدة البيانات + اختر أقرب منطقة ← **Create new project** وانتظر دقيقة.

## الخطوة ٢ — أنشئ الجدول (الصق واضغط Run)
من اليسار: **SQL Editor** ← **New query** ← الصق هذا كاملًا ← **Run**:

```sql
create table if not exists teacher_data (
  id text primary key,
  data jsonb not null,
  teacher text,
  updated_at timestamptz default now()
);
alter table teacher_data enable row level security;
grant usage on schema public to anon;
grant select, insert, update, delete on teacher_data to anon;
drop policy if exists "anon access" on teacher_data;
create policy "anon access" on teacher_data
  for all to anon using (true) with check (true);
```

تظهر: **Success. No rows returned** = تم.

## الخطوة ٣ — انسخ الرابطين
من اليسار: **Project Settings (⚙️)** ← **API**:
- انسخ **Project URL**  (مثل `https://abcd.supabase.co`)
- انسخ مفتاح **anon public**  (يبدأ بـ `eyJhbGci...`)

## الخطوة ٤ — الصق في التطبيق
داخل التطبيق: **الإعدادات ← النسخ السحابي**:
1. الصق **Project URL**.
2. الصق مفتاح **anon public**.
3. اضغط **ربط وحفظ**.

ظهور «متصل» = تم الربط، ورُفعت نسختك تلقائيًا. بعدها كل تعديل يُرفع وحده.

---

### للاستعادة على جهاز آخر (نفسك)
افتح التطبيق على الجهاز الآخر ← الإعدادات ← النسخ السحابي ← الصق **نفس** الرابط والمفتاح ← **ربط وحفظ** ← **استعادة من السحابة**.

### ملاحظات
- بياناتك تبقى على جهازك وتعمل دون إنترنت؛ السحابة نسخة احتياطية تلقائية.
- لا تستخدم مفتاح **service_role** إطلاقًا — فقط **anon public**.
- إن ظهر خطأ «الجدول غير موجود»: أعد تنفيذ كود الخطوة ٢.
- إن ظهر «مرفوض»: تأكد أنك نفّذت أوامر grant و create policy معًا.
