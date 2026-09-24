# ربط «منظومة المعلم» بقاعدة Supabase — دليل كامل خطوة بخطوة

التطبيق يخزّن كامل حالتك في كائن واحد، ويزامنها كصفّ واحد لكل معلّم في جدول
`teacher_data`. يعمل التطبيق دون إنترنت، والسحابة للنسخ الاحتياطي والمزامنة بين الأجهزة.

الحقول التي يستخدمها التطبيق:
- `id`  = رمز المزامنة (مُعرّفك السري)
- `data` = كامل بيانات التطبيق (jsonb)
- `updated_at` = آخر تحديث
- `teacher` = اسم المعلّم (للعرض)

---

## الخطوة ١: إنشاء المشروع
1. https://supabase.com ← **Start your project** ← سجّل الدخول.
2. **New project** ← اسم المشروع + كلمة مرور قاعدة البيانات + أقرب منطقة ← **Create new project**.

## الخطوة ٢: إنشاء الجدول والأمان
**SQL Editor** ← **New query** ← الصق الكود التالي كاملًا ← **Run**:

```sql
-- جدول بيانات المعلّم (كامل حالة التطبيق كصفّ واحد لكل معلّم)
create table if not exists public.teacher_data (
  id          text primary key,          -- رمز المزامنة (مُعرّف حسابك السري)
  data        jsonb not null,            -- كامل بيانات التطبيق
  teacher     text,                      -- اسم المعلّم (للعرض فقط)
  updated_at  timestamptz default now()  -- آخر تحديث
);

-- تفعيل حماية الصفوف
alter table public.teacher_data enable row level security;

-- صلاحيات دور anon (المفتاح العام)
grant usage on schema public to anon;
grant select, insert, update, delete on public.teacher_data to anon;

-- سياسة الوصول
drop policy if exists "anon full access" on public.teacher_data;
create policy "anon full access" on public.teacher_data
  for all to anon
  using (true)
  with check (true);

-- تحديث updated_at تلقائيًا
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_teacher_data_updated on public.teacher_data;
create trigger trg_teacher_data_updated
  before update on public.teacher_data
  for each row execute function public.set_updated_at();
```

النتيجة المتوقعة: **Success. No rows returned**.

## الخطوة ٣: نسخ الرابط والمفتاح
**Project Settings (⚙️)** ← **API**:
- **Project URL** (مثل `https://abcdxyz.supabase.co`).
- **Project API keys → anon public** (يبدأ بـ `eyJhbGci...`).

⚠️ لا تستخدم `service_role` داخل التطبيق إطلاقًا.

## الخطوة ٤: الربط داخل التطبيق
الإعدادات ← المزامنة السحابية:
1. الصق Project URL.
2. الصق مفتاح anon.
3. اكتب رمز مزامنة سريًّا وفريدًا (مثل `fahd-taif-9x7k2`).
4. **اختبار الاتصال** ← «الاتصال ناجح».
5. **رفع للسحابة**.
6. على جهاز آخر: نفس الرابط/المفتاح/الرمز ← **سحب من السحابة**.
7. فعّل **المزامنة التلقائية** لرفع كل تعديل تلقائيًا.

---

## التحقق من نجاح المزامنة
في Supabase: **Table Editor** ← جدول `teacher_data` ← يجب أن ترى صفًّا برمز المزامنة
وحقل `data` ممتلئ.

## حل المشكلات الشائعة
- **الجدول غير موجود (404):** أعد تنفيذ كود SQL في الخطوة ٢.
- **مرفوض (401/permission denied):** تأكد أنك نفّذت أوامر `grant` و`create policy`.
- **Failed to fetch / CORS:** تأكد من صحة الرابط (بدون / في النهاية) ومن الاتصال بالإنترنت.
  Supabase يسمح بالطلبات من المتصفح افتراضيًا؛ لا حاجة لإعداد CORS إضافي.
- **البيانات كبيرة:** إن كان لديك صور/تواقيع كثيرة، قد يكبر حجم `data`. احذف مرفقات غير ضرورية.

## رفع مستوى الأمان (اختياري لاحقًا)
النموذج الحالي: رمز المزامنة هو السر — اجعله طويلًا عشوائيًّا. لأمان أعلى استخدم مصادقة
Supabase (Auth) واربط السياسة بـ `auth.uid()`؛ يتطلب ذلك إضافة تسجيل دخول للتطبيق.

مثال سياسة أكثر تقييدًا (تتطلب مصادقة مستقبلًا):
```sql
-- بديل آمن: كل معلّم يرى صفّه فقط عبر حسابه المُصادق
-- alter policy ... to authenticated using (id = auth.uid()::text);
```
