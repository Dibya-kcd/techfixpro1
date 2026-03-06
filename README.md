# TechFix Pro v2.0 - Flutter App

A complete repair shop management system built with Flutter + Riverpod.

## 📁 File Structure (short names)

```
lib/
├── main.dart           → App entry + root shell + bottom nav (7 tabs)
├── theme/
│   └── t.dart          → Colors (C), ThemeData, buildTheme()
├── models/
│   └── m.dart          → Job, Customer, Product, Technician, CartItem, PartUsed, TimelineEntry
├── data/
│   ├── seed.dart       → Mock data (customers, products, technicians, jobs)
│   └── providers.dart  → Riverpod providers (jobs, cart, products, UI state)
├── widgets/
│   └── w.dart          → Pill, KpiCard, SCard, AppField, AppDropdown, PBtn, PhotoRow, StatusProgress, CostSummary, fmtMoney
└── screens/
    ├── dash.dart         → Dashboard (KPI grid, revenue chart, active jobs, low stock)
    ├── repairs.dart      → Repairs list (tabs: All/Active/Ready/Done, search, FAB)
    ├── repair_detail.dart → Job detail (4 tabs: Overview, Edit, Photos, Timeline)
    ├── add_repair.dart   → 6-step new job wizard
    ├── notify.dart       → WhatsApp/SMS/Email notify bottom sheet
    ├── customers.dart    → Customer list + detail bottom sheet
    ├── inventory.dart    → Inventory with category filters + stock badges
    ├── pos.dart          → Point of Sale (product grid, cart, discount, payment)
    ├── reports.dart      → Analytics (Sales, Repairs, Stock, Finance tabs)
    └── settings.dart     → All settings groups + dark mode toggle
```

## ✅ All Features Implemented

### Repair Job Workflow
- **6-step new job wizard**: Customer → Device → Problem+Cost → Schedule → Photos → Review
- **Sequential status advancement**: One-tap to advance to next status
- **Manual status override**: Set any status at any time
- **Full edit**: All fields editable in the Edit tab
- **Start date + End date**: Set at creation, editable, overdue detection

### Photos
- **Intake photos** at job creation (step 5) and via Photos tab
- **Completion photos** via Photos tab in job detail
- Warning shown if no completion photos before Ready for Pickup
- Photo tips and intake checklist

### Timeline
- Full audit trail with timestamp + user + note
- Every status change logged automatically
- Manual notes can be added anytime

### Customer Notifications
- **WhatsApp / SMS / Email** channel selector
- Pre-filled message with job number, device, problem, total amount
- Message editable before sending
- Notified badge shown in job list after sending

### Billing
- Parts cost + Labor cost fields (separate)
- **Discount** (₹ flat amount) in both job detail and POS
- **POS discount**: ₹ flat OR % percentage with live preview
- Tax rate configurable per job
- Live total = Parts + Labor − Discount + GST(tax%)

### Other
- Low stock & overdue alerts in dashboard + app bar badges
- Customers screen with tier filter + detail sheet
- Inventory with category filter + stock badges
- POS with cart, quantity controls, 5 payment methods
- Reports: Sales charts, Repair stats, Stock report, Finance P&L
- Settings: 5 groups + dark mode toggle

## 🚀 Quick Start

```bash
cd techfix_pro
flutter pub get
flutter run
```

## 📦 Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| flutter_riverpod | ^2.5.1 | State management |
| fl_chart | ^0.68.0 | Charts & graphs |
| google_fonts | ^6.2.1 | Syne font |
| image_picker | ^1.1.2 | Camera/gallery |
| url_launcher | ^6.3.0 | WhatsApp/SMS links |
| intl | ^0.19.0 | Date formatting |
| uuid | ^4.4.0 | ID generation |

## 🎨 Design System

All colors in `lib/theme/t.dart` under class `C`:
- `C.bg` → `#0D1B2A` (dark navy background)
- `C.primary` → `#00C6FF` (cyan blue)
- `C.accent` → `#FF6B35` (orange)
- `C.green` → `#00E676` (success)
- `C.yellow` → `#FFD600` (warning)
- `C.red` → `#FF4444` (error)

Font: **Syne** (Google Fonts) — bold, modern, technical
